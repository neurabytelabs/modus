defmodule Modus.Simulation.Environment do
  @moduledoc """
  Environment — Day/night cycle and world environment state.

  500 ticks per full cycle: ticks 0-249 = day, ticks 250-499 = night.
  Now includes season-aware ambient colors for the day/night transitions.

  Day phases (by cycle_progress):
    0.00-0.15 dawn (amber)
    0.15-0.45 day (bright)
    0.45-0.55 dusk (purple)
    0.55-0.95 night (dark blue)
    0.95-1.00 pre-dawn (deep blue → amber)

  Broadcasts changes on "modus:environment" topic.
  """
  use GenServer

  @cycle_length 500
  @day_length 250

  # Ambient overlay colors for day phases
  @phase_colors %{
    dawn: %{color: 0xDD8833, alpha: 0.10},
    day: %{color: 0xFFFFCC, alpha: 0.0},
    dusk: %{color: 0x8844AA, alpha: 0.12},
    night: %{color: 0x0A1030, alpha: 0.40},
    predawn: %{color: 0x1A1840, alpha: 0.30}
  }

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
    progress = state.cycle_tick / @cycle_length
    phase = day_phase(progress)
    phase_config = Map.fetch!(@phase_colors, phase)

    {:reply,
     %{
       time_of_day: state.time_of_day,
       cycle_tick: state.cycle_tick,
       cycle_progress: progress,
       day_phase: phase,
       ambient_color: phase_config.color,
       ambient_alpha: phase_config.alpha
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

    progress = new_tick / @cycle_length
    phase = day_phase(progress)
    phase_config = Map.fetch!(@phase_colors, phase)

    # Broadcast on every tick (for smooth transitions)
    Phoenix.PubSub.broadcast(
      Modus.PubSub,
      "modus:environment",
      {:environment_update,
       %{
         time_of_day: new_tod,
         cycle_tick: new_tick,
         cycle_progress: progress,
         day_phase: phase,
         ambient_color: phase_config.color,
         ambient_alpha: phase_config.alpha
       }}
    )

    # Log transition
    if old_tod != new_tod do
      Phoenix.PubSub.broadcast(Modus.PubSub, "modus:environment", {:time_change, new_tod})
    end

    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Helpers ─────────────────────────────────────────────────

  defp day_phase(progress) when progress < 0.15, do: :dawn
  defp day_phase(progress) when progress < 0.45, do: :day
  defp day_phase(progress) when progress < 0.55, do: :dusk
  defp day_phase(progress) when progress < 0.95, do: :night
  defp day_phase(_), do: :predawn
end
