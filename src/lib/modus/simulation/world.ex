defmodule Modus.Simulation.World do
  @moduledoc """
  World — The universe container.

  Manages the grid, resources, and coordinates the tick loop.
  In Spinoza's terms, the World is "Substance" — the one reality
  in which all agents (modi) exist.

  ## Architecture

  - Grid: 50x50 ETS table with terrain types
  - Tick: 100ms interval, coordinated by Ticker
  - Broadcast: Delta-only updates via PubSub

  ## Terrain Types

  - `:grass`    — open plains, easy movement
  - `:water`    — rivers/lakes, blocks land agents
  - `:forest`   — dense woodland, slower movement
  - `:mountain` — high ground, very slow / impassable
  """
  use GenServer

  @default_size {100, 100}
  # Terrain types: :grass, :water, :forest, :mountain
  # Biome types: :plains, :forest_village, :coastal, :mountain_pass
  # Biome types: plains, forest_village, coastal, mountain_pass

  defstruct [
    :id,
    :name,
    :grid_size,
    :grid_table,
    :current_tick,
    :status,
    :config,
    :created_at
  ]

  @type terrain :: :grass | :water | :forest | :mountain
  @type cell :: %{terrain: terrain, occupants: list(), resources: map()}
  @type coord :: {non_neg_integer(), non_neg_integer()}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          grid_size: {integer(), integer()},
          grid_table: :ets.tid() | nil,
          current_tick: integer(),
          status: :initializing | :running | :paused | :stopped,
          config: map(),
          created_at: DateTime.t()
        }

  # ── Public API ──────────────────────────────────────────────

  @doc "Create a new world struct with configurable grid (default 100x100)."
  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    size = Keyword.get(opts, :grid_size, @default_size)

    %__MODULE__{
      id: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower),
      name: name,
      grid_size: size,
      grid_table: nil,
      current_tick: 0,
      status: :initializing,
      config: %{
        template: Keyword.get(opts, :template, :village),
        resource_abundance: Keyword.get(opts, :resource_abundance, :medium),
        danger_level: Keyword.get(opts, :danger_level, :normal),
        seed: Keyword.get(opts, :seed, :rand.uniform(1_000_000))
      },
      created_at: DateTime.utc_now()
    }
  end

  @doc "Get the cell data at {x, y}."
  @spec get_cell(pid() | atom(), coord()) :: {:ok, cell()} | {:error, :out_of_bounds}
  def get_cell(server \\ __MODULE__, {x, y}) do
    GenServer.call(server, {:get_cell, {x, y}})
  end

  @doc "Set (merge) cell data at {x, y}."
  @spec set_cell(pid() | atom(), coord(), map()) :: :ok | {:error, :out_of_bounds}
  def set_cell(server \\ __MODULE__, {x, y}, data) do
    GenServer.call(server, {:set_cell, {x, y}, data})
  end

  @doc "Return the 4-directional (Von Neumann) neighbors of a cell."
  @spec neighbors(pid() | atom(), coord()) :: [coord()]
  def neighbors(server \\ __MODULE__, {x, y}) do
    GenServer.call(server, {:neighbors, {x, y}})
  end

  @doc "Get world status."
  @spec status(pid() | atom()) :: map()
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @doc "Get the full world state."
  @spec get_state(pid() | atom()) :: t()
  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  # ── GenServer ───────────────────────────────────────────────

  def start_link(world) do
    GenServer.start_link(__MODULE__, world, name: __MODULE__)
  end

  @impl true
  def init(world) do
    table = :ets.new(:modus_grid, [:set, :public, read_concurrency: true])
    world = %{world | grid_table: table, status: :paused}
    generate_terrain(world)
    {:ok, world}
  end

  @impl true
  def handle_call(:get_state, _from, world) do
    {:reply, world, world}
  end

  @impl true
  def handle_call(:status, _from, world) do
    {:reply,
     %{
       name: world.name,
       tick: world.current_tick,
       status: world.status,
       grid_size: world.grid_size
     }, world}
  end

  @impl true
  def handle_call({:get_cell, {x, y}}, _from, world) do
    {max_x, max_y} = world.grid_size

    if x >= 0 and x < max_x and y >= 0 and y < max_y do
      case :ets.lookup(world.grid_table, {x, y}) do
        [{{^x, ^y}, cell}] -> {:reply, {:ok, cell}, world}
        [] -> {:reply, {:error, :out_of_bounds}, world}
      end
    else
      {:reply, {:error, :out_of_bounds}, world}
    end
  end

  @impl true
  def handle_call({:set_cell, {x, y}, data}, _from, world) do
    {max_x, max_y} = world.grid_size

    if x >= 0 and x < max_x and y >= 0 and y < max_y do
      case :ets.lookup(world.grid_table, {x, y}) do
        [{{^x, ^y}, cell}] ->
          :ets.insert(world.grid_table, {{x, y}, Map.merge(cell, data)})
          {:reply, :ok, world}

        [] ->
          {:reply, {:error, :out_of_bounds}, world}
      end
    else
      {:reply, {:error, :out_of_bounds}, world}
    end
  end

  @impl true
  def handle_call({:neighbors, {x, y}}, _from, world) do
    {max_x, max_y} = world.grid_size

    coords =
      [{x - 1, y}, {x + 1, y}, {x, y - 1}, {x, y + 1}]
      |> Enum.filter(fn {nx, ny} -> nx >= 0 and nx < max_x and ny >= 0 and ny < max_y end)

    {:reply, coords, world}
  end

  @impl true
  def handle_cast(:tick, world) do
    world = %{world | current_tick: world.current_tick + 1}
    {:noreply, world}
  end

  @doc "Spawn initial agents at random walkable positions."
  @spec spawn_initial_agents(pid() | atom(), pos_integer()) :: [{:ok, pid()}]
  def spawn_initial_agents(server \\ __MODULE__, count) when count >= 1 do
    state = get_state(server)
    {max_x, max_y} = state.grid_size

    names = [
      "Alex", "Maya", "River", "Sage", "Finn", "Luna", "Kai",
      "Nova", "Zoe", "Atlas", "Iris", "Leo", "Mira", "Jude",
      "Aria", "Rowan", "Niko", "Ivy", "Theo", "Lila", "Orion",
      "Jade", "Ravi", "Suki", "Omar", "Nyla", "Ezra", "Cleo",
      "Amir", "Willow", "Bodhi", "Vera", "Kira", "Dara", "Ren",
      "Yara", "Soren", "Mika", "Inara", "Leila", "Zephyr", "Priya",
      "Hugo", "Amara", "Idris", "Noor", "Koda", "Lumi", "Astrid", "Nico"
    ]

    occupations = [:farmer, :builder, :explorer, :healer, :trader]

    1..count
    |> Enum.map(fn i ->
      pos = find_walkable_position(state.grid_table, max_x, max_y)
      name = Enum.at(names, rem(i - 1, length(names)))
      occ = Enum.random(occupations)
      agent = Modus.Simulation.Agent.new(name, pos, occ)
      Modus.Simulation.AgentSupervisor.spawn_agent(agent)
    end)
  end

  defp find_walkable_position(table, max_x, max_y) do
    x = :rand.uniform(max_x) - 1
    y = :rand.uniform(max_y) - 1

    case :ets.lookup(table, {x, y}) do
      [{{^x, ^y}, %{terrain: terrain}}] when terrain in [:grass, :forest] ->
        {x, y}

      _ ->
        find_walkable_position(table, max_x, max_y)
    end
  end

  # ── Biome System ─────────────────────────────────────────────

  @doc "Determine the biome at a given coordinate based on noise."
  @spec biome_at(integer(), integer(), integer()) :: atom()
  def biome_at(x, y, seed) do
    # Use a different seed offset for biome noise (large scale)
    bn = noise_at(x, y, seed + 7777, 32)
    mn = noise_at(x, y, seed + 3333, 24)

    cond do
      bn < 0.25 -> :coastal
      bn < 0.50 -> :plains
      bn < 0.75 -> :forest_village
      true -> :mountain_pass
    end
    |> maybe_override_biome(mn)
  end

  defp maybe_override_biome(biome, moisture) do
    # High moisture near coastal → stay coastal, low moisture in forest → mountain_pass
    cond do
      biome == :forest_village and moisture < 0.2 -> :mountain_pass
      biome == :plains and moisture > 0.85 -> :coastal
      true -> biome
    end
  end

  # ── Village & Structure Generation ─────────────────────────

  @doc "Generate village center positions deterministically from seed."
  @spec generate_villages(integer(), integer(), integer()) :: [{integer(), integer()}]
  def generate_villages(max_x, max_y, seed) do
    # Generate 3-6 village centers spread across the map
    num_villages = 3 + rem(hash_int(seed, 42), 4)
    margin = div(min(max_x, max_y), 8)

    for i <- 0..(num_villages - 1) do
      vx = margin + rem(hash_int(seed, i * 100 + 1), max(max_x - 2 * margin, 1))
      vy = margin + rem(hash_int(seed, i * 100 + 2), max(max_y - 2 * margin, 1))
      {vx, vy}
    end
  end

  defp hash_int(a, b) do
    :erlang.phash2({a, b}, 1_000_000)
  end

  @doc "Check if coordinate is near a village center (within radius)."
  def near_village?(x, y, villages, radius \\ 6) do
    Enum.any?(villages, fn {vx, vy} ->
      dx = x - vx
      dy = y - vy
      dx * dx + dy * dy <= radius * radius
    end)
  end

  @doc "Check if coordinate is on a road between villages."
  def on_road?(x, y, villages) do
    # Simple: for each pair of adjacent villages, check Manhattan proximity to line
    villages
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [{x1, y1}, {x2, y2}] ->
      point_near_line?(x, y, x1, y1, x2, y2, 1)
    end)
  end

  defp point_near_line?(px, py, x1, y1, x2, y2, tolerance) do
    # Check if point is within tolerance of the line segment (using cross product approximation)
    dx = x2 - x1
    dy = y2 - y1
    len_sq = dx * dx + dy * dy
    if len_sq == 0 do
      abs(px - x1) + abs(py - y1) <= tolerance
    else
      t = max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / len_sq))
      proj_x = ensure_float(x1) + t * ensure_float(dx)
      proj_y = ensure_float(y1) + t * ensure_float(dy)
      dist = abs(ensure_float(px) - proj_x) + abs(ensure_float(py) - proj_y)
      dist <= ensure_float(tolerance) + 1.0
    end
  end

  @doc "Check if coordinate is part of a river."
  def on_river?(x, y, seed, max_x, max_y) do
    # Generate 1-2 rivers as sine-wave paths
    river1_start_y = rem(hash_int(seed, 500), max(max_y, 1))
    river_x = ensure_float(x)
    river_expected_y = ensure_float(river1_start_y) + :math.sin(river_x / 8.0) * 6.0
    abs(ensure_float(y) - river_expected_y) < 1.5 and x > 5 and x < max_x - 5
  end

  # ── Terrain Generation ──────────────────────────────────────

  @doc false
  @spec generate_terrain(t()) :: :ok
  defp generate_terrain(world) do
    {max_x, max_y} = world.grid_size
    seed = world.config.seed
    villages = generate_villages(max_x, max_y, seed)

    for x <- 0..(max_x - 1), y <- 0..(max_y - 1) do
      terrain = procedural_terrain(x, y, seed, max_x, max_y, villages)

      cell = %{
        terrain: terrain,
        occupants: [],
        resources: default_resources(terrain)
      }

      :ets.insert(world.grid_table, {{x, y}, cell})
    end

    :ok
  end

  @spec procedural_terrain(integer(), integer(), integer(), integer(), integer(), list()) :: terrain()
  defp procedural_terrain(x, y, seed, max_x, max_y, villages) do
    # Check structures first (roads, villages, rivers)
    cond do
      on_river?(x, y, seed, max_x, max_y) -> :water
      on_road?(x, y, villages) -> :grass
      near_village?(x, y, villages) -> :grass
      true -> biome_terrain(x, y, seed)
    end
  end

  defp biome_terrain(x, y, seed) do
    biome = biome_at(x, y, seed)
    n = value_noise(x, y, seed)

    case biome do
      :plains ->
        cond do
          n < 0.15 -> :water
          n < 0.70 -> :grass
          n < 0.85 -> :forest
          true -> :mountain
        end

      :forest_village ->
        cond do
          n < 0.10 -> :water
          n < 0.35 -> :grass
          n < 0.85 -> :forest
          true -> :mountain
        end

      :coastal ->
        cond do
          n < 0.40 -> :water
          n < 0.70 -> :grass
          n < 0.85 -> :forest
          true -> :mountain
        end

      :mountain_pass ->
        cond do
          n < 0.10 -> :water
          n < 0.30 -> :grass
          n < 0.50 -> :forest
          true -> :mountain
        end
    end
  end

  # Simple value noise — hash-based, deterministic, no external deps
  @spec value_noise(integer(), integer(), integer()) :: float()
  defp value_noise(x, y, seed) do
    # Two octaves for variety
    n1 = noise_at(x, y, seed, 8)
    n2 = noise_at(x, y, seed, 16)
    # Weighted blend
    (n1 * 0.65 + n2 * 0.35)
  end

  defp noise_at(x, y, seed, scale) do
    # Grid coordinates
    gx = div(x, scale)
    gy = div(y, scale)
    fx = ensure_float(rem(x, scale)) / ensure_float(scale)
    fy = ensure_float(rem(y, scale)) / ensure_float(scale)

    # Four corner values
    v00 = hash(gx, gy, seed)
    v10 = hash(gx + 1, gy, seed)
    v01 = hash(gx, gy + 1, seed)
    v11 = hash(gx + 1, gy + 1, seed)

    # Bilinear interpolation with smoothstep
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)

    top = v00 + (v10 - v00) * sx
    bot = v01 + (v11 - v01) * sx
    top + (bot - top) * sy
  end

  defp hash(x, y, seed) do
    h = :erlang.phash2({x, y, seed}, 1_000_000)
    ensure_float(h) / 1_000_000.0
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0

  defp default_resources(:grass), do: %{food: 3}
  defp default_resources(:forest), do: %{food: 5, wood: 8}
  defp default_resources(:water), do: %{fish: 6}
  defp default_resources(:mountain), do: %{stone: 10, ore: 4}
end
