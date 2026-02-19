defmodule Modus.Simulation.Ticker do
  @moduledoc """
  Ticker — The heartbeat of the MODUS universe.

  A GenServer that drives the simulation forward at a configurable
  interval (default 100ms). Each tick broadcasts to PubSub so that
  all subscribers (World, Agents, LiveView) can react.

  ## States

  - `:running` — actively ticking
  - `:paused`  — idle, waiting for resume

  ## PubSub Topic

  Broadcasts `{:tick, tick_number}` on `"modus:tick"`.
  """
  use GenServer
  require Logger

  @default_interval_ms 100
  @pubsub Modus.PubSub
  @topic "modus:tick"

  defstruct tick: 0,
            state: :paused,
            interval_ms: @default_interval_ms,
            timer_ref: nil

  @type t :: %__MODULE__{
          tick: non_neg_integer(),
          state: :running | :paused,
          interval_ms: pos_integer(),
          timer_ref: reference() | nil
        }

  # ── Public API ──────────────────────────────────────────────

  @doc "Start the Ticker process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start ticking."
  @spec run(pid() | atom()) :: :ok
  def run(server \\ __MODULE__), do: GenServer.call(server, :run)

  @doc "Pause ticking."
  @spec pause(pid() | atom()) :: :ok
  def pause(server \\ __MODULE__), do: GenServer.call(server, :pause)

  @doc "Get current ticker state."
  @spec status(pid() | atom()) :: %{tick: non_neg_integer(), state: :running | :paused}
  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  @doc "Get the current tick number."
  @spec current_tick(pid() | atom()) :: non_neg_integer()
  def current_tick(server \\ __MODULE__), do: GenServer.call(server, :current_tick)

  @doc "Set tick speed multiplier (1, 5, 10)."
  @spec set_speed(pid() | atom(), pos_integer()) :: :ok
  def set_speed(server \\ __MODULE__, multiplier) when multiplier in [1, 5, 10] do
    GenServer.call(server, {:set_speed, multiplier})
  end

  @doc "Subscribe to tick events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc "The PubSub topic for tick events."
  @spec topic() :: String.t()
  def topic, do: @topic

  # ── GenServer ───────────────────────────────────────────────

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    {:ok, %__MODULE__{interval_ms: interval}}
  end

  @impl true
  def handle_call(:run, _from, %{state: :running} = s), do: {:reply, :ok, s}

  def handle_call(:run, _from, s) do
    ref = schedule_tick(s.interval_ms)
    {:reply, :ok, %{s | state: :running, timer_ref: ref}}
  end

  @impl true
  def handle_call(:pause, _from, %{state: :paused} = s), do: {:reply, :ok, s}

  def handle_call(:pause, _from, s) do
    if s.timer_ref, do: Process.cancel_timer(s.timer_ref)
    {:reply, :ok, %{s | state: :paused, timer_ref: nil}}
  end

  @impl true
  def handle_call(:status, _from, s) do
    {:reply, %{tick: s.tick, state: s.state}, s}
  end

  @impl true
  def handle_call(:current_tick, _from, s) do
    {:reply, s.tick, s}
  end

  @impl true
  def handle_call({:set_speed, multiplier}, _from, s) do
    new_interval = div(@default_interval_ms, multiplier)
    new_state = %{s | interval_ms: new_interval}

    # If running, reschedule with new interval
    new_state =
      if s.state == :running do
        if s.timer_ref, do: Process.cancel_timer(s.timer_ref)
        ref = schedule_tick(new_interval)
        %{new_state | timer_ref: ref}
      else
        new_state
      end

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:tick, %{state: :paused} = s), do: {:noreply, s}

  def handle_info(:tick, s) do
    tick_start = System.monotonic_time()
    new_tick = s.tick + 1

    # Broadcast tick event to channels/scheduler
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:tick, new_tick})
    # Broadcast to agents (self-tick)
    Phoenix.PubSub.broadcast(@pubsub, "simulation:ticks", {:tick, new_tick})

    # Rebuild spatial index every 10 ticks for O(1) neighbor lookups
    if rem(new_tick, 10) == 0 do
      try do
        Modus.Performance.SpatialIndex.rebuild()
      catch
        _, _ -> :ok
      end
    end

    # Decay unowned buildings + detect neighborhoods every 100 ticks
    if rem(new_tick, 100) == 0 do
      try do
        Modus.Simulation.Building.decay_unowned()
        old_hoods = Modus.Simulation.Building.neighborhoods() |> Enum.map(& &1.id) |> MapSet.new()
        new_hoods = Modus.Simulation.Building.detect_neighborhoods()
        # Log story events for newly formed neighborhoods
        for hood <- new_hoods, not MapSet.member?(old_hoods, hood.id) do
          Modus.Simulation.EventLog.log(:neighborhood_formed, new_tick, hood.resident_ids, %{
            name: hood.name,
            size: hood.size,
            center: hood.center
          })
        end
      catch
        _, _ -> :ok
      end
    end

    # Tick world events engine
    try do
      Modus.Simulation.WorldEvents.tick(new_tick)
    catch
      _, _ -> :ok
    end

    # Record population every 10 ticks for StoryEngine graphs
    if rem(new_tick, 10) == 0 do
      agent_count =
        try do
          Registry.count(Modus.AgentRegistry)
        catch
          _, _ -> 0
        end

      Modus.Simulation.StoryEngine.record_population(new_tick, agent_count)

      # Update Observatory ETS cache (v7.2 — O(1) reads)
      try do
        Modus.Simulation.Observatory.update_cache()
      catch
        _, _ -> :ok
      end

      # Feed WorldHistory metrics for era detection
      try do
        Modus.Simulation.WorldHistory.record_metrics(%{
          tick: new_tick,
          population: agent_count,
          births: 0,
          deaths: 0,
          trades: 0,
          conflicts: 0
        })
      catch
        _, _ -> :ok
      end
    end

    # Auto-save check (v3.7.0 Persistentia)
    if rem(new_tick, 100) == 0 do
      try do
        Modus.Persistence.SaveManager.autosave(new_tick)
      catch
        _, _ -> :ok
      end
    end

    # Emit telemetry (v7.2 — LiveDashboard compatible)
    tick_duration = System.monotonic_time() - tick_start

    agent_count =
      try do
        Registry.count(Modus.AgentRegistry)
      catch
        _, _ -> 0
      end

    :telemetry.execute(
      [:modus, :ticker, :tick],
      %{duration: tick_duration, agent_count: agent_count},
      %{tick_number: new_tick}
    )

    # v7.3: Tick lag detection — warn if tick processing exceeds interval
    tick_ms = System.convert_time_unit(tick_duration, :native, :millisecond)

    if tick_ms > s.interval_ms do
      Logger.warning(
        "Tick lag detected: tick ##{new_tick} took #{tick_ms}ms (interval: #{s.interval_ms}ms, agents: #{agent_count})"
      )
    end

    # Schedule next tick
    ref = schedule_tick(s.interval_ms)
    {:noreply, %{s | tick: new_tick, timer_ref: ref}}
  end

  # Catch-all for unexpected messages
  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internal ────────────────────────────────────────────────

  # v7.5: Adaptive tick interval — slow down when many agents to maintain budget
  @adaptive_thresholds [
    {200, 1.0},   # <= 200 agents: no slowdown
    {500, 1.5},   # 201-500 agents: 1.5x interval
    {1000, 2.5},  # 501-1000 agents: 2.5x interval
    {5000, 4.0}   # 1001+: 4x interval
  ]

  defp schedule_tick(ms) do
    # Apply RulesEngine time_speed multiplier (higher = faster = shorter interval)
    time_speed =
      try do
        Modus.Simulation.RulesEngine.time_speed()
      catch
        _, _ -> 1.0
      end

    # Adaptive interval based on agent count
    agent_count =
      try do
        Registry.count(Modus.AgentRegistry)
      catch
        _, _ -> 0
      end

    adaptive_multiplier = adaptive_factor(agent_count)

    adjusted_ms = max(10, round(ms * adaptive_multiplier / time_speed))
    Process.send_after(self(), :tick, adjusted_ms)
  end

  defp adaptive_factor(agent_count) do
    @adaptive_thresholds
    |> Enum.find(fn {threshold, _factor} -> agent_count <= threshold end)
    |> case do
      {_threshold, factor} -> factor
      nil -> 4.0  # Beyond all thresholds
    end
  end

end
