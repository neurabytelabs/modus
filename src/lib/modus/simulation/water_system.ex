defmodule Modus.Simulation.WaterSystem do
  @moduledoc """
  WaterSystem — Water flow simulation for MODUS.

  v4.2.0 Aqua: "Water finds its own level."

  Generates rivers and lakes from terrain elevation data produced by
  `TerrainGenerator`. Rivers flow downhill from mountains to ocean;
  lakes form in terrain depressions where water pools.

  ## Features

  - River generation via steepest-descent tracing from mountain peaks
  - Lake detection in terrain depressions (local minima)
  - Fishing spots along rivers and lakes
  - Water as movement barrier (agents need bridges/fords)
  - Irrigation bonus for nearby farms
  - Seasonal flooding (spring) and drought (summer)
  - Water pollution from large settlements

  ## ETS Storage

  Water data stored in `:modus_water` for O(1) lookups.
  Each entry: `{{x, y}, %{type: :river | :lake, flow_dir: {dx, dy} | nil, depth: float, pollution: float}}`
  """

  alias Modus.Simulation.TerrainGenerator

  @type water_type :: :river | :lake
  @type water_cell :: %{
          type: water_type(),
          flow_dir: {integer(), integer()} | nil,
          depth: float(),
          pollution: float(),
          fishing_spot: boolean()
        }

  # How many rivers to generate per 1000 tiles
  @rivers_per_1000 3
  # Min elevation to start a river
  @river_source_elevation 0.70
  # Depression threshold for lake formation
  @lake_depression_threshold 0.02
  # Max lake radius
  @max_lake_radius 4
  # Irrigation range (Manhattan distance)
  @irrigation_range 2
  # Flood probability per season tick (spring)
  @spring_flood_chance 0.15
  # Pollution per 10 agents in settlement
  # Pollution per 10 agents in settlement (used by external callers)
  # @pollution_per_10_agents 0.1

  # ── Public API ──────────────────────────────────────────────

  @doc "Generate water features for a world and store in ETS."
  @spec generate(integer(), integer(), integer()) :: :ok
  def generate(width, height, seed) do
    ensure_table()

    # Step 1: Generate rivers from high points
    rivers = generate_rivers(width, height, seed)

    # Step 2: Detect lake depressions
    lakes = detect_lakes(width, height, seed)

    # Step 3: Store all water cells
    store_water_cells(rivers, lakes)

    :ok
  end

  @doc "Get water data at a coordinate."
  @spec get(integer(), integer()) :: water_cell() | nil
  def get(x, y) do
    case :ets.lookup(:modus_water, {x, y}) do
      [{{^x, ^y}, data}] -> data
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Check if a position has water."
  @spec water?(integer(), integer()) :: boolean()
  def water?(x, y), do: get(x, y) != nil

  @doc "Check if a position is a river."
  @spec river?(integer(), integer()) :: boolean()
  def river?(x, y) do
    case get(x, y) do
      %{type: :river} -> true
      _ -> false
    end
  end

  @doc "Check if a position is a lake."
  @spec lake?(integer(), integer()) :: boolean()
  def lake?(x, y) do
    case get(x, y) do
      %{type: :lake} -> true
      _ -> false
    end
  end

  @doc "Check if a position is a fishing spot."
  @spec fishing_spot?(integer(), integer()) :: boolean()
  def fishing_spot?(x, y) do
    case get(x, y) do
      %{fishing_spot: true} -> true
      _ -> false
    end
  end

  @doc "Check if water blocks movement (no bridge/ford)."
  @spec blocks_movement?(integer(), integer()) :: boolean()
  def blocks_movement?(x, y) do
    case get(x, y) do
      %{type: :river, depth: d} when d > 0.5 -> true
      %{type: :lake} -> true
      _ -> false
    end
  end

  @doc "Check if position is a ford (shallow river crossing)."
  @spec ford?(integer(), integer()) :: boolean()
  def ford?(x, y) do
    case get(x, y) do
      %{type: :river, depth: d} when d <= 0.5 -> true
      _ -> false
    end
  end

  @doc """
  Get irrigation bonus multiplier for a position.
  Farms near water grow faster: 1.5x within range, 1.0x otherwise.
  """
  @spec irrigation_bonus(integer(), integer()) :: float()
  def irrigation_bonus(x, y) do
    has_water_nearby =
      for dx <- -@irrigation_range..@irrigation_range,
          dy <- -@irrigation_range..@irrigation_range,
          abs(dx) + abs(dy) <= @irrigation_range,
          abs(dx) + abs(dy) > 0,
          reduce: false do
        true -> true
        false -> water?(x + dx, y + dy)
      end

    if has_water_nearby, do: 1.5, else: 1.0
  end

  @doc """
  Apply seasonal effects to water system.
  - Spring: rivers may flood (expand 1 tile, increase depth)
  - Summer: rivers shrink (reduce depth)
  """
  @spec apply_season(:spring | :summer | :autumn | :winter) :: :ok
  def apply_season(season) do
    case season do
      :spring -> apply_spring_floods()
      :summer -> apply_summer_drought()
      _ -> :ok
    end
  end

  @doc """
  Add pollution to water at position from settlement activity.
  Pollution ranges 0.0 to 1.0.
  """
  @spec add_pollution(integer(), integer(), float()) :: :ok
  def add_pollution(x, y, amount) do
    case get(x, y) do
      nil ->
        :ok

      cell ->
        new_pollution = min(1.0, cell.pollution + ensure_float(amount))
        :ets.insert(:modus_water, {{x, y}, %{cell | pollution: new_pollution}})
        :ok
    end
  end

  @doc "Get all water cells as a list of {{x,y}, cell} tuples."
  @spec all_water() :: [{{integer(), integer()}, water_cell()}]
  def all_water do
    case :ets.whereis(:modus_water) do
      :undefined -> []
      _tid -> :ets.tab2list(:modus_water)
    end
  rescue
    ArgumentError -> []
  end

  @doc "Get all fishing spots."
  @spec fishing_spots() :: [{integer(), integer()}]
  def fishing_spots do
    all_water()
    |> Enum.filter(fn {_pos, cell} -> cell.fishing_spot end)
    |> Enum.map(fn {pos, _cell} -> pos end)
  end

  @doc "Count water tiles by type."
  @spec stats() :: %{rivers: integer(), lakes: integer(), fishing_spots: integer(), total: integer()}
  def stats do
    cells = all_water()
    rivers = Enum.count(cells, fn {_, c} -> c.type == :river end)
    lakes = Enum.count(cells, fn {_, c} -> c.type == :lake end)
    fishing = Enum.count(cells, fn {_, c} -> c.fishing_spot end)
    %{rivers: rivers, lakes: lakes, fishing_spots: fishing, total: length(cells)}
  end

  # ── River Generation ────────────────────────────────────────

  defp generate_rivers(width, height, seed) do
    total_tiles = width * height
    num_rivers = max(1, div(total_tiles * @rivers_per_1000, 1000))

    # Find mountain/high-elevation starting points
    sources = find_river_sources(width, height, seed, num_rivers)

    # Trace each river downhill
    Enum.flat_map(sources, fn source ->
      trace_river(source, width, height, MapSet.new())
    end)
  end

  defp find_river_sources(width, height, _seed, count) do
    # Collect high-elevation land tiles
    candidates =
      for x <- 0..(width - 1),
          y <- 0..(height - 1),
          terrain = TerrainGenerator.get(x, y),
          terrain != nil,
          terrain.elevation >= @river_source_elevation,
          terrain.biome == :mountain,
          do: {x, y, terrain.elevation}

    # Sort by elevation (highest first) and pick evenly spaced ones
    candidates
    |> Enum.sort_by(fn {_, _, e} -> -e end)
    |> Enum.take(count * 3)
    |> Enum.take_every(max(1, div(length(candidates), max(count, 1))))
    |> Enum.take(count)
    |> Enum.map(fn {x, y, _} -> {x, y} end)
  end

  defp trace_river({x, y}, width, height, visited) do
    if x < 0 or y < 0 or x >= width or y >= height or MapSet.member?(visited, {x, y}) do
      []
    else
      terrain = TerrainGenerator.get(x, y)

      cond do
        terrain == nil ->
          []

        # Reached ocean — stop
        terrain.biome == :ocean ->
          []

        true ->
          current_elev = terrain.elevation
          visited = MapSet.put(visited, {x, y})

          # Find steepest descent neighbor
          neighbors =
            for dx <- -1..1, dy <- -1..1, {dx, dy} != {0, 0} do
              nx = x + dx
              ny = y + dy
              nt = TerrainGenerator.get(nx, ny)
              if nt, do: {nx, ny, dx, dy, nt.elevation}, else: nil
            end
            |> Enum.reject(&is_nil/1)
            |> Enum.filter(fn {_, _, _, _, e} -> e < current_elev end)
            |> Enum.sort_by(fn {_, _, _, _, e} -> e end)

          case neighbors do
            [] ->
              # Depression — river ends here (potential lake seed)
              depth = 0.3 + current_elev * 0.4
              [{x, y, {0, 0}, depth}]

            [{nx, ny, dx, dy, _} | _] ->
              depth = 0.2 + (1.0 - current_elev) * 0.6
              [{x, y, {dx, dy}, depth} | trace_river({nx, ny}, width, height, visited)]
          end
      end
    end
  end

  # ── Lake Detection ──────────────────────────────────────────

  defp detect_lakes(width, height, seed) do
    # Find local elevation minima (surrounded by higher terrain)
    depressions =
      for x <- 2..(width - 3),
          y <- 2..(height - 3),
          terrain = TerrainGenerator.get(x, y),
          terrain != nil,
          terrain.biome != :ocean,
          is_depression?(x, y, terrain.elevation),
          do: {x, y, terrain.elevation}

    # Expand each depression into a lake
    Enum.flat_map(depressions, fn {cx, cy, elev} ->
      radius = lake_radius(elev, seed, cx, cy)
      expand_lake(cx, cy, radius, width, height)
    end)
  end

  defp is_depression?(x, y, elevation) do
    neighbors =
      for dx <- -1..1, dy <- -1..1, {dx, dy} != {0, 0} do
        case TerrainGenerator.get(x + dx, y + dy) do
          %{elevation: e} -> e
          _ -> elevation
        end
      end

    min_neighbor = Enum.min(neighbors)
    # This tile is lower than all neighbors by threshold
    elevation <= min_neighbor + @lake_depression_threshold
    and Enum.all?(neighbors, fn e -> e >= elevation - 0.01 end)
  end

  defp lake_radius(elevation, seed, cx, cy) do
    # Lower elevation = bigger lake, with some randomness
    base = round((1.0 - elevation) * @max_lake_radius)
    noise = rem(:erlang.phash2({cx, cy, seed, :lake}, 3), 2)
    max(1, min(@max_lake_radius, base + noise))
  end

  defp expand_lake(cx, cy, radius, width, height) do
    for dx <- -radius..radius,
        dy <- -radius..radius,
        dx * dx + dy * dy <= radius * radius,
        nx = cx + dx,
        ny = cy + dy,
        nx >= 0 and ny >= 0 and nx < width and ny < height,
        terrain = TerrainGenerator.get(nx, ny),
        terrain != nil,
        terrain.biome != :ocean do
      depth = 0.4 + (1.0 - terrain.elevation) * 0.5
      {nx, ny, depth}
    end
  end

  # ── Storage ─────────────────────────────────────────────────

  defp store_water_cells(rivers, lakes) do
    # Store rivers
    Enum.each(rivers, fn {x, y, flow_dir, depth} ->
      cell = %{
        type: :river,
        flow_dir: flow_dir,
        depth: ensure_float(depth),
        pollution: 0.0,
        fishing_spot: is_fishing_spot?(:river, depth)
      }

      :ets.insert(:modus_water, {{x, y}, cell})
    end)

    # Store lakes (may overwrite river cells at intersections)
    Enum.each(lakes, fn {x, y, depth} ->
      # Don't overwrite existing river cells unless lake is deeper
      existing = get(x, y)

      if existing == nil or (existing.type == :river and depth > existing.depth) do
        cell = %{
          type: :lake,
          flow_dir: nil,
          depth: ensure_float(depth),
          pollution: 0.0,
          fishing_spot: is_fishing_spot?(:lake, depth)
        }

        :ets.insert(:modus_water, {{x, y}, cell})
      end
    end)
  end

  defp is_fishing_spot?(:river, depth) when depth > 0.3, do: true
  defp is_fishing_spot?(:lake, depth) when depth > 0.35, do: true
  defp is_fishing_spot?(_, _), do: false

  # ── Seasonal Effects ────────────────────────────────────────

  defp apply_spring_floods do
    all_water()
    |> Enum.filter(fn {_, cell} -> cell.type == :river end)
    |> Enum.each(fn {{x, y}, cell} ->
      # Increase depth slightly
      new_depth = min(1.0, cell.depth + 0.1)
      :ets.insert(:modus_water, {{x, y}, %{cell | depth: new_depth}})

      # Maybe flood adjacent tiles
      if :rand.uniform() < @spring_flood_chance do
        flood_adjacent(x, y, cell.depth * 0.5)
      end
    end)

    :ok
  end

  defp apply_summer_drought do
    all_water()
    |> Enum.each(fn {{x, y}, cell} ->
      new_depth = max(0.05, cell.depth - 0.15)
      :ets.insert(:modus_water, {{x, y}, %{cell | depth: new_depth}})
    end)

    :ok
  end

  defp flood_adjacent(x, y, depth) do
    for dx <- -1..1, dy <- -1..1, {dx, dy} != {0, 0} do
      nx = x + dx
      ny = y + dy

      unless water?(nx, ny) do
        terrain = TerrainGenerator.get(nx, ny)

        if terrain && terrain.biome not in [:ocean, :mountain] do
          cell = %{
            type: :river,
            flow_dir: {-dx, -dy},
            depth: ensure_float(depth),
            pollution: 0.0,
            fishing_spot: false
          }

          :ets.insert(:modus_water, {{x + dx, y + dy}, cell})
        end
      end
    end
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  defp ensure_table do
    case :ets.whereis(:modus_water) do
      :undefined ->
        :ets.new(:modus_water, [:set, :public, :named_table, read_concurrency: true])

      tid ->
        tid
    end
  end
end
