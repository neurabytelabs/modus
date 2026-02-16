defmodule ModusWeb.WorldChannel do
  @moduledoc """
  WorldChannel — Real-time world state streaming.

  On join: sends full grid + agent state.
  Each tick: broadcasts delta (agent positions + tick number).
  """
  use Phoenix.Channel

  alias Modus.Simulation.{World, Ticker, Agent, AgentSupervisor}

  # tick topic used for PubSub subscription

  @impl true
  def join("world:lobby", _payload, socket) do
    # Subscribe to tick events
    Ticker.subscribe()

    # Build full state
    state = build_full_state()
    {:ok, state, socket}
  end

  @impl true
  def handle_in("start", _payload, socket) do
    # Ensure world + agents exist, then start ticker
    ensure_world_running()
    Ticker.run()
    broadcast!(socket, "status_change", %{status: "running"})
    {:noreply, socket}
  end

  @impl true
  def handle_in("pause", _payload, socket) do
    Ticker.pause()
    broadcast!(socket, "status_change", %{status: "paused"})
    {:noreply, socket}
  end

  @impl true
  def handle_in("reset", _payload, socket) do
    Ticker.pause()
    # Kill all agents
    AgentSupervisor.terminate_all()
    # Restart world
    if Process.whereis(World), do: GenServer.stop(World)
    world = World.new("Genesis")
    {:ok, _} = World.start_link(world)
    World.spawn_initial_agents(10)
    Ticker.run()
    broadcast!(socket, "status_change", %{status: "running"})

    # Send fresh full state
    state = build_full_state()
    broadcast!(socket, "full_state", state)
    {:noreply, socket}
  end

  # Handle tick broadcasts from PubSub
  @impl true
  def handle_info({:tick, tick_number}, socket) do
    agents = get_agent_list()

    # Tick each agent
    for agent <- agents do
      Agent.tick(agent.id, tick_number, %{})
    end

    # Get updated positions
    updated_agents = get_agent_list()

    delta = %{
      tick: tick_number,
      agent_count: length(updated_agents),
      agents: updated_agents,
    }

    push(socket, "delta", delta)
    {:noreply, socket}
  end

  # ── Helpers ───────────────────────────────────────────────

  defp build_full_state do
    world_state = if Process.whereis(World) do
      World.get_state()
    else
      nil
    end

    grid = if world_state do
      build_grid(world_state)
    else
      []
    end

    agents = get_agent_list()

    tick = if Process.whereis(Ticker) do
      Ticker.current_tick()
    else
      0
    end

    status = if Process.whereis(Ticker) do
      Ticker.status().state |> to_string()
    else
      "paused"
    end

    %{
      grid: grid,
      agents: agents,
      tick: tick,
      status: status,
      agent_count: length(agents),
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
        state = GenServer.call(pid, :get_state, 500)
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
        }
      catch
        :exit, _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp ensure_world_running do
    unless Process.whereis(World) do
      world = World.new("Genesis")
      {:ok, _} = World.start_link(world)
    end

    # Spawn agents if none exist
    agents = get_agent_list()
    if Enum.empty?(agents) do
      World.spawn_initial_agents(10)
    end
  end
end
