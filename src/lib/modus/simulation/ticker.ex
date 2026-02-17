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
    new_tick = s.tick + 1

    # Broadcast tick event to channels/scheduler
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:tick, new_tick})
    # Broadcast to agents (self-tick)
    Phoenix.PubSub.broadcast(@pubsub, "simulation:ticks", {:tick, new_tick})

    # Decay unowned buildings + detect neighborhoods every 100 ticks
    if rem(new_tick, 100) == 0 do
      try do
        Modus.Simulation.Building.decay_unowned()
        old_hoods = Modus.Simulation.Building.neighborhoods() |> Enum.map(& &1.id) |> MapSet.new()
        new_hoods = Modus.Simulation.Building.detect_neighborhoods()
        # Log story events for newly formed neighborhoods
        for hood <- new_hoods, not MapSet.member?(old_hoods, hood.id) do
          Modus.Simulation.EventLog.log(:neighborhood_formed, new_tick, hood.resident_ids, %{
            name: hood.name, size: hood.size, center: hood.center
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
      agent_count = try do
        Registry.count(Modus.AgentRegistry)
      catch
        _, _ -> 0
      end
      Modus.Simulation.StoryEngine.record_population(new_tick, agent_count)
    end

    # Schedule next tick
    ref = schedule_tick(s.interval_ms)
    {:noreply, %{s | tick: new_tick, timer_ref: ref}}
  end

  # ── Internal ────────────────────────────────────────────────

  defp schedule_tick(ms) do
    # Apply RulesEngine time_speed multiplier (higher = faster = shorter interval)
    time_speed = try do
      Modus.Simulation.RulesEngine.time_speed()
    catch
      _, _ -> 1.0
    end
    adjusted_ms = max(10, round(ms / time_speed))
    Process.send_after(self(), :tick, adjusted_ms)
  end
end
