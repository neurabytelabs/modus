defmodule ModusWeb.WorldChannel do
  @moduledoc """
  WorldChannel — Real-time world state streaming.

  On join: sends full grid + agent state.
  Each tick: broadcasts delta (agent positions + tick number).
  Supports agent chat (user→agent via Ollama) and agent detail queries.
  """
  use Phoenix.Channel

  alias Modus.Simulation.{World, Ticker, Agent, AgentSupervisor, EventLog}
  alias Modus.Intelligence.LlmProvider

  @impl true
  def join("world:lobby", _payload, socket) do
    Ticker.subscribe()
    state = build_full_state()
    {:ok, state, assign(socket, :selected_agent_id, nil)}
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
          EventLog.log(:disaster, tick, [victim.id], %{type: :natural_disaster, victim: victim.name})
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

      _ -> :ok
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

  def handle_in("create_world", %{"template" => template, "population" => pop, "danger" => danger}, socket) do
    Ticker.pause()
    AgentSupervisor.terminate_all()
    if Process.whereis(World), do: GenServer.stop(World)

    world = World.new("Genesis", template: String.to_atom(template), danger_level: String.to_atom(danger))
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
        state = Agent.get_state(agent_id)

        reply =
          case LlmProvider.chat(state, message) do
            {:ok, text} -> text
            :fallback -> fallback_chat_reply(state)
            _ -> fallback_chat_reply(state)
          end

        EventLog.log(:conversation, 0, [agent_id], %{
          type: :user_chat,
          user_message: message,
          agent_reply: reply
        })

        Logger.info("MODUS chat_reply ready for #{agent_id}: #{String.slice(reply, 0..80)}")
        send(channel_pid, {:chat_reply, agent_id, reply})
      catch
        kind, reason ->
          Logger.warning("Chat failed for #{agent_id}: #{inspect({kind, reason})}")
          send(channel_pid, {:chat_reply, agent_id, "*yawns and looks around* ...I'm not sure what to say right now."})
      end
    end)

    {:noreply, socket}
  end

  def handle_in("get_llm_config", _payload, socket) do
    config = LlmProvider.get_config()
    {:reply, {:ok, %{
      provider: to_string(config.provider),
      model: config.model,
      base_url: config.base_url || "",
      api_key: config.api_key || ""
    }}, socket}
  end

  def handle_in("set_llm_config", payload, socket) do
    provider = case payload["provider"] do
      "antigravity" -> :antigravity
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

  # ── handle_info ─────────────────────────────────────────────

  @impl true
  def handle_info({:tick, tick_number}, socket) do
    # Agents now self-tick via PubSub — we just query state
    agents = get_agent_list()

    delta = %{
      tick: tick_number,
      agent_count: length(Enum.filter(agents, & &1.alive)),
      agents: agents
    }

    push(socket, "delta", delta)

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

  def handle_info({:chat_reply, agent_id, reply}, socket) do
    require Logger
    Logger.info("MODUS pushing chat_reply to client for #{agent_id}")
    push(socket, "chat_reply", %{agent_id: agent_id, reply: reply})
    {:noreply, socket}
  end

  # ── Helpers ───────────────────────────────────────────────

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

    %{
      grid: grid,
      agents: agents,
      tick: tick,
      status: status,
      agent_count: length(agents)
    }
  end

  defp build_grid(world_state) do
    {max_x, max_y} = world_state.grid_size

    for x <- 0..(max_x - 1), y <- 0..(max_y - 1) do
      case :ets.lookup(world_state.grid_table, {x, y}) do
        [{{^x, ^y}, cell}] ->
          %{x: x, y: y, terrain: cell.terrain |> to_string()}

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
          friends: (try do Modus.Mind.Cerebro.SocialNetwork.get_friends(state.id) |> Enum.take(3) catch _, _ -> [] end)
                   |> Enum.take(5)
                   |> Enum.map(fn f -> %{id: f.id, strength: Float.round(f.strength, 2)} end),
          conversing_with: Map.get(state, :conversing_with)
        }
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp trigger_agent_conversations(agents, tick) do
    alive = Enum.filter(agents, & &1.alive)

    pairs =
      for a <- alive, b <- alive, a.id < b.id,
          abs(a.x - b.x) <= 3 and abs(a.y - b.y) <= 3,
          do: {a.id, b.id}

    pairs
    |> Enum.take_random(min(1, length(pairs)))
    |> Enum.each(fn {id_a, id_b} ->
      Task.start(fn ->
        try do
          state_a = Agent.get_state(id_a)
          state_b = Agent.get_state(id_b)

          case LlmProvider.conversation(state_a, state_b, %{tick: tick}) do
            dialogue when is_list(dialogue) ->
              EventLog.log(:conversation, tick, [id_a, id_b], %{
                type: :agent_chat,
                dialogue:
                  Enum.map(dialogue, fn {speaker, line} ->
                    %{speaker: speaker, line: line}
                  end)
              })

              update_relationship(id_a, id_b, :acquaintance, 0.1)
              update_relationship(id_b, id_a, :acquaintance, 0.1)

            :fallback ->
              fallback_lines = ["Merhaba!", "Nasılsın?", "Hava güzel bugün.", "Dikkat et!", "Birlikte çalışalım mı?"]
              dialogue = [
                {state_a.name, Enum.random(fallback_lines)},
                {state_b.name, Enum.random(fallback_lines)}
              ]

              EventLog.log(:conversation, tick, [id_a, id_b], %{
                type: :agent_chat,
                dialogue:
                  Enum.map(dialogue, fn {speaker, line} ->
                    %{speaker: speaker, line: line}
                  end)
              })

              update_relationship(id_a, id_b, :acquaintance, 0.1)
              update_relationship(id_b, id_a, :acquaintance, 0.1)
          end
        catch
          :exit, _ -> :ok
        end
      end)
    end)
  end

  defp update_relationship(agent_id, other_id, type, delta) do
    try do
      state = Agent.get_state(agent_id)
      {current_type, current_strength} = Map.get(state.relationships, other_id, {type, 0.0})
      new_strength = min(current_strength + delta, 1.0)
      new_type = if new_strength > 0.5, do: :friend, else: current_type
      new_rels = Map.put(state.relationships, other_id, {new_type, new_strength})

      GenServer.cast(
        {:via, Registry, {Modus.AgentRegistry, agent_id}},
        {:update_relationships, new_rels}
      )
    catch
      :exit, _ -> :ok
    end
  end

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
        openness: Float.round(state.personality.openness, 2),
        conscientiousness: Float.round(state.personality.conscientiousness, 2),
        extraversion: Float.round(state.personality.extraversion, 2),
        agreeableness: Float.round(state.personality.agreeableness, 2),
        neuroticism: Float.round(state.personality.neuroticism, 2)
      },
      needs: %{
        hunger: Float.round(state.needs.hunger, 1),
        social: Float.round(state.needs.social, 1),
        rest: Float.round(state.needs.rest, 1),
        shelter: Float.round(state.needs.shelter, 1)
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
              salience: Float.round(m.salience, 2),
              position: %{x: elem(m.position, 0), y: elem(m.position, 1)}
            }
          end)
        catch
          _, _ -> []
        end,
      last_reasoning: state.last_reasoning
    }
  end

  defp fallback_chat_reply(agent_state) do
    responses = [
      "Hello! I'm #{agent_state.name}, a #{agent_state.occupation}. Nice to meet you!",
      "*waves* I'm busy #{agent_state.current_action} right now, but it's good to see you.",
      "Ah, a visitor! I'm #{agent_state.name}. The village is quite peaceful today.",
      "*looks up from work* Oh! I didn't see you there. What brings you to these parts?",
      "Greetings, friend. #{agent_state.name} at your service."
    ]
    Enum.random(responses)
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
