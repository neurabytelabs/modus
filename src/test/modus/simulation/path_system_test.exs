defmodule Modus.Simulation.PathSystemTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.PathSystem

  setup do
    # Clean ETS tables before each test
    for table <- [:modus_paths, :modus_bridges] do
      case :ets.whereis(table) do
        :undefined -> :ok
        _ -> :ets.delete_all_objects(table)
      end
    end

    PathSystem.init()
    :ok
  end

  describe "record_walk/3" do
    test "creates new path entry on first walk" do
      cell = PathSystem.record_walk(5, 5, 100)
      assert cell.walks == 1
      assert cell.tier == :none
      assert cell.last_walked == 100
    end

    test "increments walk counter" do
      PathSystem.record_walk(5, 5, 100)
      cell = PathSystem.record_walk(5, 5, 101)
      assert cell.walks == 2
    end

    test "upgrades to dirt_trail at 10 walks" do
      cell =
        Enum.reduce(1..10, nil, fn tick, _acc ->
          PathSystem.record_walk(5, 5, tick)
        end)

      assert cell.tier == :dirt_trail
    end

    test "upgrades to road at 50 walks" do
      cell =
        Enum.reduce(1..50, nil, fn tick, _acc ->
          PathSystem.record_walk(5, 5, tick)
        end)

      assert cell.tier == :road
    end

    test "upgrades to highway at 200 walks" do
      cell =
        Enum.reduce(1..200, nil, fn tick, _acc ->
          PathSystem.record_walk(5, 5, tick)
        end)

      assert cell.tier == :highway
    end
  end

  describe "get/2" do
    test "returns nil for unwalked tile" do
      assert PathSystem.get(99, 99) == nil
    end

    test "returns path data for walked tile" do
      PathSystem.record_walk(3, 4, 50)
      cell = PathSystem.get(3, 4)
      assert cell.walks == 1
    end
  end

  describe "tier_at/2" do
    test "returns :none for empty tile" do
      assert PathSystem.tier_at(0, 0) == :none
    end

    test "returns correct tier" do
      Enum.each(1..15, fn t -> PathSystem.record_walk(1, 1, t) end)
      assert PathSystem.tier_at(1, 1) == :dirt_trail
    end
  end

  describe "decay_paths/1" do
    test "decays idle paths" do
      # Walk 5 times at tick 0
      Enum.each(1..5, fn _ -> PathSystem.record_walk(2, 2, 0) end)
      assert PathSystem.get(2, 2).walks == 5

      # Decay at tick 500 (5 decay intervals)
      PathSystem.decay_paths(500)
      cell = PathSystem.get(2, 2)
      assert cell == nil || cell.walks == 0
    end

    test "does not decay recently walked paths" do
      Enum.each(1..20, fn t -> PathSystem.record_walk(3, 3, t) end)
      PathSystem.decay_paths(21)
      cell = PathSystem.get(3, 3)
      assert cell.walks == 20
    end
  end

  describe "bridges" do
    setup do
      # Setup water table for bridge tests
      case :ets.whereis(:modus_water) do
        :undefined -> :ets.new(:modus_water, [:set, :public, :named_table])
        _ -> :ok
      end

      :ets.insert(
        :modus_water,
        {{10, 10},
         %{type: :river, flow_dir: {1, 0}, depth: 0.5, pollution: 0.0, fishing_spot: false}}
      )

      :ok
    end

    test "build bridge on water tile" do
      assert {:ok, bridge} = PathSystem.build_bridge(10, 10, "agent-1", 100)
      assert bridge.built_by == "agent-1"
      assert bridge.health == 1.0
    end

    test "cannot build bridge on non-water tile" do
      assert {:error, :not_water} = PathSystem.build_bridge(50, 50, "agent-1", 100)
    end

    test "cannot build duplicate bridge" do
      PathSystem.build_bridge(10, 10, "agent-1", 100)
      assert {:error, :already_exists} = PathSystem.build_bridge(10, 10, "agent-2", 200)
    end

    test "has_bridge? returns correct value" do
      refute PathSystem.has_bridge?(10, 10)
      PathSystem.build_bridge(10, 10, "agent-1", 100)
      assert PathSystem.has_bridge?(10, 10)
    end
  end

  describe "stats/0" do
    test "returns correct statistics" do
      # Create some paths of different tiers
      Enum.each(1..15, fn t -> PathSystem.record_walk(1, 1, t) end)
      Enum.each(1..55, fn t -> PathSystem.record_walk(2, 2, t) end)

      stats = PathSystem.stats()
      assert stats.total_paths == 2
      assert stats.trails == 1
      assert stats.roads == 1
      assert stats.total_walks == 70
    end
  end

  describe "visual helpers" do
    test "tier_color returns valid colors" do
      assert PathSystem.tier_color(:dirt_trail) == "#8B7355"
      assert PathSystem.tier_color(:road) == "#A0522D"
      assert PathSystem.tier_color(:highway) == "#696969"
      assert PathSystem.tier_color(:none) == "transparent"
    end

    test "tier_emoji returns correct symbols" do
      assert PathSystem.tier_emoji(:dirt_trail) == "·"
      assert PathSystem.tier_emoji(:road) == "═"
      assert PathSystem.tier_emoji(:highway) == "█"
    end
  end

  describe "get_all_paths/0 and get_all_bridges/0" do
    test "returns all recorded paths" do
      PathSystem.record_walk(1, 1, 1)
      PathSystem.record_walk(2, 2, 1)
      paths = PathSystem.get_all_paths()
      assert length(paths) == 2
    end

    test "returns empty list when no paths" do
      assert PathSystem.get_all_paths() == []
    end
  end
end
