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

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

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
            send(channel_pid, {:chat_reply, agent_id, "Şu an cevap veremiyorum..."})
        end
      catch
        kind, reason ->
          Logger.warning("Chat failed for #{agent_id}: #{inspect({kind, reason})}")
          send(channel_pid, {:chat_reply, agent_id, "Bir sorun oluştu..."})
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

    env = try do
      Modus.Simulation.Environment.get_state()
    catch
      :exit, _ -> %{time_of_day: :day, cycle_progress: 0.0}
    end

    delta = %{
      tick: tick_number,
      agent_count: length(Enum.filter(agents, & &1.alive)),
      agents: agents,
      time_of_day: to_string(env.time_of_day),
      cycle_progress: Float.round(ensure_float(env.cycle_progress), 4)
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

    env = try do
      Modus.Simulation.Environment.get_state()
    catch
      :exit, _ -> %{time_of_day: :day, cycle_progress: 0.0}
    end

    %{
      grid: grid,
      agents: agents,
      tick: tick,
      status: status,
      agent_count: length(agents),
      time_of_day: to_string(env.time_of_day),
      cycle_progress: Float.round(ensure_float(env.cycle_progress), 4)
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
                   |> Enum.map(fn f -> %{id: f.id, strength: Float.round(ensure_float(f.strength), 2)} end),
          conversing_with: Map.get(state, :conversing_with),
          group: case Modus.Mind.Cerebro.Group.get_agent_group(state.id) do
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
      last_reasoning: state.last_reasoning
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
