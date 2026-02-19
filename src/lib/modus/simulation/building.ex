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

  ## Upgrade Path (homes only)
  - Hut (level 1) → House (level 2): owner + conatus > 0.7 + 500 ticks old
  - House (level 2) → Mansion (level 3): owner + conatus > 0.7 + 500 ticks old

  ## Neighborhoods
  - 3+ buildings within 5 tiles = neighborhood
  - Auto-named, provides +0.02 social/tick to residents
  """

  require Logger

  @type building_type :: :hut | :house | :mansion | :farm | :market | :well | :watchtower

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
    hut: %{wood: 5},
    house: %{wood: 10, stone: 5},
    mansion: %{wood: 20, stone: 15},
    farm: %{wood: 3},
    market: %{wood: 8, stone: 8},
    well: %{stone: 10},
    watchtower: %{stone: 15, wood: 5}
  }

  # Upgrade costs (additional resources needed)
  @upgrade_costs %{
    # hut → house
    {1, 2} => %{wood: 8, stone: 5},
    # house → mansion
    {2, 3} => %{wood: 15, stone: 12}
  }

  @bonuses %{
    hut: %{rest: 10.0},
    house: %{rest: 15.0, shelter: 10.0},
    mansion: %{rest: 25.0, shelter: 20.0, social: 5.0},
    farm: %{hunger: -5.0},
    market: %{social: 5.0},
    well: %{rest: 5.0},
    watchtower: %{shelter: 5.0}
  }

  @emojis %{
    hut: "🛋",
    house: "🏠",
    mansion: "🏛",
    farm: "🌾",
    market: "🏪",
    well: "🪣",
    watchtower: "🗼"
  }

  @colors %{
    hut: 0x8B4513,
    house: 0xD2B48C,
    mansion: 0xFFD700,
    farm: 0x228B22,
    market: 0xDAA520,
    well: 0x4682B4,
    watchtower: 0x696969
  }

  @sizes %{
    hut: {12, 12},
    house: {16, 16},
    mansion: {22, 22},
    farm: {20, 14},
    market: {18, 18},
    well: {10, 10},
    watchtower: {10, 14}
  }

  # Level → type mapping for home upgrades
  @level_type %{1 => :hut, 2 => :house, 3 => :mansion}

  # Neighborhood name parts
  @neighborhood_prefixes [
    "Green",
    "Oak",
    "Sunset",
    "River",
    "Stone",
    "Golden",
    "Silver",
    "Willow",
    "Cedar",
    "Pine",
    "Maple",
    "Birch",
    "Elder",
    "Moss",
    "Fern"
  ]
  @neighborhood_suffixes [
    "Hill",
    "Vale",
    "Meadow",
    "Commons",
    "Quarter",
    "Heights",
    "Crossing",
    "Grove",
    "Hollow",
    "Haven",
    "Rest",
    "Glen",
    "Fields",
    "Row",
    "Park"
  ]

  # ── ETS Setup ─────────────────────────────────────────────

  def init_table do
    try do
      if :ets.whereis(:buildings) == :undefined do
        :ets.new(:buildings, [:named_table, :set, :public, read_concurrency: true])
      end
    rescue
      ArgumentError -> :ok
    end

    try do
      if :ets.whereis(:neighborhoods) == :undefined do
        :ets.new(:neighborhoods, [:named_table, :set, :public, read_concurrency: true])
      end
    rescue
      ArgumentError -> :ok
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

    level =
      case type do
        :hut -> 1
        :house -> 2
        :mansion -> 3
        _ -> 1
      end

    building = %{
      id: generate_id(),
      type: type,
      position: position,
      owner_id: owner_id,
      health: 100.0,
      level: level,
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

  @doc "Damage a building by amount. Removes it if health <= 0."
  @spec damage(String.t(), number()) :: :ok
  def damage(building_id, amount) do
    init_table()

    case :ets.lookup(:buildings, building_id) do
      [{^building_id, building}] ->
        new_health = building.health - amount

        if new_health <= 0 do
          :ets.delete(:buildings, building_id)
        else
          :ets.insert(:buildings, {building_id, %{building | health: new_health}})
        end

        :ok

      _ ->
        :ok
    end
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

  @doc "Check if agent has a home (hut, house, or mansion)."
  @spec has_home?(String.t()) :: boolean()
  def has_home?(agent_id) do
    owned_by(agent_id)
    |> Enum.any?(fn b -> b.type in [:hut, :house, :mansion] end)
  end

  @doc "Get agent's home building."
  @spec get_home(String.t()) :: t() | nil
  def get_home(agent_id) do
    owned_by(agent_id)
    |> Enum.find(fn b -> b.type in [:hut, :house, :mansion] end)
  end

  # ── Upgrade System ────────────────────────────────────────

  @doc "Check if a building can be upgraded. Requires owner, conatus > 0.7, 500+ ticks old."
  @spec can_upgrade?(t(), float(), integer()) :: boolean()
  def can_upgrade?(building, conatus_energy, current_tick) do
    building.type in [:hut, :house] and
      building.level < 3 and
      conatus_energy > 0.7 and
      current_tick - building.built_tick >= 500
  end

  @doc "Get upgrade cost for a building's next level."
  @spec upgrade_cost(t()) :: map()
  def upgrade_cost(building) do
    Map.get(@upgrade_costs, {building.level, building.level + 1}, %{})
  end

  @doc "Check if agent can afford upgrade."
  @spec can_afford_upgrade?(map(), t()) :: boolean()
  def can_afford_upgrade?(inventory, building) do
    cost = upgrade_cost(building)

    Enum.all?(cost, fn {resource, amount} ->
      Map.get(inventory, resource, 0) >= amount
    end)
  end

  @doc "Deduct upgrade costs from inventory."
  @spec deduct_upgrade_costs(map(), t()) :: map()
  def deduct_upgrade_costs(inventory, building) do
    cost = upgrade_cost(building)

    Enum.reduce(cost, inventory, fn {resource, amount}, inv ->
      current = Map.get(inv, resource, 0)
      Map.put(inv, resource, max(0, current - amount))
    end)
  end

  @doc "Upgrade a building to the next level. Returns {:ok, upgraded} or :error."
  @spec upgrade(String.t(), integer()) :: {:ok, t()} | :error
  def upgrade(building_id, tick) do
    init_table()

    case :ets.lookup(:buildings, building_id) do
      [{^building_id, building}] when building.level < 3 ->
        new_level = building.level + 1
        new_type = Map.get(@level_type, new_level, building.type)
        upgraded = %{building | level: new_level, type: new_type, health: 100.0, built_tick: tick}
        :ets.insert(:buildings, {building_id, upgraded})

        Logger.info(
          "MODUS Building upgraded: #{building.type}→#{new_type} (L#{new_level}) at #{inspect(building.position)}"
        )

        {:ok, upgraded}

      _ ->
        :error
    end
  end

  # ── Neighborhood System ───────────────────────────────────

  @doc """
  Detect neighborhoods: clusters of 3+ buildings within 5 tiles.
  Uses simple greedy clustering. Call periodically (every 100 ticks).
  Returns list of neighborhoods and stores in ETS.
  """
  @spec detect_neighborhoods() :: [map()]
  def detect_neighborhoods do
    init_table()
    buildings = all()

    # Group buildings into clusters (greedy: each building joins nearest cluster within 5 tiles)
    clusters = cluster_buildings(buildings, 5)

    # Only clusters with 3+ buildings become neighborhoods
    neighborhoods =
      clusters
      |> Enum.filter(fn cluster -> length(cluster) >= 3 end)
      |> Enum.with_index()
      |> Enum.map(fn {cluster, _idx} ->
        # Compute center
        positions = Enum.map(cluster, & &1.position)
        {cx, cy} = center_of(positions)

        # Generate stable name based on center position
        name = neighborhood_name(cx, cy)

        # Building IDs in this neighborhood
        building_ids = Enum.map(cluster, & &1.id)
        owner_ids = cluster |> Enum.map(& &1.owner_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

        hood = %{
          id: "hood_#{cx}_#{cy}",
          name: name,
          center: {cx, cy},
          building_ids: building_ids,
          resident_ids: owner_ids,
          size: length(cluster)
        }

        :ets.insert(:neighborhoods, {hood.id, hood})
        hood
      end)

    # Clean stale neighborhoods
    current_ids = MapSet.new(Enum.map(neighborhoods, & &1.id))

    :ets.tab2list(:neighborhoods)
    |> Enum.each(fn {id, _} ->
      unless MapSet.member?(current_ids, id), do: :ets.delete(:neighborhoods, id)
    end)

    neighborhoods
  end

  @doc "Get all neighborhoods."
  @spec neighborhoods() :: [map()]
  def neighborhoods do
    init_table()

    :ets.tab2list(:neighborhoods)
    |> Enum.map(fn {_id, n} -> n end)
  end

  @doc "Check if an agent is in any neighborhood."
  @spec agent_neighborhood(String.t()) :: map() | nil
  def agent_neighborhood(agent_id) do
    neighborhoods()
    |> Enum.find(fn n -> agent_id in n.resident_ids end)
  end

  @doc "Get neighborhood bonus for social need (+0.02 per tick if in neighborhood)."
  @spec neighborhood_social_bonus(String.t()) :: float()
  def neighborhood_social_bonus(agent_id) do
    case agent_neighborhood(agent_id) do
      nil -> 0.0
      _hood -> 0.02
    end
  end

  @doc "Serialize neighborhoods for client broadcast."
  @spec serialize_neighborhoods() :: [map()]
  def serialize_neighborhoods do
    neighborhoods()
    |> Enum.map(fn n ->
      %{
        id: n.id,
        name: n.name,
        x: elem(n.center, 0),
        y: elem(n.center, 1),
        size: n.size,
        resident_count: length(n.resident_ids)
      }
    end)
  end

  @doc "Find a build position near a friend's home."
  @spec friend_build_position(String.t()) :: {integer(), integer()} | nil
  def friend_build_position(agent_id) do
    alias Modus.Mind.Cerebro.SocialNetwork

    friends = SocialNetwork.get_friends(agent_id, 0.4)

    friend_homes =
      friends
      |> Enum.map(fn f -> get_home(f.id) end)
      |> Enum.reject(&is_nil/1)

    case friend_homes do
      [] ->
        nil

      homes ->
        # Pick closest friend's home, offset by 1-2 tiles
        home = Enum.random(homes)
        {hx, hy} = home.position
        dx = Enum.random([-2, -1, 1, 2])
        dy = Enum.random([-2, -1, 1, 2])
        {hx + dx, hy + dy}
    end
  end

  # ── Area Bonuses ──────────────────────────────────────────

  @doc "Apply building bonuses to an agent's needs if near a building."
  @spec apply_area_bonuses(map(), {integer(), integer()}) :: map()
  def apply_area_bonuses(needs, position) do
    {ax, ay} = position

    nearby_buildings =
      all()
      |> Enum.filter(fn b ->
        {bx, by} = b.position
        abs(bx - ax) <= 2 and abs(by - ay) <= 2
      end)

    Enum.reduce(nearby_buildings, needs, fn building, acc ->
      bonus = bonuses(building.type)
      # Level multiplier: L2=1.5x, L3=2x
      level_mult =
        case building.level do
          1 -> 1.0
          2 -> 1.5
          3 -> 2.0
          _ -> 1.0
        end

      Enum.reduce(bonus, acc, fn {need, amount}, n ->
        current = Map.get(n, need, 0.0)
        new_val = max(0.0, min(100.0, current + amount * 0.1 * level_mult))
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

          Logger.info(
            "MODUS Building destroyed (decay): #{building.type} at #{inspect(building.position)}"
          )
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

  # ── Private Helpers ───────────────────────────────────────

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  defp cluster_buildings(buildings, radius) do
    # Simple greedy clustering
    Enum.reduce(buildings, [], fn building, clusters ->
      {bx, by} = building.position
      # Find first cluster within radius
      idx =
        Enum.find_index(clusters, fn cluster ->
          Enum.any?(cluster, fn b ->
            {cx, cy} = b.position
            abs(cx - bx) <= radius and abs(cy - by) <= radius
          end)
        end)

      case idx do
        nil ->
          clusters ++ [[building]]

        i ->
          List.update_at(clusters, i, fn cluster -> [building | cluster] end)
      end
    end)
  end

  defp center_of(positions) do
    count = length(positions)

    if count == 0 do
      {0, 0}
    else
      {sx, sy} = Enum.reduce(positions, {0, 0}, fn {x, y}, {ax, ay} -> {ax + x, ay + y} end)
      {div(sx, count), div(sy, count)}
    end
  end

  defp neighborhood_name(x, y) do
    # Deterministic name from position
    prefix_idx = rem(abs(x * 7 + y * 13), length(@neighborhood_prefixes))
    suffix_idx = rem(abs(x * 11 + y * 3), length(@neighborhood_suffixes))

    "#{Enum.at(@neighborhood_prefixes, prefix_idx)} #{Enum.at(@neighborhood_suffixes, suffix_idx)}"
  end
end
