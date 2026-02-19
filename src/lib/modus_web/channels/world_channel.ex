defmodule ModusWeb.WorldChannel do
  @moduledoc """
  WorldChannel — Real-time world state streaming.

  On join: sends full grid + agent state.
  Each tick: broadcasts delta (agent positions + tick number).
  Supports agent chat (user→agent via Ollama) and agent detail queries.
  """
  use Phoenix.Channel

  alias Modus.Simulation.{World, Ticker, Agent, AgentSupervisor, EventLog, Building, WorldEvents}
  alias Modus.Intelligence.LlmProvider

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  @impl true
  def join("world:lobby", _payload, socket) do
    Ticker.subscribe()
    Phoenix.PubSub.subscribe(Modus.PubSub, "world_events")
    Phoenix.PubSub.subscribe(Modus.PubSub, "modus:seasons")
    Phoenix.PubSub.subscribe(Modus.PubSub, "modus:rules")
    Phoenix.PubSub.subscribe(Modus.PubSub, "prayers")
    Phoenix.PubSub.subscribe(Modus.PubSub, "agent_chats")
    state = build_full_state()
    {:ok, state, assign(socket, selected_agent_id: nil, prev_agents: %{})}
  end

  # ── handle_in ───────────────────────────────────────────────

  @impl true
  def handle_in("start", _payload, socket) do
    ensure_world_running()
    Ticker.run()
    broadcast!(socket, "status_change", %{status: "running"})
    {:noreply, socket}
  end

  def handle_in("pause", _payload, socket) do
    Ticker.pause()
    broadcast!(socket, "status_change", %{status: "paused"})
    {:noreply, socket}
  end

  def handle_in("reset", _payload, socket) do
    Ticker.pause()
    AgentSupervisor.terminate_all()
    if Process.whereis(World), do: GenServer.stop(World)
    world = World.new("Genesis")
    {:ok, _} = World.start_link(world)
    World.spawn_initial_agents(10)
    Ticker.run()
    broadcast!(socket, "status_change", %{status: "running"})
    state = build_full_state()
    broadcast!(socket, "full_state", state)
    {:noreply, socket}
  end

  def handle_in("set_speed", %{"speed" => speed}, socket) when speed in [1, 5, 10] do
    Ticker.set_speed(speed)
    broadcast!(socket, "speed_change", %{speed: speed})
    {:noreply, socket}
  end

  def handle_in("inject_event", %{"event_type" => event_type}, socket) do
    tick = if Process.whereis(Ticker), do: Ticker.current_tick(), else: 0
    agents = get_agent_list()
    alive = Enum.filter(agents, & &1.alive)

    case event_type do
      "natural_disaster" ->
        # Kill a random agent and log
        if alive != [] do
          victim = Enum.random(alive)

          try do
            GenServer.cast(
              {:via, Registry, {Modus.AgentRegistry, victim.id}},
              :kill
            )
          catch
            :exit, _ -> :ok
          end

          EventLog.log(:disaster, tick, [victim.id], %{
            type: :natural_disaster,
            victim: victim.name
          })
        end

      "migrant" ->
        # Spawn a new agent
        if Process.whereis(World) do
          World.spawn_initial_agents(1)
        end

        EventLog.log(:migration, tick, [], %{type: :migrant_arrival})

      "resource_bonus" ->
        # Boost hunger for all alive agents
        for agent <- alive do
          try do
            GenServer.cast(
              {:via, Registry, {Modus.AgentRegistry, agent.id}},
              {:boost_need, :hunger, 30.0}
            )
          catch
            :exit, _ -> :ok
          end
        end

        EventLog.log(:resource, tick, [], %{type: :resource_bonus})

      _ ->
        :ok
    end

    # Send updated state
    updated_agents = get_agent_list()

    broadcast!(socket, "delta", %{
      tick: tick,
      agent_count: length(updated_agents),
      agents: updated_agents
    })

    {:noreply, socket}
  end

  def handle_in(
        "create_world",
        %{"template" => template, "population" => pop, "danger" => danger} = payload,
        socket
      ) do
    Ticker.pause()
    AgentSupervisor.terminate_all()
    if Process.whereis(World), do: GenServer.stop(World)

    opts = [template: String.to_atom(template), danger_level: String.to_atom(danger)]
    opts = if payload["seed"], do: Keyword.put(opts, :seed, payload["seed"]), else: opts

    opts =
      if payload["grid_size"],
        do: Keyword.put(opts, :grid_size, {payload["grid_size"], payload["grid_size"]}),
        else: opts

    world = World.new("Genesis", opts)
    {:ok, _} = World.start_link(world)
    pop_count = max(2, min(pop, 50))
    World.spawn_initial_agents(pop_count)
    Ticker.run()
    broadcast!(socket, "status_change", %{status: "running"})
    state = build_full_state()
    broadcast!(socket, "full_state", state)
    {:noreply, socket}
  end

  def handle_in("chat_agent", %{"agent_id" => agent_id, "message" => message}, socket) do
    require Logger
    Logger.info("MODUS chat_agent received: agent_id=#{agent_id} message=#{inspect(message)}")
    channel_pid = self()

    Task.start(fn ->
      try do
        case Modus.Protocol.Bridge.process(agent_id, message) do
          {:ok, reply} ->
            EventLog.log(:conversation, 0, [agent_id], %{
              type: :user_chat,
              user_message: message,
              agent_reply: reply
            })

            Logger.info("MODUS chat_reply ready for #{agent_id}: #{String.slice(reply, 0..80)}")
            send(channel_pid, {:chat_reply, agent_id, reply})

          _ ->
            send(channel_pid, {:chat_reply, agent_id, "I can't respond right now..."})
        end
      catch
        kind, reason ->
          Logger.warning("Chat failed for #{agent_id}: #{inspect({kind, reason})}")
          send(channel_pid, {:chat_reply, agent_id, "Something went wrong..."})
      end
    end)

    {:noreply, socket}
  end

  def handle_in("get_llm_config", _payload, socket) do
    config = LlmProvider.get_config()

    {:reply,
     {:ok,
      %{
        provider: to_string(config.provider),
        model: config.model,
        base_url: config.base_url || "",
        api_key: config.api_key || ""
      }}, socket}
  end

  def handle_in("set_llm_config", payload, socket) do
    provider =
      case payload["provider"] do
        "gemini" -> :gemini
        _ -> :ollama
      end

    config = %{
      provider: provider,
      model: payload["model"] || "llama3.2:3b-instruct-q4_K_M",
      base_url: payload["base_url"],
      api_key: payload["api_key"]
    }

    LlmProvider.set_config(config)
    {:reply, {:ok, %{status: "saved"}}, socket}
  end

  def handle_in("test_llm_connection", _payload, socket) do
    case LlmProvider.test_connection() do
      :ok -> {:reply, {:ok, %{status: "ok"}}, socket}
      {:error, reason} -> {:reply, {:ok, %{status: "error", reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("select_agent", %{"agent_id" => agent_id}, socket) do
    {:reply, :ok, assign(socket, :selected_agent_id, agent_id)}
  end

  def handle_in("deselect_agent", _payload, socket) do
    {:reply, :ok, assign(socket, :selected_agent_id, nil)}
  end

  def handle_in("save_world", %{"name" => name}, socket) do
    case Modus.Persistence.WorldPersistence.save(name) do
      {:ok, info} ->
        {:reply, {:ok, info}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("save_world", _payload, socket) do
    case Modus.Persistence.WorldPersistence.save() do
      {:ok, info} ->
        {:reply, {:ok, info}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("load_world", %{"world_id" => world_id}, socket) do
    case Modus.Persistence.WorldPersistence.load(world_id) do
      {:ok, info} ->
        # Send full state to all clients
        state = build_full_state()
        broadcast!(socket, "full_state", state)
        broadcast!(socket, "status_change", %{status: "paused"})
        {:reply, {:ok, info}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("list_worlds", _payload, socket) do
    worlds = Modus.Persistence.WorldPersistence.list()
    {:reply, {:ok, %{worlds: worlds}}, socket}
  end

  def handle_in("delete_world", %{"world_id" => world_id}, socket) do
    case Modus.Persistence.WorldPersistence.delete(world_id) do
      {:ok, _} -> {:reply, {:ok, %{status: "deleted"}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # ── World Builder: Paint Terrain ──────────────────────────────

  @valid_terrains ~w(grass forest water mountain desert sand farm flowers swamp tundra)

  def handle_in("paint_terrain", %{"x" => x, "y" => y, "terrain" => terrain}, socket)
      when is_integer(x) and is_integer(y) and terrain in @valid_terrains do
    terrain_atom = String.to_existing_atom(terrain)

    case World.paint_terrain({x, y}, terrain_atom) do
      :ok ->
        # Broadcast tile update to all clients
        broadcast!(socket, "terrain_painted", %{x: x, y: y, terrain: terrain})
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("paint_terrain", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_params"}}, socket}
  end

  # ── World Builder: Place Resource Node ─────────────────────

  @valid_nodes ~w(food_source water_well wood_pile stone_quarry)

  def handle_in("place_resource", %{"x" => x, "y" => y, "node_type" => node_type}, socket)
      when is_integer(x) and is_integer(y) and node_type in @valid_nodes do
    node_atom = String.to_existing_atom(node_type)

    case World.place_resource_node({x, y}, node_atom) do
      :ok ->
        broadcast!(socket, "resource_placed", %{x: x, y: y, node_type: node_type})
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("place_resource", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_params"}}, socket}
  end

  # ── God Mode: Place Building ──────────────────────────────

  @valid_building_types ~w(hut house farm market well watchtower)

  def handle_in("place_building", %{"x" => x, "y" => y, "type" => type}, socket)
      when is_integer(x) and is_integer(y) and type in @valid_building_types do
    building_type = String.to_existing_atom(type)
    tick = if Process.whereis(Ticker), do: Ticker.current_tick(), else: 0
    building = Building.place(building_type, {x, y}, nil, tick)
    EventLog.log(:building, tick, [], %{type: building_type, position: [x, y], god_mode: true})

    broadcast!(socket, "building_placed", %{
      building: hd(Building.serialize_all() |> Enum.filter(&(&1.id == building.id)))
    })

    {:reply, :ok, socket}
  end

  def handle_in("place_building", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_params"}}, socket}
  end

  # ── Gather Resource (triggered by client) ──────────────────

  def handle_in("gather_resource", %{"agent_id" => agent_id, "x" => x, "y" => y}, socket) do
    try do
      GenServer.cast(
        {:via, Registry, {Modus.AgentRegistry, agent_id}},
        {:gather_at, {x, y}}
      )

      {:reply, :ok, socket}
    catch
      :exit, _ -> {:reply, {:error, %{reason: "agent_not_found"}}, socket}
    end
  end

  # ── Agent Designer: Spawn Custom Agent ────────────────────────

  @valid_occupations ~w(farmer merchant explorer healer builder guard hunter fisher artist scholar)
  @valid_moods ~w(happy calm anxious eager)
  @valid_animal_types ~w(deer rabbit wolf)

  def handle_in("spawn_custom_agent", payload, socket) do
    require Logger
    Logger.info("MODUS spawn_custom_agent: #{inspect(payload)}")

    name = payload["name"] || "Unnamed"

    occupation =
      if payload["occupation"] in @valid_occupations,
        do: String.to_atom(payload["occupation"]),
        else: :explorer

    mood =
      if payload["mood"] in @valid_moods,
        do: String.to_atom(payload["mood"]),
        else: :calm

    # Parse personality (Big Five 0-100 → 0.0-1.0)
    p = payload["personality"] || %{}

    personality = %{
      openness: (p["o"] || 50) / 100,
      conscientiousness: (p["c"] || 50) / 100,
      extraversion: (p["e"] || 50) / 100,
      agreeableness: (p["a"] || 50) / 100,
      neuroticism: (p["n"] || 50) / 100
    }

    # Position — use provided or find walkable
    position =
      if payload["x"] && payload["y"] do
        {payload["x"], payload["y"]}
      else
        if Process.whereis(World) do
          state = World.get_state()
          {max_x, max_y} = state.grid_size
          find_walkable({max_x, max_y}, state.grid_table)
        else
          {50, 50}
        end
      end

    agent = Agent.new_custom(name, position, occupation, personality, mood)

    case AgentSupervisor.spawn_agent(agent) do
      {:ok, _pid} ->
        tick = if Process.whereis(Ticker), do: Ticker.current_tick(), else: 0

        EventLog.log(:birth, tick, [agent.id], %{
          name: name,
          type: :custom_spawn,
          occupation: occupation
        })

        agents = get_agent_list()

        broadcast!(socket, "delta", %{
          tick: tick,
          agent_count: length(agents),
          agents: agents
        })

        {:reply, {:ok, %{id: agent.id, name: name}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("spawn_animal", %{"type" => animal_type, "x" => x, "y" => y}, socket)
      when animal_type in @valid_animal_types do
    require Logger
    Logger.info("MODUS spawn_animal: #{animal_type} at #{x},#{y}")

    # Animals are simple agents with animal occupation
    name =
      case animal_type do
        "deer" -> "Deer"
        "rabbit" -> "Rabbit"
        "wolf" -> "Wolf"
      end

    personality = %{
      openness: :rand.uniform() * 0.5,
      conscientiousness: :rand.uniform() * 0.3,
      extraversion: :rand.uniform() * 0.4,
      agreeableness: if(animal_type == "wolf", do: 0.1, else: 0.7),
      neuroticism: if(animal_type == "rabbit", do: 0.8, else: 0.3)
    }

    agent = Agent.new_custom(name, {x, y}, String.to_atom(animal_type), personality, :calm)

    case AgentSupervisor.spawn_agent(agent) do
      {:ok, _pid} ->
        tick = if Process.whereis(Ticker), do: Ticker.current_tick(), else: 0

        EventLog.log(:birth, tick, [agent.id], %{
          name: name,
          type: :animal_spawn,
          animal: animal_type
        })

        agents = get_agent_list()

        broadcast!(socket, "delta", %{
          tick: tick,
          agent_count: length(agents),
          agents: agents
        })

        {:reply, {:ok, %{id: agent.id, name: name}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("spawn_animal", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_animal_type"}}, socket}
  end

  # ── Prayer System ────────────────────────────────────────────

  def handle_in("get_prayers", payload, socket) do
    opts = []
    opts = if payload["status"], do: Keyword.put(opts, :status, String.to_existing_atom(payload["status"])), else: opts
    opts = if payload["agent_id"], do: Keyword.put(opts, :agent_id, payload["agent_id"]), else: opts
    opts = if payload["limit"], do: Keyword.put(opts, :limit, payload["limit"]), else: opts
    prayers = Modus.World.PrayerSystem.list_prayers(opts)
    {:reply, {:ok, %{prayers: prayers}}, socket}
  end

  def handle_in("respond_prayer", %{"prayer_id" => prayer_id, "response" => response}, socket)
      when response in ["positive", "negative"] do
    response_atom = String.to_existing_atom(response)
    case Modus.World.PrayerSystem.respond(prayer_id, response_atom) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("respond_prayer", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_params"}}, socket}
  end

  # ── Agent Chat Viewer ──────────────────────────────────────

  def handle_in("get_agent_chats", payload, socket) do
    opts = []
    opts = if payload["agent_id"], do: Keyword.put(opts, :agent_id, payload["agent_id"]), else: opts
    opts = if payload["topic"], do: Keyword.put(opts, :topic, payload["topic"]), else: opts
    opts = if payload["limit"], do: Keyword.put(opts, :limit, payload["limit"]), else: opts

    chats =
      Modus.World.AgentChatViewer.list_chats(opts)
      |> Enum.map(&Modus.World.AgentChatViewer.serialize_chat/1)

    {:reply, {:ok, %{chats: chats}}, socket}
  end

  def handle_in("subscribe_agent_chats", _payload, socket) do
    # Already subscribed via join; this is a client acknowledgment
    {:reply, :ok, socket}
  end

  # ── Export & Share ──────────────────────────────────────────

  def handle_in("export_world", _payload, socket) do
    case Modus.Persistence.WorldExport.export_json() do
      {:ok, json} -> {:reply, {:ok, %{json: json}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("export_share", _payload, socket) do
    case Modus.Persistence.WorldExport.export_base64() do
      {:ok, b64} -> {:reply, {:ok, %{share_code: b64}}, socket}
      {:error, reason} -> {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("import_world", %{"json" => json}, socket) do
    case Modus.Persistence.WorldExport.import_json(json) do
      {:ok, info} ->
        state = build_full_state()
        broadcast!(socket, "full_state", state)
        {:reply, {:ok, info}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("import_share", %{"share_code" => code}, socket) do
    case Modus.Persistence.WorldExport.import_base64(code) do
      {:ok, info} ->
        state = build_full_state()
        broadcast!(socket, "full_state", state)
        {:reply, {:ok, info}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # ── World Events (God Mode) ────────────────────────────────

  @valid_world_events ~w(storm earthquake meteor_shower plague golden_age flood fire)

  def handle_in("trigger_world_event", %{"event_type" => event_type}, socket)
      when event_type in @valid_world_events do
    tick = if Process.whereis(Ticker), do: Ticker.current_tick(), else: 0
    event_atom = String.to_existing_atom(event_type)
    {:ok, _event} = WorldEvents.trigger(event_atom, tick: tick)
    {:reply, :ok, socket}
  end

  def handle_in("trigger_world_event", _payload, socket) do
    {:reply, {:error, %{reason: "invalid_event_type"}}, socket}
  end

  def handle_in("get_world_events", _payload, socket) do
    events = WorldEvents.serialize()
    {:reply, {:ok, %{events: events}}, socket}
  end

  # ── Rules Engine ────────────────────────────────────────────

  def handle_in("get_rules", _payload, socket) do
    rules = Modus.Simulation.RulesEngine.serialize()
    presets = Modus.Simulation.RulesEngine.preset_names()
    {:reply, {:ok, %{rules: rules, presets: presets}}, socket}
  end

  def handle_in("update_rules", %{"rules" => rules_params}, socket) do
    changes = %{}

    changes =
      if rules_params["time_speed"],
        do: Map.put(changes, :time_speed, ensure_float(rules_params["time_speed"])),
        else: changes

    changes =
      if rules_params["resource_abundance"],
        do:
          Map.put(
            changes,
            :resource_abundance,
            String.to_existing_atom(rules_params["resource_abundance"])
          ),
        else: changes

    changes =
      if rules_params["danger_level"],
        do:
          Map.put(changes, :danger_level, String.to_existing_atom(rules_params["danger_level"])),
        else: changes

    changes =
      if rules_params["social_tendency"],
        do: Map.put(changes, :social_tendency, ensure_float(rules_params["social_tendency"])),
        else: changes

    changes =
      if rules_params["birth_rate"],
        do: Map.put(changes, :birth_rate, ensure_float(rules_params["birth_rate"])),
        else: changes

    changes =
      if rules_params["building_speed"],
        do: Map.put(changes, :building_speed, ensure_float(rules_params["building_speed"])),
        else: changes

    changes =
      if rules_params["mutation_rate"],
        do: Map.put(changes, :mutation_rate, ensure_float(rules_params["mutation_rate"])),
        else: changes

    Modus.Simulation.RulesEngine.update(changes)
    rules = Modus.Simulation.RulesEngine.serialize()
    broadcast!(socket, "rules_changed", %{rules: rules})
    {:reply, {:ok, %{rules: rules}}, socket}
  end

  def handle_in("apply_preset", %{"preset" => preset_name}, socket) do
    case Modus.Simulation.RulesEngine.apply_preset(preset_name) do
      {:ok, _rules} ->
        rules = Modus.Simulation.RulesEngine.serialize()
        broadcast!(socket, "rules_changed", %{rules: rules})
        {:reply, {:ok, %{rules: rules}}, socket}

      {:error, :unknown_preset} ->
        {:reply, {:error, %{reason: "unknown_preset"}}, socket}
    end
  end

  def handle_in("get_agent_detail", %{"agent_id" => agent_id}, socket) do
    try do
      state = Agent.get_state(agent_id)
      events = EventLog.recent(agent_id: agent_id, limit: 5)
      detail = build_agent_detail(state, events)
      {:reply, {:ok, detail}, assign(socket, :selected_agent_id, agent_id)}
    catch
      :exit, _ ->
        {:reply, {:error, %{reason: "agent_not_found"}}, socket}
    end
  end

  def handle_in("add_goal", %{"agent_id" => agent_id, "type" => type_str} = payload, socket) do
    type = String.to_existing_atom(type_str)
    target = payload["target"]
    goal = Modus.Mind.Goals.add_goal(agent_id, type, target)

    {:reply,
     {:ok, %{goal: hd(Modus.Mind.Goals.serialize(agent_id) |> Enum.filter(&(&1.id == goal.id)))}},
     socket}
  rescue
    _ -> {:reply, {:error, %{reason: "invalid_goal_type"}}, socket}
  end

  def handle_in("remove_goal", %{"agent_id" => agent_id, "goal_id" => goal_id}, socket) do
    Modus.Mind.Goals.remove_goal(agent_id, goal_id)
    {:reply, {:ok, %{}}, socket}
  end

  # ── handle_info ─────────────────────────────────────────────

  @impl true
  def handle_info({:tick, tick_number}, socket) do
    # Agents now self-tick via PubSub — we just query state
    agents = get_agent_list()

    env =
      try do
        Modus.Simulation.Environment.get_state()
      catch
        :exit, _ -> %{time_of_day: :day, cycle_progress: 0.0}
      end

    buildings =
      try do
        Building.serialize_all()
      catch
        _, _ -> []
      end

    neighborhoods =
      try do
        Building.serialize_neighborhoods()
      catch
        _, _ -> []
      end

    world_events =
      try do
        WorldEvents.serialize()
      catch
        _, _ -> []
      end

    seasons =
      try do
        Modus.Simulation.Seasons.serialize()
      catch
        _, _ ->
          %{
            season: "spring",
            season_name: "Spring",
            emoji: "🌸",
            year: 1,
            progress: 0.0,
            tint: 0x88DD88,
            tint_alpha: 0.08,
            terrain_shift: %{},
            growth_modifier: 1.0
          }
      end

    weather =
      try do
        Modus.Simulation.Weather.serialize()
      catch
        _, _ ->
          %{
            current: "clear",
            name: "Clear",
            emoji: "☀️",
            move_mod: 1.0,
            gather_mod: 1.0,
            mood_mod: 0.0,
            crop_mod: 1.0,
            severe_event: nil,
            ticks_remaining: 0,
            forecast: []
          }
      end

    rules =
      try do
        Modus.Simulation.RulesEngine.serialize()
      catch
        _, _ -> %{}
      end

    # v7.4: Delta compression — only send changed agent fields
    prev_agents = socket.assigns[:prev_agents] || %{}

    {compressed_agents, new_prev} =
      agents
      |> Enum.map_reduce(prev_agents, fn agent, acc ->
        prev = Map.get(acc, agent.id)
        compressed = if prev, do: agent_delta(prev, agent), else: agent
        {compressed, Map.put(acc, agent.id, agent)}
      end)

    # Remove dead agents no longer in list
    current_ids = MapSet.new(agents, & &1.id)
    new_prev = Map.filter(new_prev, fn {id, _} -> MapSet.member?(current_ids, id) end)

    delta = %{
      tick: tick_number,
      agent_count: length(Enum.filter(agents, & &1.alive)),
      agents: compressed_agents,
      buildings: buildings,
      neighborhoods: neighborhoods,
      world_events: world_events,
      time_of_day: to_string(env.time_of_day),
      cycle_progress: Float.round(ensure_float(env.cycle_progress), 4),
      ambient_color: Map.get(env, :ambient_color, 0x000000),
      ambient_alpha: Float.round(ensure_float(Map.get(env, :ambient_alpha, 0.0)), 4),
      day_phase: to_string(Map.get(env, :day_phase, :day)),
      season: seasons,
      weather: weather,
      rules: rules
    }

    push(socket, "delta", delta)
    socket = assign(socket, :prev_agents, new_prev)

    # Push selected agent detail every 10 ticks for live panel update
    selected_id = socket.assigns[:selected_agent_id]

    if selected_id && rem(tick_number, 10) == 0 do
      try do
        state = Agent.get_state(selected_id)
        events = EventLog.recent(agent_id: selected_id, limit: 5)
        detail = build_agent_detail(state, events)
        push(socket, "agent_detail_update", %{detail: detail})
      catch
        :exit, _ -> :ok
      end
    end

    {:noreply, socket}
  end

  def handle_info({:world_event, event_data}, socket) do
    push(socket, "world_event", event_data)
    {:noreply, socket}
  end

  def handle_info({:event_ended, event_data}, socket) do
    push(socket, "world_event_ended", event_data)
    {:noreply, socket}
  end

  def handle_info({:season_change, season, config}, socket) do
    push(socket, "season_change", %{
      season: to_string(season),
      season_name: config.name,
      emoji: config.emoji,
      tint: config.tint,
      tint_alpha: config.tint_alpha,
      terrain_shift:
        config.terrain_shift
        |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
        |> Enum.into(%{}),
      growth_modifier: config.growth_modifier
    })

    {:noreply, socket}
  end

  def handle_info({:rules_changed, _rules}, socket) do
    push(socket, "rules_changed", %{rules: Modus.Simulation.RulesEngine.serialize()})
    {:noreply, socket}
  end

  def handle_info({:new_prayer, prayer}, socket) do
    push(socket, "new_prayer", %{prayer: prayer})
    {:noreply, socket}
  end

  def handle_info({:prayer_answered, prayer}, socket) do
    push(socket, "prayer_answered", %{prayer: prayer})
    {:noreply, socket}
  end

  def handle_info({:new_agent_chat, chat_data}, socket) do
    push(socket, "new_agent_chat", %{chat: chat_data})
    {:noreply, socket}
  end

  def handle_info({:chat_reply, agent_id, reply}, socket) do
    require Logger
    Logger.info("MODUS pushing chat_reply to client for #{agent_id}")
    push(socket, "chat_reply", %{agent_id: agent_id, reply: reply})
    {:noreply, socket}
  end

  # ── Helpers ───────────────────────────────────────────────

  # v7.4: Delta compression — only include changed fields (always include id)
  defp agent_delta(prev, current) do
    base = %{id: current.id}

    [:name, :x, :y, :occupation, :action, :alive, :conatus, :conatus_energy,
     :affect, :reasoning, :age, :age_stage, :age_emoji, :conversing_with, :group]
    |> Enum.reduce(base, fn key, acc ->
      old_val = Map.get(prev, key)
      new_val = Map.get(current, key)
      if old_val == new_val, do: acc, else: Map.put(acc, key, new_val)
    end)
    |> maybe_add_friends(prev, current)
  end

  defp maybe_add_friends(delta, prev, current) do
    if Map.get(prev, :friends) == Map.get(current, :friends),
      do: delta,
      else: Map.put(delta, :friends, current.friends)
  end

  defp find_walkable({max_x, max_y}, table) do
    x = :rand.uniform(max_x) - 1
    y = :rand.uniform(max_y) - 1

    case :ets.lookup(table, {x, y}) do
      [{{^x, ^y}, %{terrain: terrain}}] when terrain in [:grass, :forest] -> {x, y}
      _ -> find_walkable({max_x, max_y}, table)
    end
  end

  defp build_full_state do
    world_state =
      if Process.whereis(World), do: World.get_state(), else: nil

    grid = if world_state, do: build_grid(world_state), else: []
    agents = get_agent_list()

    tick =
      if Process.whereis(Ticker), do: Ticker.current_tick(), else: 0

    status =
      if Process.whereis(Ticker),
        do: Ticker.status().state |> to_string(),
        else: "paused"

    env =
      try do
        Modus.Simulation.Environment.get_state()
      catch
        :exit, _ -> %{time_of_day: :day, cycle_progress: 0.0}
      end

    grid_size = if world_state, do: world_state.grid_size, else: {100, 100}
    {gw, gh} = grid_size

    buildings =
      try do
        Building.serialize_all()
      catch
        _, _ -> []
      end

    neighborhoods =
      try do
        Building.serialize_neighborhoods()
      catch
        _, _ -> []
      end

    world_events =
      try do
        WorldEvents.serialize()
      catch
        _, _ -> []
      end

    seasons =
      try do
        Modus.Simulation.Seasons.serialize()
      catch
        _, _ ->
          %{
            season: "spring",
            season_name: "Spring",
            emoji: "🌸",
            year: 1,
            progress: 0.0,
            tint: 0x88DD88,
            tint_alpha: 0.08,
            terrain_shift: %{},
            growth_modifier: 1.0
          }
      end

    rules =
      try do
        Modus.Simulation.RulesEngine.serialize()
      catch
        _, _ -> %{}
      end

    %{
      grid: grid,
      agents: agents,
      buildings: buildings,
      neighborhoods: neighborhoods,
      world_events: world_events,
      tick: tick,
      status: status,
      agent_count: length(agents),
      grid_width: gw,
      grid_height: gh,
      time_of_day: to_string(env.time_of_day),
      cycle_progress: Float.round(ensure_float(env.cycle_progress), 4),
      ambient_color: Map.get(env, :ambient_color, 0x000000),
      ambient_alpha: Float.round(ensure_float(Map.get(env, :ambient_alpha, 0.0)), 4),
      day_phase: to_string(Map.get(env, :day_phase, :day)),
      season: seasons,
      rules: rules
    }
  end

  defp build_grid(world_state) do
    {max_x, max_y} = world_state.grid_size

    for x <- 0..(max_x - 1), y <- 0..(max_y - 1) do
      case :ets.lookup(world_state.grid_table, {x, y}) do
        [{{^x, ^y}, cell}] ->
          biome = Map.get(cell, :biome, :plains) |> to_string()
          base = %{x: x, y: y, terrain: cell.terrain |> to_string(), biome: biome}
          nodes = Map.get(cell, :resource_nodes, [])

          if nodes == [],
            do: base,
            else: Map.put(base, :resource_nodes, Enum.map(nodes, &to_string/1))

        _ ->
          %{x: x, y: y, terrain: "grass"}
      end
    end
  end

  defp get_agent_list do
    Modus.AgentRegistry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {_id, pid} ->
      try do
        state = GenServer.call(pid, :get_state, 2_000)
        {ax, ay} = state.position

        %{
          id: state.id,
          name: state.name,
          x: ax,
          y: ay,
          occupation: state.occupation |> to_string(),
          action: state.current_action |> to_string(),
          alive: state.alive?,
          conatus: state.conatus_score,
          conatus_energy: state.conatus_energy,
          affect: state.affect_state |> to_string(),
          reasoning: state.last_reasoning != nil,
          friends:
            try do
              Modus.Mind.Cerebro.SocialNetwork.get_friends(state.id) |> Enum.take(3)
            catch
              _, _ -> []
            end
            |> Enum.take(5)
            |> Enum.map(fn f ->
              %{id: f.id, strength: Float.round(ensure_float(f.strength), 2)}
            end),
          age: state.age,
          age_stage: Modus.Simulation.Aging.stage(state.age) |> to_string(),
          age_emoji: Modus.Simulation.Aging.emoji(Modus.Simulation.Aging.stage(state.age)),
          conversing_with: Map.get(state, :conversing_with),
          group:
            case Modus.Mind.Cerebro.Group.get_agent_group(state.id) do
              nil -> nil
              g -> %{id: g.id, name: g.name, color: g.color, is_leader: g.leader_id == state.id}
            end
        }
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # NOTE: trigger_agent_conversations removed — Cerebro AgentConversation handles all agent conversations now.

  defp build_agent_detail(state, events) do
    %{
      id: state.id,
      name: state.name,
      occupation: to_string(state.occupation),
      alive: state.alive?,
      age: state.age,
      conatus: state.conatus_score,
      position: %{x: elem(state.position, 0), y: elem(state.position, 1)},
      personality: %{
        openness: Float.round(ensure_float(state.personality.openness), 2),
        conscientiousness: Float.round(ensure_float(state.personality.conscientiousness), 2),
        extraversion: Float.round(ensure_float(state.personality.extraversion), 2),
        agreeableness: Float.round(ensure_float(state.personality.agreeableness), 2),
        neuroticism: Float.round(ensure_float(state.personality.neuroticism), 2)
      },
      needs: %{
        hunger: Float.round(ensure_float(state.needs.hunger), 1),
        social: Float.round(ensure_float(state.needs.social), 1),
        rest: Float.round(ensure_float(state.needs.rest), 1),
        shelter: Float.round(ensure_float(state.needs.shelter), 1)
      },
      relationships:
        state.relationships
        |> Enum.map(fn {id, {type, strength}} ->
          %{agent_id: id, type: to_string(type), strength: strength}
        end),
      conatus_energy: state.conatus_energy,
      affect_state: to_string(state.affect_state),
      affect_history:
        state.affect_history
        |> Enum.take(5)
        |> Enum.map(fn entry ->
          %{
            tick: entry.tick,
            from: to_string(entry.from),
            to: to_string(entry.to),
            reason: entry.reason
          }
        end),
      action: to_string(state.current_action),
      recent_events:
        events
        |> Enum.map(fn e ->
          %{id: e.id, type: to_string(e.type), tick: e.tick, data: e.data}
        end),
      memories:
        try do
          Modus.Mind.AffectMemory.recall(state.id, limit: 10)
          |> Enum.map(fn m ->
            %{
              tick: m.tick,
              affect_from: to_string(m.affect_from),
              affect_to: to_string(m.affect_to),
              reason: m.reason,
              salience: Float.round(ensure_float(m.salience), 2),
              position: %{x: elem(m.position, 0), y: elem(m.position, 1)}
            }
          end)
        catch
          _, _ -> []
        end,
      last_reasoning: state.last_reasoning,
      aging: Modus.Simulation.Aging.serialize(state.id, state.age),
      population_pyramid: Modus.Simulation.Aging.population_pyramid(),
      skills: Modus.Mind.Learning.to_map(state.id),
      inventory: state.inventory || %{},
      goals: Modus.Mind.Goals.serialize(state.id),
      culture: Modus.Mind.Culture.serialize(state.id)
    }
  end

  defp ensure_world_running do
    unless Process.whereis(World) do
      world = World.new("Genesis")
      {:ok, _} = World.start_link(world)
    end

    agents = get_agent_list()

    if Enum.empty?(agents) do
      World.spawn_initial_agents(10)
    end
  end
end
