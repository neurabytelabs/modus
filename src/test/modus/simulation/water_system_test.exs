defmodule Modus.Simulation.WaterSystemTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.{WaterSystem, TerrainGenerator}

  @width 50
  @height 50
  @seed 12345

  setup do
    # Clean up ETS tables between tests
    for table <- [:modus_terrain, :modus_water] do
      case :ets.whereis(table) do
        :undefined -> :ok
        _tid -> :ets.delete(table)
      end
    end

    # Generate terrain first (water depends on it)
    TerrainGenerator.generate(@width, @height, @seed, :continent)
    :ok
  end

  describe "generate/3" do
    test "creates water features without crashing" do
      assert :ok = WaterSystem.generate(@width, @height, @seed)
    end

    test "generates at least some water cells" do
      WaterSystem.generate(@width, @height, @seed)
      stats = WaterSystem.stats()
      assert stats.total > 0
    end

    test "generates rivers" do
      WaterSystem.generate(@width, @height, @seed)
      stats = WaterSystem.stats()
      assert stats.rivers > 0
    end

    test "generates fishing spots" do
      WaterSystem.generate(@width, @height, @seed)
      stats = WaterSystem.stats()
      assert stats.fishing_spots > 0
    end
  end

  describe "get/2" do
    test "returns nil for non-water position" do
      WaterSystem.generate(@width, @height, @seed)
      # Find a non-water cell
      result =
        Enum.find_value(0..(@width - 1), fn x ->
          Enum.find_value(0..(@height - 1), fn y ->
            if WaterSystem.get(x, y) == nil, do: {x, y}
          end)
        end)

      assert result != nil
      {x, y} = result
      assert WaterSystem.get(x, y) == nil
    end

    test "returns water cell data for water position" do
      WaterSystem.generate(@width, @height, @seed)
      cells = WaterSystem.all_water()
      assert length(cells) > 0

      {{x, y}, _} = hd(cells)
      cell = WaterSystem.get(x, y)
      assert cell != nil
      assert cell.type in [:river, :lake]
      assert is_float(cell.depth)
      assert is_float(cell.pollution)
      assert is_boolean(cell.fishing_spot)
    end

    test "returns nil for out-of-bounds" do
      WaterSystem.generate(@width, @height, @seed)
      assert WaterSystem.get(-1, -1) == nil
      assert WaterSystem.get(9999, 9999) == nil
    end
  end

  describe "water?/2" do
    test "returns true for water cells" do
      WaterSystem.generate(@width, @height, @seed)
      {{x, y}, _} = hd(WaterSystem.all_water())
      assert WaterSystem.water?(x, y) == true
    end

    test "returns false for non-water cells" do
      WaterSystem.generate(@width, @height, @seed)
      assert WaterSystem.water?(9999, 9999) == false
    end
  end

  describe "river?/2 and lake?/2" do
    test "correctly identifies river cells" do
      WaterSystem.generate(@width, @height, @seed)
      river_cell = Enum.find(WaterSystem.all_water(), fn {_, c} -> c.type == :river end)

      if river_cell do
        {{x, y}, _} = river_cell
        assert WaterSystem.river?(x, y) == true
        assert WaterSystem.lake?(x, y) == false
      end
    end

    test "correctly identifies lake cells" do
      WaterSystem.generate(@width, @height, @seed)
      lake_cell = Enum.find(WaterSystem.all_water(), fn {_, c} -> c.type == :lake end)

      if lake_cell do
        {{x, y}, _} = lake_cell
        assert WaterSystem.lake?(x, y) == true
        assert WaterSystem.river?(x, y) == false
      end
    end
  end

  describe "blocks_movement?/2" do
    test "deep rivers block movement" do
      WaterSystem.generate(@width, @height, @seed)

      deep_river =
        Enum.find(WaterSystem.all_water(), fn {_, c} ->
          c.type == :river and c.depth > 0.5
        end)

      if deep_river do
        {{x, y}, _} = deep_river
        assert WaterSystem.blocks_movement?(x, y) == true
      end
    end

    test "lakes block movement" do
      WaterSystem.generate(@width, @height, @seed)
      lake = Enum.find(WaterSystem.all_water(), fn {_, c} -> c.type == :lake end)

      if lake do
        {{x, y}, _} = lake
        assert WaterSystem.blocks_movement?(x, y) == true
      end
    end

    test "non-water does not block" do
      WaterSystem.generate(@width, @height, @seed)
      assert WaterSystem.blocks_movement?(9999, 9999) == false
    end
  end

  describe "ford?/2" do
    test "shallow rivers are fords" do
      WaterSystem.generate(@width, @height, @seed)

      shallow_river =
        Enum.find(WaterSystem.all_water(), fn {_, c} ->
          c.type == :river and c.depth <= 0.5
        end)

      if shallow_river do
        {{x, y}, _} = shallow_river
        assert WaterSystem.ford?(x, y) == true
      end
    end
  end

  describe "irrigation_bonus/2" do
    test "returns 1.5 near water" do
      WaterSystem.generate(@width, @height, @seed)
      {{wx, wy}, _} = hd(WaterSystem.all_water())

      # Check adjacent tile
      bonus = WaterSystem.irrigation_bonus(wx + 1, wy)
      assert bonus == 1.5
    end

    test "returns 1.0 far from water" do
      WaterSystem.generate(@width, @height, @seed)
      # Very unlikely to have water at extreme coords
      assert WaterSystem.irrigation_bonus(9999, 9999) == 1.0
    end
  end

  describe "pollution" do
    test "add_pollution increases pollution level" do
      WaterSystem.generate(@width, @height, @seed)
      {{x, y}, _} = hd(WaterSystem.all_water())

      assert WaterSystem.get(x, y).pollution == 0.0
      WaterSystem.add_pollution(x, y, 0.3)
      assert WaterSystem.get(x, y).pollution == 0.3
    end

    test "pollution caps at 1.0" do
      WaterSystem.generate(@width, @height, @seed)
      {{x, y}, _} = hd(WaterSystem.all_water())

      WaterSystem.add_pollution(x, y, 0.8)
      WaterSystem.add_pollution(x, y, 0.5)
      assert WaterSystem.get(x, y).pollution == 1.0
    end

    test "add_pollution on non-water is noop" do
      WaterSystem.generate(@width, @height, @seed)
      assert :ok = WaterSystem.add_pollution(9999, 9999, 0.5)
    end
  end

  describe "seasonal effects" do
    test "spring floods increase river depth" do
      WaterSystem.generate(@width, @height, @seed)

      river_cell = Enum.find(WaterSystem.all_water(), fn {_, c} -> c.type == :river end)

      if river_cell do
        {{x, y}, cell} = river_cell
        old_depth = cell.depth
        WaterSystem.apply_season(:spring)
        new_cell = WaterSystem.get(x, y)
        assert new_cell.depth >= old_depth
      end
    end

    test "summer drought decreases depth" do
      WaterSystem.generate(@width, @height, @seed)

      {{x, y}, cell} = hd(WaterSystem.all_water())
      old_depth = cell.depth
      WaterSystem.apply_season(:summer)
      new_cell = WaterSystem.get(x, y)
      assert new_cell.depth <= old_depth
    end

    test "autumn and winter are noops" do
      WaterSystem.generate(@width, @height, @seed)
      assert :ok = WaterSystem.apply_season(:autumn)
      assert :ok = WaterSystem.apply_season(:winter)
    end
  end

  describe "stats/0" do
    test "returns correct structure" do
      WaterSystem.generate(@width, @height, @seed)
      stats = WaterSystem.stats()
      assert Map.has_key?(stats, :rivers)
      assert Map.has_key?(stats, :lakes)
      assert Map.has_key?(stats, :fishing_spots)
      assert Map.has_key?(stats, :total)
      assert stats.total == stats.rivers + stats.lakes
    end
  end

  describe "fishing_spots/0" do
    test "returns list of positions" do
      WaterSystem.generate(@width, @height, @seed)
      spots = WaterSystem.fishing_spots()
      assert is_list(spots)

      Enum.each(spots, fn {x, y} ->
        assert WaterSystem.fishing_spot?(x, y)
      end)
    end
  end
end
