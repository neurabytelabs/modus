defmodule Modus.Simulation.Wildlife do
  @moduledoc """
  Wildlife — Ecology simulation with breeding, food chains, migration, and ecosystem balance.

  Manages animal populations with predator-prey dynamics, seasonal migration,
  and population caps. Integrates with Seasons for migration patterns.

  ## Animal Types
  - `:deer`   — herbivore, prey for wolves, max population 20
  - `:wolf`   — predator, hunts deer, max population 8
  - `:rabbit` — herbivore, fast breeder, max population 30
  - `:bear`   — omnivore, solitary, max population 5
  - `:fish`   — aquatic, in fishing spots, max population 50

  ## Spinoza: *Conatus* — every creature strives to persist in its being.
  """
  use GenServer

  alias Modus.Simulation.EventLog

  @pubsub Modus.PubSub

  @population_caps %{
    deer: 20,
    wolf: 8,
    rabbit: 30,
    bear: 5,
    fish: 50
  }

  @breed_rates %{
    deer: 0.03,
    wolf: 0.02,
    rabbit: 0.06,
    bear: 0.01,
    fish: 0.04
  }

  @hunt_rates %{
    wolf: %{deer: 0.05, rabbit: 0.08},
    bear: %{deer: 0.02, rabbit: 0.04, fish: 0.03}
  }

  @migration_patterns %{
    spring: %{deer: {0, -1}, wolf: {1, 0}, rabbit: {0, 0}, bear: {-1, -1}},
    summer: %{deer: {1, 0}, wolf: {0, 1}, rabbit: {1, 1}, bear: {0, -1}},
    autumn: %{deer: {0, 1}, wolf: {-1, 0}, rabbit: {-1, -1}, bear: {1, 1}},
    winter: %{deer: {-1, 0}, wolf: {0, -1}, rabbit: {0, 0}, bear: {0, 0}}
  }

  defstruct animals: %{},
            fishing_spots: [],
            plant_regrowth: [],
            ecosystem_health: 1.0,
            overhunt_counter: %{},
            tick_count: 0

  # ── Public API ──────────────────────────────────────────

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @spec get_state() :: map()
  def get_state, do: GenServer.call(__MODULE__, :get_state)

  @spec get_animals() :: map()
  def get_animals, do: GenServer.call(__MODULE__, :get_animals)

  @spec get_population(atom()) :: non_neg_integer()
  def get_population(species), do: GenServer.call(__MODULE__, {:get_population, species})

  @spec hunt(atom()) :: {:ok, non_neg_integer()} | {:error, :extinct}
  def hunt(species), do: GenServer.call(__MODULE__, {:hunt, species})

  @spec get_fishing_spots() :: [map()]
  def get_fishing_spots, do: GenServer.call(__MODULE__, :get_fishing_spots)

  @spec fish({integer(), integer()}) :: {:ok, integer()} | {:error, :no_spot | :depleted}
  def fish(position), do: GenServer.call(__MODULE__, {:fish, position})

  @spec add_plant_regrowth({integer(), integer()}, non_neg_integer()) :: :ok
  def add_plant_regrowth(position, tick), do: GenServer.cast(__MODULE__, {:add_regrowth, position, tick})

  @spec tick(non_neg_integer(), atom()) :: :ok
  def tick(tick_number, season \\ :spring), do: GenServer.cast(__MODULE__, {:tick, tick_number, season})

  @spec ecosystem_health() :: float()
  def ecosystem_health, do: GenServer.call(__MODULE__, :ecosystem_health)

  @spec serialize() :: map()
  def serialize, do: GenServer.call(__MODULE__, :serialize)

  @doc "Population caps config."
  def population_caps, do: @population_caps

  # ── Pure Functions (testable without GenServer) ─────────

  @doc "Breed animals, respecting population caps."
  @spec breed(map()) :: map()
  def breed(animals) do
    Enum.reduce(animals, animals, fn {species, count}, acc ->
      cap = Map.get(@population_caps, species, 10)
      rate = Map.get(@breed_rates, species, 0.02)
      new_births = floor(ensure_float(count) * rate)
      new_count = min(count + new_births, cap)
      Map.put(acc, species, new_count)
    end)
  end

  @doc "Apply food chain: predators hunt prey."
  @spec apply_food_chain(map()) :: map()
  def apply_food_chain(animals) do
    Enum.reduce(@hunt_rates, animals, fn {predator, prey_map}, acc ->
      pred_count = Map.get(acc, predator, 0)
      if pred_count > 0 do
        Enum.reduce(prey_map, acc, fn {prey, rate}, acc2 ->
          prey_count = Map.get(acc2, prey, 0)
          kills = floor(ensure_float(pred_count) * rate * ensure_float(prey_count) / max(ensure_float(prey_count), 1.0))
          kills = min(kills, prey_count)
          Map.put(acc2, prey, prey_count - kills)
        end)
      else
        acc
      end
    end)
  end

  @doc "Predator starvation: if prey is scarce, predators decline."
  @spec apply_predator_starvation(map()) :: map()
  def apply_predator_starvation(animals) do
    prey_total = Map.get(animals, :deer, 0) + Map.get(animals, :rabbit, 0)
    wolf_count = Map.get(animals, :wolf, 0)

    animals =
      if prey_total < 3 and wolf_count > 0 do
        Map.put(animals, :wolf, max(wolf_count - 1, 0))
      else
        animals
      end

    bear_count = Map.get(animals, :bear, 0)
    if prey_total < 2 and bear_count > 0 do
      Map.put(animals, :bear, max(bear_count - 1, 0))
    else
      animals
    end
  end

  @doc "Apply seasonal migration offsets to animal positions (conceptual population shift)."
  @spec apply_migration(map(), atom()) :: map()
  def apply_migration(animals, season) do
    patterns = Map.get(@migration_patterns, season, %{})
    # Migration affects population visibility — animals that migrate out reduce count temporarily
    Enum.reduce(patterns, animals, fn {species, {dx, dy}}, acc ->
      if dx == 0 and dy == 0 do
        acc
      else
        count = Map.get(acc, species, 0)
        # Small population fluctuation from migration
        migration_effect = if abs(dx) + abs(dy) > 1, do: -1, else: 0
        Map.put(acc, species, max(count + migration_effect, 0))
      end
    end)
  end

  @doc "Calculate ecosystem health based on population balance."
  @spec calculate_ecosystem_health(map()) :: float()
  def calculate_ecosystem_health(animals) do
    total_species = map_size(@population_caps)
    alive_species = Enum.count(animals, fn {species, count} ->
      Map.has_key?(@population_caps, species) and count > 0
    end)

    diversity = ensure_float(alive_species) / ensure_float(total_species)

    # Check predator-prey balance
    prey = Map.get(animals, :deer, 0) + Map.get(animals, :rabbit, 0)
    predators = Map.get(animals, :wolf, 0) + Map.get(animals, :bear, 0)

    balance = if prey + predators == 0 do
      0.5
    else
      ratio = ensure_float(predators) / ensure_float(prey + predators)
      # Ideal ratio is ~0.2-0.3 predators
      1.0 - abs(ratio - 0.25) * 2.0
    end
    |> max(0.0)
    |> min(1.0)

    Float.round((diversity * 0.5 + balance * 0.5), 2)
  end

  # ── GenServer ───────────────────────────────────────────

  @impl true
  def init(state) do
    initial_animals = %{
      deer: 12,
      wolf: 4,
      rabbit: 15,
      bear: 2,
      fish: 30
    }

    fishing_spots = [
      %{position: {10, 10}, stock: 20, max_stock: 20, regen_rate: 0.5},
      %{position: {30, 45}, stock: 15, max_stock: 15, regen_rate: 0.4},
      %{position: {70, 20}, stock: 25, max_stock: 25, regen_rate: 0.6}
    ]

    {:ok, %{state |
      animals: initial_animals,
      fishing_spots: fishing_spots,
      ecosystem_health: calculate_ecosystem_health(initial_animals)
    }}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call(:get_animals, _from, state), do: {:reply, state.animals, state}

  def handle_call({:get_population, species}, _from, state) do
    {:reply, Map.get(state.animals, species, 0), state}
  end

  def handle_call({:hunt, species}, _from, state) do
    count = Map.get(state.animals, species, 0)
    if count > 0 do
      new_animals = Map.put(state.animals, species, count - 1)
      overhunt = Map.update(state.overhunt_counter, species, 1, &(&1 + 1))
      health = calculate_ecosystem_health(new_animals)
      {:reply, {:ok, count - 1}, %{state | animals: new_animals, overhunt_counter: overhunt, ecosystem_health: health}}
    else
      {:reply, {:error, :extinct}, state}
    end
  end

  def handle_call(:get_fishing_spots, _from, state) do
    {:reply, state.fishing_spots, state}
  end

  def handle_call({:fish, position}, _from, state) do
    case Enum.find_index(state.fishing_spots, &(&1.position == position)) do
      nil -> {:reply, {:error, :no_spot}, state}
      idx ->
        spot = Enum.at(state.fishing_spots, idx)
        if spot.stock > 0 do
          new_spot = %{spot | stock: spot.stock - 1}
          new_spots = List.replace_at(state.fishing_spots, idx, new_spot)
          {:reply, {:ok, new_spot.stock}, %{state | fishing_spots: new_spots}}
        else
          {:reply, {:error, :depleted}, state}
        end
    end
  end

  def handle_call(:ecosystem_health, _from, state) do
    {:reply, state.ecosystem_health, state}
  end

  def handle_call(:serialize, _from, state) do
    {:reply, %{
      animals: Enum.map(state.animals, fn {k, v} -> {Atom.to_string(k), v} end) |> Enum.into(%{}),
      fishing_spots: Enum.map(state.fishing_spots, fn s ->
        {x, y} = s.position
        %{x: x, y: y, stock: s.stock, max_stock: s.max_stock}
      end),
      ecosystem_health: state.ecosystem_health,
      plant_regrowth_count: length(state.plant_regrowth)
    }, state}
  end

  @impl true
  def handle_cast({:tick, tick_number, season}, state) do
    animals = state.animals

    # Every 50 ticks: breed
    animals = if rem(tick_number, 50) == 0, do: breed(animals), else: animals

    # Every 30 ticks: food chain
    animals = if rem(tick_number, 30) == 0, do: apply_food_chain(animals), else: animals

    # Every 100 ticks: predator starvation check
    animals = if rem(tick_number, 100) == 0, do: apply_predator_starvation(animals), else: animals

    # Every 250 ticks: seasonal migration
    animals = if rem(tick_number, 250) == 0, do: apply_migration(animals, season), else: animals

    # Regenerate fishing spots
    fishing_spots = Enum.map(state.fishing_spots, fn spot ->
      if spot.stock < spot.max_stock do
        new_stock = min(spot.stock + spot.regen_rate, spot.max_stock)
        %{spot | stock: ensure_float(new_stock) |> floor() |> max(spot.stock)}
      else
        spot
      end
    end)

    # Check plant regrowth (~200 tick timer)
    {regrown, still_growing} = Enum.split_with(state.plant_regrowth, fn {_pos, planted_tick} ->
      tick_number - planted_tick >= 200
    end)

    # Regrow trees
    for {pos, _tick} <- regrown do
      try do
        Modus.Simulation.World.paint_terrain(pos, :forest)
      catch
        _, _ -> :ok
      end
    end

    # Ecosystem health
    health = calculate_ecosystem_health(animals)

    # Overhunting cascade: if health drops below 0.3, reduce all populations
    animals = if health < 0.3 do
      Enum.map(animals, fn {species, count} ->
        {species, max(count - 1, 0)}
      end) |> Enum.into(%{})
    else
      animals
    end

    health = calculate_ecosystem_health(animals)

    # Log significant events
    if rem(tick_number, 500) == 0 do
      EventLog.log(:ecology_report, tick_number, [], %{
        animals: animals,
        ecosystem_health: health
      })
    end

    {:noreply, %{state |
      animals: animals,
      fishing_spots: fishing_spots,
      plant_regrowth: still_growing,
      ecosystem_health: health,
      tick_count: tick_number
    }}
  end

  def handle_cast({:add_regrowth, position, tick}, state) do
    {:noreply, %{state | plant_regrowth: [{position, tick} | state.plant_regrowth]}}
  end

  def handle_cast({:kill_animals_in_area, species_list, count}, state) do
    animals = Enum.reduce(species_list, state.animals, fn species, acc ->
      current = Map.get(acc, species, 0)
      Map.put(acc, species, max(current - count, 0))
    end)
    {:noreply, %{state | animals: animals, ecosystem_health: calculate_ecosystem_health(animals)}}
  end

  def handle_cast({:set_animals, animals}, state) do
    {:noreply, %{state | animals: animals, ecosystem_health: calculate_ecosystem_health(animals)}}
  end

  def handle_cast(:reset, _state) do
    {:ok, fresh} = init(%__MODULE__{})
    {:noreply, fresh}
  end

  # ── Helpers ─────────────────────────────────────────────

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0
end
