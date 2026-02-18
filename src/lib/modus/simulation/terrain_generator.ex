defmodule Modus.Simulation.TerrainGenerator do
  @moduledoc """
  TerrainGenerator — Perlin-noise terrain with biomes.

  Generates rich terrain using layered 2D Perlin noise for elevation,
  temperature, and moisture. These three maps determine biome assignment.

  ## Biomes

  - `:ocean`    — deep water (elevation < 0.30)
  - `:desert`   — hot & dry
  - `:plains`   — temperate grassland
  - `:forest`   — temperate & moist
  - `:swamp`    — low elevation, very moist
  - `:mountain` — high elevation
  - `:tundra`   — cold & dry

  ## Template Presets

  - `:island`       — central landmass surrounded by ocean
  - `:continent`    — large landmass, ocean on edges
  - `:archipelago`  — many small islands
  - `:pangaea`      — almost all land, minimal water

  ## ETS Storage

  Terrain data stored in `:modus_terrain` for O(1) lookups.
  Each entry: `{{x, y}, %{biome: atom, elevation: float, temperature: float, moisture: float}}`
  """

  @type biome :: :ocean | :desert | :plains | :forest | :swamp | :mountain | :tundra
  @type preset :: :island | :continent | :archipelago | :pangaea

  @biome_terrain %{
    ocean: :water,
    desert: :desert,
    plains: :grass,
    forest: :forest,
    swamp: :swamp,
    mountain: :mountain,
    tundra: :tundra
  }

  @biome_emoji %{
    ocean: "🌊",
    desert: "🏜️",
    plains: "🌾",
    forest: "🌲",
    swamp: "🪷",
    mountain: "⛰️",
    tundra: "❄️"
  }

  @biome_color %{
    ocean: "#1a5276",
    desert: "#f0c27a",
    plains: "#7dcea0",
    forest: "#1e8449",
    swamp: "#6c7a3a",
    mountain: "#808080",
    tundra: "#d5e8f0"
  }

  # Movement cost multiplier per biome (1.0 = normal)
  @movement_cost %{
    ocean: :impassable,
    desert: 1.8,
    plains: 1.0,
    forest: 1.4,
    swamp: 2.0,
    mountain: 2.5,
    tundra: 1.6
  }

  # Resources per biome
  @biome_resources %{
    ocean: %{fish: 8, fresh_water: 10},
    desert: %{stone: 3},
    plains: %{food: 5, wild_berries: 3},
    forest: %{food: 3, wood: 10, herbs: 2},
    swamp: %{herbs: 8, food: 2},
    mountain: %{stone: 12, ore: 6},
    tundra: %{stone: 4, food: 1}
  }

  # ── Public API ──────────────────────────────────────────────

  @doc "Generate terrain for a world grid and store in ETS."
  @spec generate(integer(), integer(), integer(), preset()) :: :ets.tid()
  def generate(width, height, seed, preset \\ :continent) do
    table = ensure_table()

    for x <- 0..(width - 1), y <- 0..(height - 1) do
      elevation = elevation_at(x, y, seed, width, height, preset)
      temperature = temperature_at(x, y, seed, height)
      moisture = moisture_at(x, y, seed)
      biome = assign_biome(elevation, temperature, moisture)

      entry = %{
        biome: biome,
        elevation: elevation,
        temperature: temperature,
        moisture: moisture
      }

      :ets.insert(table, {{x, y}, entry})
    end

    table
  end

  @doc "Get terrain data at a coordinate."
  @spec get(integer(), integer()) :: map() | nil
  def get(x, y) do
    case :ets.lookup(:modus_terrain, {x, y}) do
      [{{^x, ^y}, data}] -> data
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Get the biome at a coordinate."
  @spec biome_at(integer(), integer()) :: biome() | nil
  def biome_at(x, y) do
    case get(x, y) do
      %{biome: biome} -> biome
      _ -> nil
    end
  end

  @doc "Get the terrain type (for World grid compatibility)."
  @spec terrain_type(biome()) :: atom()
  def terrain_type(biome), do: Map.get(@biome_terrain, biome, :grass)

  @doc "Get movement cost for a biome. Returns :impassable or float."
  @spec movement_cost(biome()) :: :impassable | float()
  def movement_cost(biome), do: Map.get(@movement_cost, biome, 1.0)

  @doc "Get default resources for a biome."
  @spec biome_resources(biome()) :: map()
  def biome_resources(biome), do: Map.get(@biome_resources, biome, %{})

  @doc "Get emoji for a biome."
  @spec biome_emoji(biome()) :: String.t()
  def biome_emoji(biome), do: Map.get(@biome_emoji, biome, "⬜")

  @doc "Get color hex for a biome."
  @spec biome_color(biome()) :: String.t()
  def biome_color(biome), do: Map.get(@biome_color, biome, "#888888")

  @doc "Check if a position is walkable."
  @spec walkable?(integer(), integer()) :: boolean()
  def walkable?(x, y) do
    case biome_at(x, y) do
      :ocean -> false
      nil -> false
      _ -> true
    end
  end

  @doc "All biome types."
  @spec biomes() :: [biome()]
  def biomes, do: [:ocean, :desert, :plains, :forest, :swamp, :mountain, :tundra]

  @doc "All preset types."
  @spec presets() :: [preset()]
  def presets, do: [:island, :continent, :archipelago, :pangaea]

  # ── Elevation ───────────────────────────────────────────────

  defp elevation_at(x, y, seed, width, height, preset) do
    # 3-octave Perlin noise
    e1 = perlin(x, y, seed, 32)
    e2 = perlin(x, y, seed + 1000, 16)
    e3 = perlin(x, y, seed + 2000, 8)
    raw = e1 * 0.5 + e2 * 0.3 + e3 * 0.2

    # Apply preset mask
    apply_preset(raw, x, y, width, height, preset)
  end

  defp apply_preset(raw, x, y, width, height, :island) do
    # Radial gradient — center high, edges low
    cx = ef(width) / 2.0
    cy = ef(height) / 2.0
    dx = (ef(x) - cx) / cx
    dy = (ef(y) - cy) / cy
    dist = :math.sqrt(dx * dx + dy * dy)
    mask = max(0.0, 1.0 - dist * 1.2)
    clamp(raw * mask + 0.1 * mask)
  end

  defp apply_preset(raw, x, y, width, height, :continent) do
    # Gentle falloff at edges
    cx = ef(width) / 2.0
    cy = ef(height) / 2.0
    dx = abs(ef(x) - cx) / cx
    dy = abs(ef(y) - cy) / cy
    edge = max(dx, dy)
    mask = max(0.0, 1.0 - edge * 0.8)
    clamp(raw * 0.7 + mask * 0.3)
  end

  defp apply_preset(raw, x, y, width, height, :archipelago) do
    # Multiple island centers using additional noise
    island_noise = perlin(x, y, 99999, 12)
    cx = ef(width) / 2.0
    cy = ef(height) / 2.0
    dx = (ef(x) - cx) / cx
    dy = (ef(y) - cy) / cy
    dist = :math.sqrt(dx * dx + dy * dy)
    edge_mask = max(0.0, 1.0 - dist * 1.0)
    # Islands form where island_noise > 0.5
    island_mask = if island_noise > 0.45, do: 1.0, else: island_noise * 1.5
    clamp(raw * island_mask * edge_mask)
  end

  defp apply_preset(raw, _x, _y, _width, _height, :pangaea) do
    # Mostly land — push elevation up
    clamp(raw * 0.6 + 0.35)
  end

  # ── Temperature & Moisture ─────────────────────────────────

  defp temperature_at(x, y, seed, height) do
    # Latitude-based + noise variation
    latitude = ef(y) / ef(max(height - 1, 1))
    # Warmer in center, colder at top/bottom
    base_temp = 1.0 - abs(latitude - 0.5) * 2.0
    noise = perlin(x, y, seed + 5000, 24)
    clamp(base_temp * 0.7 + noise * 0.3)
  end

  defp moisture_at(x, y, seed) do
    m1 = perlin(x, y, seed + 3000, 20)
    m2 = perlin(x, y, seed + 4000, 10)
    clamp(m1 * 0.6 + m2 * 0.4)
  end

  # ── Biome Assignment ────────────────────────────────────────

  @doc "Assign biome based on elevation, temperature, moisture."
  @spec assign_biome(float(), float(), float()) :: biome()
  def assign_biome(elevation, temperature, moisture) do
    cond do
      elevation < 0.30 -> :ocean
      elevation > 0.75 -> :mountain
      temperature < 0.25 -> :tundra
      temperature > 0.70 and moisture < 0.30 -> :desert
      moisture > 0.65 and elevation < 0.45 -> :swamp
      moisture > 0.45 -> :forest
      true -> :plains
    end
  end

  # ── Perlin Noise (Pure Elixir) ──────────────────────────────

  @doc false
  def perlin(x, y, seed, scale) do
    # Grid coordinates
    sx = ef(x) / ef(max(scale, 1))
    sy = ef(y) / ef(max(scale, 1))

    x0 = floor(sx) |> trunc()
    y0 = floor(sy) |> trunc()
    x1 = x0 + 1
    y1 = y0 + 1

    # Fractional position
    fx = sx - ef(x0)
    fy = sy - ef(y0)

    # Gradient dot products at four corners
    d00 = grad_dot(x0, y0, fx, fy, seed)
    d10 = grad_dot(x1, y0, fx - 1.0, fy, seed)
    d01 = grad_dot(x0, y1, fx, fy - 1.0, seed)
    d11 = grad_dot(x1, y1, fx - 1.0, fy - 1.0, seed)

    # Smoothstep interpolation
    u = smoothstep(fx)
    v = smoothstep(fy)

    top = lerp(d00, d10, u)
    bot = lerp(d01, d11, u)
    result = lerp(top, bot, v)

    # Normalize from [-1,1] to [0,1]
    clamp(result * 0.5 + 0.5)
  end

  defp grad_dot(gx, gy, dx, dy, seed) do
    # Hash to select one of 4 gradient vectors
    h = :erlang.phash2({gx, gy, seed}, 4)

    case h do
      0 -> dx + dy
      1 -> dx - dy
      2 -> -dx + dy
      3 -> -dx - dy
    end
  end

  defp smoothstep(t), do: t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
  defp lerp(a, b, t), do: a + (b - a) * t
  defp clamp(v), do: max(0.0, min(1.0, v))
  defp ef(v) when is_float(v), do: v
  defp ef(v) when is_integer(v), do: v * 1.0
  defp ef(_), do: 0.0

  # ── ETS Table ───────────────────────────────────────────────

  defp ensure_table do
    case :ets.whereis(:modus_terrain) do
      :undefined ->
        :ets.new(:modus_terrain, [:set, :public, :named_table, read_concurrency: true])

      tid ->
        :ets.delete_all_objects(tid)
        tid
    end
  end
end
