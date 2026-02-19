defmodule Modus.Simulation.WildlifeTest do
  use ExUnit.Case, async: true

  alias Modus.Simulation.Wildlife

  # ── Pure function tests (no GenServer needed) ───────────

  describe "breed/1" do
    test "increases population within caps" do
      animals = %{deer: 10, wolf: 4, rabbit: 20}
      result = Wildlife.breed(animals)
      assert result.deer >= 10
      assert result.wolf >= 4
      assert result.rabbit >= 20
    end

    test "respects population caps" do
      animals = %{deer: 20, wolf: 8, rabbit: 30}
      result = Wildlife.breed(animals)
      assert result.deer <= 20
      assert result.wolf <= 8
      assert result.rabbit <= 30
    end

    test "zero population stays zero" do
      animals = %{deer: 0, wolf: 0, rabbit: 0}
      result = Wildlife.breed(animals)
      assert result.deer == 0
      assert result.wolf == 0
      assert result.rabbit == 0
    end

    test "breeds rabbits faster than wolves" do
      animals = %{deer: 10, wolf: 4, rabbit: 10}
      result = Wildlife.breed(animals)
      rabbit_growth = result.rabbit - 10
      wolf_growth = result.wolf - 4
      # Rabbit breed rate (0.06) > wolf (0.02)
      assert rabbit_growth >= wolf_growth
    end
  end

  describe "apply_food_chain/1" do
    test "wolves reduce deer population" do
      animals = %{deer: 15, wolf: 6, rabbit: 20, bear: 2, fish: 10}
      result = Wildlife.apply_food_chain(animals)
      assert result.deer <= 15
    end

    test "no predators means no kills" do
      animals = %{deer: 15, wolf: 0, rabbit: 20, bear: 0, fish: 10}
      result = Wildlife.apply_food_chain(animals)
      assert result.deer == 15
      assert result.rabbit == 20
    end

    test "prey cannot go below zero" do
      animals = %{deer: 1, wolf: 8, rabbit: 1, bear: 5, fish: 10}
      result = Wildlife.apply_food_chain(animals)
      assert result.deer >= 0
      assert result.rabbit >= 0
    end

    test "bears hunt multiple prey types" do
      animals = %{deer: 10, wolf: 0, rabbit: 10, bear: 5, fish: 20}
      result = Wildlife.apply_food_chain(animals)
      # Bears hunt deer, rabbit, and fish
      assert result.deer <= 10 or result.rabbit <= 10 or result.fish <= 20
    end
  end

  describe "apply_predator_starvation/1" do
    test "wolves starve when prey is scarce" do
      animals = %{deer: 1, wolf: 4, rabbit: 1, bear: 0}
      result = Wildlife.apply_predator_starvation(animals)
      assert result.wolf < 4
    end

    test "wolves survive with sufficient prey" do
      animals = %{deer: 10, wolf: 4, rabbit: 10, bear: 0}
      result = Wildlife.apply_predator_starvation(animals)
      assert result.wolf == 4
    end

    test "bears starve when prey very low" do
      animals = %{deer: 0, wolf: 0, rabbit: 1, bear: 3}
      result = Wildlife.apply_predator_starvation(animals)
      assert result.bear < 3
    end

    test "predators cannot go below zero" do
      animals = %{deer: 0, wolf: 0, rabbit: 0, bear: 0}
      result = Wildlife.apply_predator_starvation(animals)
      assert result.wolf == 0
      assert result.bear == 0
    end
  end

  describe "apply_migration/2" do
    test "spring migration affects populations" do
      animals = %{deer: 10, wolf: 4, rabbit: 15, bear: 3}
      result = Wildlife.apply_migration(animals, :spring)
      # Bear has dx+dy > 1 in spring so loses 1
      assert result.bear == 2
    end

    test "summer migration pattern" do
      animals = %{deer: 10, wolf: 4, rabbit: 15, bear: 3}
      result = Wildlife.apply_migration(animals, :summer)
      # Rabbit has dx+dy > 1 in summer
      assert result.rabbit == 14
    end

    test "populations cannot go below zero from migration" do
      animals = %{deer: 0, wolf: 0, rabbit: 0, bear: 0}
      result = Wildlife.apply_migration(animals, :winter)
      assert Enum.all?(result, fn {_k, v} -> v >= 0 end)
    end
  end

  describe "calculate_ecosystem_health/1" do
    test "balanced ecosystem has high health" do
      animals = %{deer: 12, wolf: 4, rabbit: 15, bear: 2, fish: 30}
      health = Wildlife.calculate_ecosystem_health(animals)
      assert health > 0.5
      assert health <= 1.0
    end

    test "all extinct has low health" do
      animals = %{deer: 0, wolf: 0, rabbit: 0, bear: 0, fish: 0}
      health = Wildlife.calculate_ecosystem_health(animals)
      assert health <= 0.5
    end

    test "only predators = poor balance" do
      animals = %{deer: 0, wolf: 8, rabbit: 0, bear: 5, fish: 0}
      health = Wildlife.calculate_ecosystem_health(animals)
      assert health < 0.5
    end

    test "returns float between 0 and 1" do
      animals = %{deer: 5, wolf: 2, rabbit: 8, bear: 1, fish: 15}
      health = Wildlife.calculate_ecosystem_health(animals)
      assert is_float(health)
      assert health >= 0.0
      assert health <= 1.0
    end
  end

  describe "population_caps/0" do
    test "returns expected caps" do
      caps = Wildlife.population_caps()
      assert caps.deer == 20
      assert caps.wolf == 8
      assert caps.rabbit == 30
      assert caps.bear == 5
      assert caps.fish == 50
    end
  end

  # ── GenServer tests ─────────────────────────────────────

  describe "GenServer" do
    setup do
      case Process.whereis(Modus.PubSub) do
        nil -> Phoenix.PubSub.Supervisor.start_link(name: Modus.PubSub)
        _ -> :ok
      end

      case Process.whereis(Modus.Simulation.EventLog) do
        nil -> Modus.Simulation.EventLog.start_link([])
        _ -> :ok
      end

      case Process.whereis(Wildlife) do
        nil ->
          start_supervised!({Wildlife, []})

        _pid ->
          # Reset to initial state for test isolation
          GenServer.cast(Wildlife, :reset)
          :timer.sleep(10)
      end

      :ok
    end

    test "starts with initial populations" do
      animals = Wildlife.get_animals()
      assert animals.deer == 12
      assert animals.wolf == 4
      assert animals.rabbit == 15
    end

    test "hunt reduces population" do
      assert {:ok, remaining} = Wildlife.hunt(:deer)
      assert remaining == 11
      assert Wildlife.get_population(:deer) == 11
    end

    test "hunt returns error when extinct" do
      # Hunt all deer
      for _ <- 1..12, do: Wildlife.hunt(:deer)
      assert {:error, :extinct} = Wildlife.hunt(:deer)
    end

    test "fishing works" do
      spots = Wildlife.get_fishing_spots()
      assert length(spots) == 3

      first_spot = hd(spots)
      {:ok, stock} = Wildlife.fish(first_spot.position)
      assert stock == first_spot.stock - 1
    end

    test "fishing depleted spot returns error" do
      spots = Wildlife.get_fishing_spots()
      first_spot = hd(spots)

      # Fish until empty
      for _ <- 1..first_spot.stock do
        Wildlife.fish(first_spot.position)
      end

      assert {:error, :depleted} = Wildlife.fish(first_spot.position)
    end

    test "fishing invalid position returns error" do
      assert {:error, :no_spot} = Wildlife.fish({999, 999})
    end

    test "ecosystem health is calculated" do
      health = Wildlife.ecosystem_health()
      assert is_float(health)
      assert health > 0.0
    end

    test "tick processes without crash" do
      Wildlife.tick(50, :spring)
      Wildlife.tick(100, :summer)
      # Give GenServer time to process
      :timer.sleep(50)
      animals = Wildlife.get_animals()
      assert is_map(animals)
    end

    test "serialize returns valid data" do
      data = Wildlife.serialize()
      assert is_map(data.animals)
      assert is_list(data.fishing_spots)
      assert is_float(data.ecosystem_health)
      assert is_integer(data.plant_regrowth_count)
    end

    test "plant regrowth tracking" do
      Wildlife.add_plant_regrowth({5, 5}, 0)
      :timer.sleep(20)
      state = Wildlife.get_state()
      assert length(state.plant_regrowth) >= 1
    end
  end
end
