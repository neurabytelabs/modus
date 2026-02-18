defmodule Modus.Simulation.PathSystem do
  @moduledoc """
  PathSystem — Road & path system for MODUS.

  v4.3.0 Via: "All roads are made by walking."

  Tracks agent movement and creates desire paths — tiles that are
  frequently walked become trails, roads, and highways. Paths speed
  up movement and enable trade routes between settlements.

  ## Path Tiers

  - `:dirt_trail` — 10+ walks → +20% speed
  - `:road`       — 50+ walks → +50% speed
  - `:highway`    — 200+ walks → +100% speed

  ## Features

  - Desire paths from agent foot traffic (ETS counter)
  - Tier upgrades as traffic increases
  - Path decay: unused paths lose 1 walk per 100 ticks
  - Movement speed bonus on paths
  - Trade route detection between settlements
  - Bridge construction over water tiles
  - A* pathfinding using terrain + path costs

  ## ETS Storage

  Path data in `:modus_paths` — `{{x, y}, %{walks: int, tier: atom, last_walked: int}}`
  Bridge data in `:modus_bridges` — `{{x, y}, %{built_by: str, built_tick: int, health: float}}`
  """

  alias Modus.Simulation.TerrainGenerator
  alias Modus.Simulation.WaterSystem

  @type tier :: :none | :dirt_trail | :road | :highway
  @type path_cell :: %{
          walks: non_neg_integer(),
          tier: tier(),
          last_walked: non_neg_integer()
        }
  @type bridge :: %{
          built_by: String.t(),
          built_tick: non_neg_integer(),
          health: float()
        }

  # Tier thresholds
  @trail_threshold 10
  @road_threshold 50
  @highway_threshold 200

  # Speed bonuses (multiplier on base speed)
  @speed_bonus %{
    none: 1.0,
    dirt_trail: 1.2,
    road: 1.5,
    highway: 2.0
  }

  # Decay: lose 1 walk per this many ticks of inactivity
  @decay_interval 100

  # Bridge build cost
  @bridge_cost %{wood: 10, stone: 5}

  # A* heuristic weight
  @astar_max_iterations 2000

  # ── Public API ──────────────────────────────────────────────

  @doc "Initialize ETS tables for paths and bridges."
  @spec init() :: :ok
  def init do
    ensure_table(:modus_paths)
    ensure_table(:modus_bridges)
    :ok
  end

  @doc "Record an agent walking on a tile. Increments walk counter and updates tier."
  @spec record_walk(integer(), integer(), non_neg_integer()) :: path_cell()
  def record_walk(x, y, current_tick) do
    ensure_table(:modus_paths)

    cell =
      case :ets.lookup(:modus_paths, {x, y}) do
        [{{^x, ^y}, existing}] -> existing
        _ -> %{walks: 0, tier: :none, last_walked: 0}
      end

    new_walks = cell.walks + 1
    new_tier = tier_for_walks(new_walks)

    updated = %{cell | walks: new_walks, tier: new_tier, last_walked: current_tick}
    :ets.insert(:modus_paths, {{x, y}, updated})
    updated
  end

  @doc "Get path data at a coordinate."
  @spec get(integer(), integer()) :: path_cell() | nil
  def get(x, y) do
    case :ets.lookup(:modus_paths, {x, y}) do
      [{{^x, ^y}, data}] -> data
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Get the movement speed multiplier at a position (terrain + path combined)."
  @spec movement_multiplier(integer(), integer()) :: float()
  def movement_multiplier(x, y) do
    path_bonus =
      case get(x, y) do
        %{tier: tier} -> Map.get(@speed_bonus, tier, 1.0)
        nil -> 1.0
      end

    terrain_cost =
      case TerrainGenerator.get(x, y) do
        %{biome: biome} -> TerrainGenerator.movement_cost(biome)
        _ -> 1.0
      end

    # If terrain is impassable and no bridge, can't walk
    case terrain_cost do
      :impassable ->
        if has_bridge?(x, y), do: path_bonus, else: 0.0

      cost when is_number(cost) ->
        ensure_float(path_bonus / cost)
    end
  end

  @doc "Get the tier for a position."
  @spec tier_at(integer(), integer()) :: tier()
  def tier_at(x, y) do
    case get(x, y) do
      %{tier: tier} -> tier
      nil -> :none
    end
  end

  @doc "Decay all paths. Call periodically (e.g., every 100 ticks)."
  @spec decay_paths(non_neg_integer()) :: non_neg_integer()
  def decay_paths(current_tick) do
    ensure_table(:modus_paths)

    decayed =
      :ets.foldl(
        fn {{x, y}, cell}, acc ->
          ticks_idle = current_tick - cell.last_walked

          if ticks_idle >= @decay_interval and cell.walks > 0 do
            decay_amount = div(ticks_idle, @decay_interval)
            new_walks = max(0, cell.walks - decay_amount)
            new_tier = tier_for_walks(new_walks)

            if new_walks == 0 do
              :ets.delete(:modus_paths, {x, y})
            else
              :ets.insert(:modus_paths, {{x, y}, %{cell | walks: new_walks, tier: new_tier}})
            end

            acc + 1
          else
            acc
          end
        end,
        0,
        :modus_paths
      )

    decayed
  end

  # ── Bridges ─────────────────────────────────────────────────

  @doc "Build a bridge over a water tile."
  @spec build_bridge(integer(), integer(), String.t(), non_neg_integer()) ::
          {:ok, bridge()} | {:error, atom()}
  def build_bridge(x, y, agent_id, current_tick) do
    ensure_table(:modus_bridges)

    cond do
      has_bridge?(x, y) ->
        {:error, :already_exists}

      WaterSystem.get(x, y) == nil ->
        {:error, :not_water}

      true ->
        bridge = %{built_by: agent_id, built_tick: current_tick, health: 1.0}
        :ets.insert(:modus_bridges, {{x, y}, bridge})
        {:ok, bridge}
    end
  end

  @doc "Check if a bridge exists at position."
  @spec has_bridge?(integer(), integer()) :: boolean()
  def has_bridge?(x, y) do
    case :ets.lookup(:modus_bridges, {x, y}) do
      [_] -> true
      _ -> false
    end
  rescue
    ArgumentError -> false
  end

  @doc "Get bridge cost requirements."
  @spec bridge_cost() :: map()
  def bridge_cost, do: @bridge_cost

  # ── Trade Routes ────────────────────────────────────────────

  @doc """
  Detect trade routes: paths of tier :road or higher connecting
  two settlement positions. Returns list of {from, to, path_tiles}.
  """
  @spec detect_trade_routes(list({integer(), integer()})) :: list()
  def detect_trade_routes(settlement_positions) when is_list(settlement_positions) do
    ensure_table(:modus_paths)

    pairs = for a <- settlement_positions, b <- settlement_positions, a < b, do: {a, b}

    Enum.reduce(pairs, [], fn {{x1, y1}, {x2, y2}}, acc ->
      case find_path({x1, y1}, {x2, y2}) do
        {:ok, path} ->
          road_tiles =
            Enum.filter(path, fn {px, py} ->
              case get(px, py) do
                %{tier: tier} when tier in [:road, :highway] -> true
                _ -> false
              end
            end)

          # At least 50% of path must be road/highway to count as trade route
          if length(road_tiles) >= length(path) * 0.5 do
            [{{{x1, y1}, {x2, y2}}, path} | acc]
          else
            acc
          end

        :no_path ->
          acc
      end
    end)
  end

  # ── A* Pathfinding ──────────────────────────────────────────

  @doc "Find optimal path between two points using A* with terrain and path costs."
  @spec find_path({integer(), integer()}, {integer(), integer()}) ::
          {:ok, list({integer(), integer()})} | :no_path
  def find_path(start, goal) do
    find_path(start, goal, 100)
  end

  @doc "Find path with explicit world size limit."
  @spec find_path({integer(), integer()}, {integer(), integer()}, integer()) ::
          {:ok, list({integer(), integer()})} | :no_path
  def find_path({sx, sy} = start, {gx, gy} = goal, _world_size) do
    # A* implementation
    open = :gb_sets.singleton({heuristic(sx, sy, gx, gy), 0.0, start})
    g_scores = %{start => 0.0}
    came_from = %{}

    astar_loop(open, g_scores, came_from, goal, 0)
  end

  defp astar_loop(_open, _g_scores, _came_from, _goal, iterations)
       when iterations > @astar_max_iterations do
    :no_path
  end

  defp astar_loop(open, g_scores, came_from, goal, iterations) do
    if :gb_sets.is_empty(open) do
      :no_path
    else
      {{_f, g, current}, rest} = :gb_sets.take_smallest(open)

      if current == goal do
        {:ok, reconstruct_path(came_from, current)}
      else
        {new_open, new_g, new_from} =
          Enum.reduce(neighbors(current), {rest, g_scores, came_from}, fn neighbor,
                                                                         {o, gs, cf} ->
            cost = move_cost(neighbor)

            if cost == :impassable do
              {o, gs, cf}
            else
              tentative_g = g + ensure_float(cost)

              if tentative_g < Map.get(gs, neighbor, :infinity) do
                {nx, ny} = neighbor
                {gx, gy} = goal
                f = tentative_g + heuristic(nx, ny, gx, gy)
                new_o = :gb_sets.add({f, tentative_g, neighbor}, o)
                new_gs = Map.put(gs, neighbor, tentative_g)
                new_cf = Map.put(cf, neighbor, current)
                {new_o, new_gs, new_cf}
              else
                {o, gs, cf}
              end
            end
          end)

        astar_loop(new_open, new_g, new_from, goal, iterations + 1)
      end
    end
  end

  defp neighbors({x, y}) do
    [{x - 1, y}, {x + 1, y}, {x, y - 1}, {x, y + 1}]
  end

  defp move_cost({x, y}) do
    terrain_cost =
      case TerrainGenerator.get(x, y) do
        %{biome: biome} -> TerrainGenerator.movement_cost(biome)
        _ -> 1.0
      end

    case terrain_cost do
      :impassable ->
        if has_bridge?(x, y), do: 1.0, else: :impassable

      cost ->
        # Path bonus reduces cost
        path_bonus =
          case get(x, y) do
            %{tier: tier} -> Map.get(@speed_bonus, tier, 1.0)
            nil -> 1.0
          end

        ensure_float(cost / path_bonus)
    end
  end

  defp heuristic(x1, y1, x2, y2) do
    ensure_float(abs(x1 - x2) + abs(y1 - y2))
  end

  defp reconstruct_path(came_from, current) do
    reconstruct_path(came_from, current, [current])
  end

  defp reconstruct_path(came_from, current, path) do
    case Map.get(came_from, current) do
      nil -> path
      prev -> reconstruct_path(came_from, prev, [prev | path])
    end
  end

  # ── Visual Data ─────────────────────────────────────────────

  @doc "Get all path data for rendering."
  @spec get_all_paths() :: list()
  def get_all_paths do
    ensure_table(:modus_paths)

    :ets.foldl(
      fn {{x, y}, cell}, acc ->
        [%{x: x, y: y, tier: cell.tier, walks: cell.walks} | acc]
      end,
      [],
      :modus_paths
    )
  rescue
    ArgumentError -> []
  end

  @doc "Get all bridges for rendering."
  @spec get_all_bridges() :: list()
  def get_all_bridges do
    ensure_table(:modus_bridges)

    :ets.foldl(
      fn {{x, y}, bridge}, acc ->
        [%{x: x, y: y, health: bridge.health, built_by: bridge.built_by} | acc]
      end,
      [],
      :modus_bridges
    )
  rescue
    ArgumentError -> []
  end

  @doc "Path tier color for rendering overlay."
  @spec tier_color(tier()) :: String.t()
  def tier_color(:dirt_trail), do: "#8B7355"
  def tier_color(:road), do: "#A0522D"
  def tier_color(:highway), do: "#696969"
  def tier_color(_), do: "transparent"

  @doc "Path tier emoji."
  @spec tier_emoji(tier()) :: String.t()
  def tier_emoji(:dirt_trail), do: "·"
  def tier_emoji(:road), do: "═"
  def tier_emoji(:highway), do: "█"
  def tier_emoji(_), do: ""

  # ── Stats ───────────────────────────────────────────────────

  @doc "Get path system statistics."
  @spec stats() :: map()
  def stats do
    ensure_table(:modus_paths)
    ensure_table(:modus_bridges)

    paths = get_all_paths()
    bridges = get_all_bridges()

    tier_counts =
      Enum.reduce(paths, %{dirt_trail: 0, road: 0, highway: 0}, fn p, acc ->
        if p.tier != :none do
          Map.update(acc, p.tier, 1, &(&1 + 1))
        else
          acc
        end
      end)

    %{
      total_paths: length(paths),
      trails: Map.get(tier_counts, :dirt_trail, 0),
      roads: Map.get(tier_counts, :road, 0),
      highways: Map.get(tier_counts, :highway, 0),
      bridges: length(bridges),
      total_walks: Enum.reduce(paths, 0, fn p, acc -> acc + p.walks end)
    }
  end

  # ── Private ─────────────────────────────────────────────────

  defp tier_for_walks(walks) when walks >= @highway_threshold, do: :highway
  defp tier_for_walks(walks) when walks >= @road_threshold, do: :road
  defp tier_for_walks(walks) when walks >= @trail_threshold, do: :dirt_trail
  defp tier_for_walks(_), do: :none

  defp ensure_table(name) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, [:set, :public, :named_table])
      _ -> :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0
end
