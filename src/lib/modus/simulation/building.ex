defmodule Modus.Simulation.Building do
  @moduledoc """
  Building — Structures built by agents using gathered resources.

  Buildings are stored in ETS (:buildings) and provide area bonuses.
  Each building has a type, owner, health, and level.

  ## Building Types & Costs
  - Hut: 5 wood → rest+10 bonus
  - House: 10 wood + 5 stone → rest+15, shelter+10
  - Farm: 3 wood → auto-food generation
  - Market: 8 wood + 8 stone → trade bonus
  - Well: 10 stone → water access
  - Watchtower: 15 stone + 5 wood → expanded vision
  """

  require Logger

  @type building_type :: :hut | :house | :farm | :market | :well | :watchtower

  @type t :: %{
    id: String.t(),
    type: building_type(),
    position: {integer(), integer()},
    owner_id: String.t() | nil,
    health: float(),
    level: integer(),
    built_tick: integer()
  }

  # ── Cost Definitions ──────────────────────────────────────

  @costs %{
    hut:        %{wood: 5},
    house:      %{wood: 10, stone: 5},
    farm:       %{wood: 3},
    market:     %{wood: 8, stone: 8},
    well:       %{stone: 10},
    watchtower: %{stone: 15, wood: 5}
  }

  @bonuses %{
    hut:        %{rest: 10.0},
    house:      %{rest: 15.0, shelter: 10.0},
    farm:       %{hunger: -5.0},
    market:     %{social: 5.0},
    well:       %{rest: 5.0},
    watchtower: %{shelter: 5.0}
  }

  @emojis %{
    hut:        "🛋",
    house:      "🏠",
    farm:       "🌾",
    market:     "🏪",
    well:       "🪣",
    watchtower: "🗼"
  }

  @colors %{
    hut:        0x8B4513,
    house:      0xD2B48C,
    farm:       0x228B22,
    market:     0xDAA520,
    well:       0x4682B4,
    watchtower: 0x696969
  }

  @sizes %{
    hut:        {12, 12},
    house:      {16, 16},
    farm:       {20, 14},
    market:     {18, 18},
    well:       {10, 10},
    watchtower: {10, 14}
  }

  # ── ETS Setup ─────────────────────────────────────────────

  def init_table do
    if :ets.whereis(:buildings) == :undefined do
      :ets.new(:buildings, [:named_table, :set, :public, read_concurrency: true])
    end
    :ok
  end

  # ── Public API ────────────────────────────────────────────

  @doc "Get building costs for a type."
  @spec costs(building_type()) :: map()
  def costs(type), do: Map.get(@costs, type, %{})

  @doc "Get all building types."
  def types, do: Map.keys(@costs)

  @doc "Get emoji for a building type."
  def emoji(type), do: Map.get(@emojis, type, "🏗️")

  @doc "Get color for a building type."
  def color(type), do: Map.get(@colors, type, 0x888888)

  @doc "Get size {w, h} for a building type."
  def size(type), do: Map.get(@sizes, type, {14, 14})

  @doc "Get area bonuses for a building type."
  def bonuses(type), do: Map.get(@bonuses, type, %{})

  @doc "Check if an agent's inventory has enough resources to build."
  @spec can_build?(map(), building_type()) :: boolean()
  def can_build?(inventory, type) do
    cost = costs(type)
    Enum.all?(cost, fn {resource, amount} ->
      Map.get(inventory, resource, 0) >= amount
    end)
  end

  @doc "Deduct build costs from inventory. Returns updated inventory."
  @spec deduct_costs(map(), building_type()) :: map()
  def deduct_costs(inventory, type) do
    cost = costs(type)
    Enum.reduce(cost, inventory, fn {resource, amount}, inv ->
      current = Map.get(inv, resource, 0)
      Map.put(inv, resource, max(0, current - amount))
    end)
  end

  @doc "Place a building at a position."
  @spec place(building_type(), {integer(), integer()}, String.t(), integer()) :: t()
  def place(type, position, owner_id, tick) do
    init_table()
    building = %{
      id: generate_id(),
      type: type,
      position: position,
      owner_id: owner_id,
      health: 100.0,
      level: 1,
      built_tick: tick
    }
    :ets.insert(:buildings, {building.id, building})
    Logger.info("MODUS Building placed: #{type} at #{inspect(position)} by #{owner_id}")
    building
  end

  @doc "Get all buildings."
  @spec all() :: [t()]
  def all do
    init_table()
    :ets.tab2list(:buildings)
    |> Enum.map(fn {_id, b} -> b end)
  end

  @doc "Get building at a position."
  @spec at({integer(), integer()}) :: t() | nil
  def at(position) do
    all()
    |> Enum.find(fn b -> b.position == position end)
  end

  @doc "Get buildings owned by an agent."
  @spec owned_by(String.t()) :: [t()]
  def owned_by(owner_id) do
    all()
    |> Enum.filter(fn b -> b.owner_id == owner_id end)
  end

  @doc "Check if agent has a home (hut or house)."
  @spec has_home?(String.t()) :: boolean()
  def has_home?(agent_id) do
    owned_by(agent_id)
    |> Enum.any?(fn b -> b.type in [:hut, :house] end)
  end

  @doc "Get agent's home building."
  @spec get_home(String.t()) :: t() | nil
  def get_home(agent_id) do
    owned_by(agent_id)
    |> Enum.find(fn b -> b.type in [:hut, :house] end)
  end

  @doc "Apply building bonuses to an agent's needs if near a building."
  @spec apply_area_bonuses(map(), {integer(), integer()}) :: map()
  def apply_area_bonuses(needs, position) do
    {ax, ay} = position
    nearby_buildings = all()
    |> Enum.filter(fn b ->
      {bx, by} = b.position
      abs(bx - ax) <= 2 and abs(by - ay) <= 2
    end)

    Enum.reduce(nearby_buildings, needs, fn building, acc ->
      bonus = bonuses(building.type)
      Enum.reduce(bonus, acc, fn {need, amount}, n ->
        current = Map.get(n, need, 0.0)
        new_val = max(0.0, min(100.0, current + amount * 0.1))  # 10% per tick
        Map.put(n, need, new_val)
      end)
    end)
  end

  @doc "Decay unowned buildings. Call every 100 ticks."
  @spec decay_unowned() :: :ok
  def decay_unowned do
    init_table()
    for {id, building} <- :ets.tab2list(:buildings) do
      if building.owner_id == nil do
        new_health = building.health - 0.5
        if new_health <= 0 do
          :ets.delete(:buildings, id)
          Logger.info("MODUS Building destroyed (decay): #{building.type} at #{inspect(building.position)}")
        else
          :ets.insert(:buildings, {id, %{building | health: new_health}})
        end
      end
    end
    :ok
  end

  @doc "Remove a building by id."
  @spec remove(String.t()) :: :ok
  def remove(id) do
    init_table()
    :ets.delete(:buildings, id)
    :ok
  end

  @doc "Serialize all buildings for client broadcast."
  @spec serialize_all() :: [map()]
  def serialize_all do
    all()
    |> Enum.map(fn b ->
      {w, h} = size(b.type)
      %{
        id: b.id,
        type: to_string(b.type),
        x: elem(b.position, 0),
        y: elem(b.position, 1),
        owner_id: b.owner_id,
        health: Float.round(ensure_float(b.health), 1),
        level: b.level,
        emoji: emoji(b.type),
        color: color(b.type),
        w: w,
        h: h
      }
    end)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0
end
