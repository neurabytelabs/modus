defmodule Modus.Simulation.Environment do
  @moduledoc """
  Environment — Day/night cycle and world environment state.

  500 ticks per full cycle: ticks 0-249 = day, ticks 250-499 = night.
  Broadcasts changes on "modus:environment" topic.
  """
  use GenServer

  @cycle_length 500
  @day_length 250

  defstruct cycle_tick: 0, time_of_day: :day

  # ── Public API ──────────────────────────────────────────────

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @spec time_of_day() :: :day | :night
  def time_of_day do
    GenServer.call(__MODULE__, :time_of_day)
  end

  @spec is_night?() :: boolean()
  def is_night? do
    GenServer.call(__MODULE__, :is_night?)
  end

  @spec cycle_progress() :: float()
  def cycle_progress do
    GenServer.call(__MODULE__, :cycle_progress)
  end

  # ── GenServer ───────────────────────────────────────────────

  @impl true
  def init(state) do
    Phoenix.PubSub.subscribe(Modus.PubSub, "simulation:ticks")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, %{
      time_of_day: state.time_of_day,
      cycle_tick: state.cycle_tick,
      cycle_progress: state.cycle_tick / @cycle_length
    }, state}
  end

  def handle_call(:time_of_day, _from, state) do
    {:reply, state.time_of_day, state}
  end

  def handle_call(:is_night?, _from, state) do
    {:reply, state.time_of_day == :night, state}
  end

  def handle_call(:cycle_progress, _from, state) do
    {:reply, Float.round(state.cycle_tick / @cycle_length, 4), state}
  end

  @impl true
  def handle_info({:tick, _tick_number}, state) do
    new_tick = rem(state.cycle_tick + 1, @cycle_length)
    new_tod = if new_tick < @day_length, do: :day, else: :night
    old_tod = state.time_of_day

    new_state = %{state | cycle_tick: new_tick, time_of_day: new_tod}

    # Broadcast on every tick (for smooth transitions)
    Phoenix.PubSub.broadcast(Modus.PubSub, "modus:environment", {:environment_update, %{
      time_of_day: new_tod,
      cycle_tick: new_tick,
      cycle_progress: new_tick / @cycle_length
    }})

    # Log transition
    if old_tod != new_tod do
      Phoenix.PubSub.broadcast(Modus.PubSub, "modus:environment", {:time_change, new_tod})
    end

    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
