defmodule Modus.Simulation.Resource do
  @moduledoc """
  Resource — Ecosystem-balanced resource system for MODUS.
  v4.5.0 Renascentia: "Nature always restores its balance."

  Resources exist at grid positions and follow biome-driven respawn rates,
  depletion zones, soil fertility, seasonal modifiers, and carrying capacity.

  ## Resource Types
  - `:food`, `:wood`, `:stone`, `:water`, `:fish`, `:fresh_water`
  - `:crops`, `:herbs`, `:wild_berries`
  - `:gold`, `:gems` (rare — mountain only)
  - `:rare_herbs` (rare — swamp only)

  ## Ecosystem Balance
  - Respawn rates tied to biome
  - Over-harvested tiles become barren (depletion zones, 500 ticks)
  - Soil fertility for farming (depletes with use, rotation restores)
  - Carrying capacity per tile based on biome
  - Winter reduces regrowth by 50%
  - Rare resource discovery via agent exploration
  """

  defstruct [
    :id, :type, :position, :amount, :max_amount, :depleted_at,
    :fertility, :harvest_count, :barren_until, :density
  ]

  @type resource_type :: :food | :wood | :stone | :water | :fish | :fresh_water |
                         :crops | :herbs | :wild_berries | :gold | :gems | :rare_herbs
  @type t :: %__MODULE__{
          id: String.t(),
          type: resource_type(),
          position: {integer(), integer()},
          amount: float(),
          max_amount: float(),
          depleted_at: integer() | nil,
          fertility: float(),
          harvest_count: integer(),
          barren_until: integer() | nil,
          density: atom()
        }

  # Biome-specific respawn ticks (lower = faster regrowth)
  @biome_respawn %{
    forest:   %{wood: 80, food: 120, herbs: 150},
    plains:   %{food: 100, wild_berries: 140},
    swamp:    %{herbs: 60, food: 200, rare_herbs: 400},
    mountain: %{stone: 150, gold: 600, gems: 800},
    desert:   %{stone: 300},
    tundra:   %{stone: 250, food: 350},
    ocean:    %{fish: 70, fresh_water: 50}
  }

  # Carrying capacity per biome (max total resource amount per tile)
  @biome_capacity %{
    forest: 30.0,
    plains: 20.0,
    swamp: 15.0,
    mountain: 25.0,
    desert: 5.0,
    tundra: 8.0,
    ocean: 20.0
  }

  # Depletion threshold — harvests before tile goes barren
  @barren_threshold 10
  @barren_duration 500

  # Fertility
  @max_fertility 1.0
  @fertility_drain 0.08
  @fertility_restore_rate 0.01

  @default_respawn 200

  # ── Terrain → resource types ────────────────────────────────

  @doc "Terrain → harvestable resource types."
  def terrain_resources(:forest),   do: [:wood, :food, :herbs]
  def terrain_resources(:water),    do: [:fish, :fresh_water]
  def terrain_resources(:farm),     do: [:crops]
  def terrain_resources(:mountain), do: [:stone]
  def terrain_resources(:flowers),  do: [:herbs]
  def terrain_resources(:grass),    do: [:wild_berries, :food]
  def terrain_resources(:desert),   do: []
  def terrain_resources(:sand),     do: []
  def terrain_resources(_),         do: []

  @doc "Resource node types and what they provide."
  def node_resources(:food_source),  do: %{food: 20.0}
  def node_resources(:water_well),   do: %{fresh_water: 15.0}
  def node_resources(:wood_pile),    do: %{wood: 25.0}
  def node_resources(:stone_quarry), do: %{stone: 20.0}
  def node_resources(_),             do: %{}

  # ── Creation ────────────────────────────────────────────────

  @doc "Create a new resource with ecosystem properties."
  @spec new(resource_type(), {integer(), integer()}, number()) :: t()
  def new(type, position, amount \\ 10.0) do
    amt = ensure_float(amount)
    %__MODULE__{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower),
      type: type,
      position: position,
      amount: amt,
      max_amount: amt,
      depleted_at: nil,
      fertility: @max_fertility,
      harvest_count: 0,
      barren_until: nil,
      density: density_level(amt, amt)
    }
  end

  # ── Gathering ───────────────────────────────────────────────

  @doc "Gather from a resource. Returns {gathered_amount, updated_resource}."
  @spec gather(t(), float()) :: {float(), t()}
  def gather(%__MODULE__{barren_until: barren} = resource, _requested)
      when is_integer(barren) do
    # Barren tile — nothing to gather
    {0.0, resource}
  end

  def gather(%__MODULE__{amount: amount} = resource, requested) do
    req = ensure_float(requested)
    taken = min(req, amount)
    new_amount = ensure_float(amount - taken)
    new_count = resource.harvest_count + 1

    # Check barren trigger
    barren_until =
      if new_count >= @barren_threshold and new_amount <= 0.0 do
        current_tick() + @barren_duration
      else
        resource.barren_until
      end

    # Drain fertility on crops
    new_fertility =
      if resource.type == :crops do
        max(0.0, ensure_float(resource.fertility) - @fertility_drain)
      else
        resource.fertility
      end

    depleted_at =
      if new_amount <= 0.0 and is_nil(resource.depleted_at) do
        current_tick()
      else
        resource.depleted_at
      end

    updated = %{resource |
      amount: new_amount,
      depleted_at: depleted_at,
      harvest_count: new_count,
      barren_until: barren_until,
      fertility: new_fertility,
      density: density_level(new_amount, resource.max_amount)
    }

    {taken, updated}
  end

  # ── State queries ───────────────────────────────────────────

  @doc "Check if resource is depleted."
  @spec depleted?(t()) :: boolean()
  def depleted?(%__MODULE__{amount: amount}), do: ensure_float(amount) <= 0.0

  @doc "Check if tile is barren (over-harvested)."
  @spec barren?(t()) :: boolean()
  def barren?(%__MODULE__{barren_until: nil}), do: false
  def barren?(%__MODULE__{barren_until: until}), do: current_tick() < until

  # ── Respawn ─────────────────────────────────────────────────

  @doc "Check if resource should respawn based on biome rate and season."
  @spec should_respawn?(t(), atom()) :: boolean()
  def should_respawn?(%__MODULE__{depleted_at: nil}, _biome), do: false
  def should_respawn?(%__MODULE__{barren_until: b}, _biome) when is_integer(b) do
    current_tick() >= b
  end
  def should_respawn?(%__MODULE__{depleted_at: tick, type: type}, biome) do
    rate = respawn_rate(biome, type)
    tick + rate <= current_tick()
  end

  @doc "Respawn a depleted resource. Amount scaled by fertility and season."
  @spec respawn(t(), atom()) :: t()
  def respawn(%__MODULE__{} = resource, season \\ :spring) do
    season_mod = season_modifier(season)
    fert = ensure_float(resource.fertility)
    restored = ensure_float(resource.max_amount) * fert * season_mod

    %{resource |
      amount: min(restored, resource.max_amount),
      depleted_at: nil,
      barren_until: nil,
      harvest_count: 0,
      density: density_level(restored, resource.max_amount)
    }
  end

  @doc "Tick soil fertility restoration (call each tick for fallow land)."
  @spec restore_fertility(t()) :: t()
  def restore_fertility(%__MODULE__{fertility: f} = resource) do
    new_f = min(@max_fertility, ensure_float(f) + @fertility_restore_rate)
    %{resource | fertility: new_f}
  end

  # ── Biome respawn rates ─────────────────────────────────────

  @doc "Get respawn ticks for a resource type in a biome."
  @spec respawn_rate(atom(), resource_type()) :: integer()
  def respawn_rate(biome, type) do
    @biome_respawn
    |> Map.get(biome, %{})
    |> Map.get(type, @default_respawn)
  end

  @doc "Carrying capacity for a biome."
  @spec carrying_capacity(atom()) :: float()
  def carrying_capacity(biome) do
    Map.get(@biome_capacity, biome, 15.0)
  end

  # ── Rare resources ──────────────────────────────────────────

  @doc "Attempt rare resource discovery at a position. Returns {:ok, resource} | :nothing."
  @spec discover_rare({integer(), integer()}, atom()) :: {:ok, t()} | :nothing
  def discover_rare(position, biome) do
    roll = :rand.uniform(100)
    case biome do
      :mountain when roll <= 3 ->
        type = if :rand.uniform(2) == 1, do: :gold, else: :gems
        {:ok, new(type, position, 5.0)}
      :swamp when roll <= 5 ->
        {:ok, new(:rare_herbs, position, 3.0)}
      _ ->
        :nothing
    end
  end

  # ── Season modifier ─────────────────────────────────────────

  @doc "Season growth modifier for respawn."
  @spec season_modifier(atom()) :: float()
  def season_modifier(:spring), do: 1.5
  def season_modifier(:summer), do: 1.0
  def season_modifier(:autumn), do: 0.8
  def season_modifier(:winter), do: 0.5
  def season_modifier(_), do: 1.0

  # ── Density visual ──────────────────────────────────────────

  @doc "Density level for visual indicators."
  @spec density_level(number(), number()) :: atom()
  def density_level(amount, max_amount) do
    ratio = ensure_float(amount) / max(ensure_float(max_amount), 1.0)
    cond do
      ratio >= 0.75 -> :dense
      ratio >= 0.40 -> :moderate
      ratio >= 0.10 -> :sparse
      true -> :depleted
    end
  end

  @doc "Density emoji for display."
  @spec density_emoji(atom()) :: String.t()
  def density_emoji(:dense),    do: "🟢"
  def density_emoji(:moderate), do: "🟡"
  def density_emoji(:sparse),   do: "🟠"
  def density_emoji(:depleted), do: "🔴"
  def density_emoji(_),         do: "⚪"

  # ── Legacy compat ───────────────────────────────────────────

  @doc "Ticks needed for respawn (legacy default)."
  def respawn_ticks, do: @default_respawn

  # ── Helpers ─────────────────────────────────────────────────

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  defp current_tick do
    if Process.whereis(Modus.Simulation.Ticker) do
      try do Modus.Simulation.Ticker.current_tick() catch _, _ -> 0 end
    else
      0
    end
  end
end
