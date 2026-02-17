defmodule Modus.Simulation.Seasons do
  @moduledoc """
  Seasons — Cyclical seasons that shape the world.

  Spring→Summer→Autumn→Winter, ~1000 ticks each (4000 tick full year).
  Each season affects growth rates, agent needs, terrain colors, and mood.

  ## Spinoza: *Sub specie aeternitatis* — Under the aspect of eternity,
  all things cycle and return.
  """
  use GenServer

  alias Modus.Simulation.EventLog

  @pubsub Modus.PubSub
  @topic "modus:seasons"

  @season_length 1000

  @seasons [:spring, :summer, :autumn, :winter]

  @season_config %{
    spring: %{
      emoji: "🌸",
      name: "Spring",
      growth_modifier: 1.5,
      tint: 0x88DD88,
      tint_alpha: 0.08,
      terrain_shift: %{grass: 0x5CE65C, forest: 0x1E8C3E, farm: 0xA0B856},
      mood_effect: :joy,
      mood_delta: 0.05,
      hunger_rate: 1.0,
      rest_rate: 1.0
    },
    summer: %{
      emoji: "☀️",
      name: "Summer",
      growth_modifier: 1.0,
      tint: 0xFFD700,
      tint_alpha: 0.06,
      terrain_shift: %{grass: 0x6BD96B, forest: 0x1A7A34, farm: 0xB0AA46, desert: 0xE8C060},
      mood_effect: :desire,
      mood_delta: 0.0,
      hunger_rate: 1.3,
      rest_rate: 1.3
    },
    autumn: %{
      emoji: "🍂",
      name: "Autumn",
      growth_modifier: 0.8,
      tint: 0xDD8844,
      tint_alpha: 0.08,
      terrain_shift: %{grass: 0xC4A04C, forest: 0x8B6914, farm: 0xCC9933, flowers: 0xCC7744},
      mood_effect: :sadness,
      mood_delta: -0.03,
      hunger_rate: 0.9,
      rest_rate: 1.0
    },
    winter: %{
      emoji: "❄️",
      name: "Winter",
      growth_modifier: 0.3,
      tint: 0xCCDDFF,
      tint_alpha: 0.12,
      terrain_shift: %{grass: 0xC8D8D0, forest: 0x5A7A6A, farm: 0xAABBA0, mountain: 0xBBBBCC, flowers: 0xDDDDEE},
      mood_effect: :sadness,
      mood_delta: -0.08,
      hunger_rate: 1.5,
      rest_rate: 0.8
    }
  }

  defstruct season: :spring, season_tick: 0, year: 1, total_ticks: 0

  # ── Public API ──────────────────────────────────────────────

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @spec current_season() :: atom()
  def current_season do
    GenServer.call(__MODULE__, :current_season)
  end

  @spec season_config() :: map()
  def season_config do
    GenServer.call(__MODULE__, :season_config)
  end

  @spec season_progress() :: float()
  def season_progress do
    GenServer.call(__MODULE__, :season_progress)
  end

  @doc "Get serialized state for client."
  @spec serialize() :: map()
  def serialize do
    GenServer.call(__MODULE__, :serialize)
  end

  # ── GenServer ───────────────────────────────────────────────

  @impl true
  def init(state) do
    Phoenix.PubSub.subscribe(Modus.PubSub, "simulation:ticks")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    config = Map.fetch!(@season_config, state.season)
    {:reply, Map.merge(state_to_map(state), %{config: config}), state}
  end

  def handle_call(:current_season, _from, state) do
    {:reply, state.season, state}
  end

  def handle_call(:season_config, _from, state) do
    {:reply, Map.fetch!(@season_config, state.season), state}
  end

  def handle_call(:season_progress, _from, state) do
    {:reply, state.season_tick / @season_length, state}
  end

  def handle_call(:serialize, _from, state) do
    config = Map.fetch!(@season_config, state.season)
    terrain_shift = config.terrain_shift
      |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Enum.into(%{})

    {:reply, %{
      season: Atom.to_string(state.season),
      season_name: config.name,
      emoji: config.emoji,
      year: state.year,
      progress: Float.round(state.season_tick / @season_length, 4),
      tint: config.tint,
      tint_alpha: config.tint_alpha,
      terrain_shift: terrain_shift,
      growth_modifier: config.growth_modifier
    }, state}
  end

  @impl true
  def handle_info({:tick, _tick_number}, state) do
    new_season_tick = state.season_tick + 1
    new_total = state.total_ticks + 1

    if new_season_tick >= @season_length do
      # Season change
      current_idx = Enum.find_index(@seasons, &(&1 == state.season))
      next_idx = rem(current_idx + 1, 4)
      next_season = Enum.at(@seasons, next_idx)
      new_year = if next_season == :spring, do: state.year + 1, else: state.year

      new_state = %{state |
        season: next_season,
        season_tick: 0,
        year: new_year,
        total_ticks: new_total
      }

      config = Map.fetch!(@season_config, next_season)

      # Broadcast season change
      Phoenix.PubSub.broadcast(@pubsub, @topic, {:season_change, next_season, config})

      # Log story event
      EventLog.log(:season_change, new_total, [], %{
        season: next_season,
        year: new_year,
        name: config.name,
        emoji: config.emoji
      })

      {:noreply, new_state}
    else
      {:noreply, %{state | season_tick: new_season_tick, total_ticks: new_total}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Helpers ─────────────────────────────────────────────────

  defp state_to_map(state) do
    %{
      season: state.season,
      season_tick: state.season_tick,
      year: state.year,
      total_ticks: state.total_ticks,
      progress: state.season_tick / @season_length
    }
  end
end
