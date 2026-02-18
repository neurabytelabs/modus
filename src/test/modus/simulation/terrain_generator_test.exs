defmodule Modus.Simulation.TerrainGeneratorTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.TerrainGenerator

  @seed 42
  @width 50
  @height 50

  setup do
    # Clean up terrain table if exists
    try do
      :ets.delete(:modus_terrain)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  describe "generate/4" do
    test "creates terrain ETS table with correct dimensions" do
      TerrainGenerator.generate(@width, @height, @seed)
      count = :ets.info(:modus_terrain, :size)
      assert count == @width * @height
    end

    test "every cell has biome, elevation, temperature, moisture" do
      TerrainGenerator.generate(@width, @height, @seed)

      for x <- 0..4, y <- 0..4 do
        data = TerrainGenerator.get(x, y)
        assert data != nil
        assert is_atom(data.biome)
        assert is_float(data.elevation)
        assert is_float(data.temperature)
        assert is_float(data.moisture)
        assert data.elevation >= 0.0 and data.elevation <= 1.0
        assert data.temperature >= 0.0 and data.temperature <= 1.0
        assert data.moisture >= 0.0 and data.moisture <= 1.0
      end
    end

    test "deterministic — same seed gives same terrain" do
      TerrainGenerator.generate(@width, @height, @seed)
      data1 = for x <- 0..9, y <- 0..9, do: TerrainGenerator.biome_at(x, y)

      TerrainGenerator.generate(@width, @height, @seed)
      data2 = for x <- 0..9, y <- 0..9, do: TerrainGenerator.biome_at(x, y)

      assert data1 == data2
    end

    test "different seeds produce different terrain" do
      TerrainGenerator.generate(@width, @height, @seed)
      data1 = for x <- 0..9, y <- 0..9, do: TerrainGenerator.biome_at(x, y)

      TerrainGenerator.generate(@width, @height, @seed + 999)
      data2 = for x <- 0..9, y <- 0..9, do: TerrainGenerator.biome_at(x, y)

      # Not all cells should be the same
      assert data1 != data2
    end
  end

  describe "presets" do
    test "island preset has ocean around edges" do
      TerrainGenerator.generate(@width, @height, @seed, :island)

      edge_biomes =
        for x <- [0, @width - 1], y <- 0..(@height - 1) do
          TerrainGenerator.biome_at(x, y)
        end

      ocean_count = Enum.count(edge_biomes, &(&1 == :ocean))
      # Most edges should be ocean for island preset
      assert ocean_count > length(edge_biomes) * 0.5
    end

    test "pangaea preset has mostly land" do
      TerrainGenerator.generate(@width, @height, @seed, :pangaea)

      all_biomes =
        for x <- 0..(@width - 1), y <- 0..(@height - 1) do
          TerrainGenerator.biome_at(x, y)
        end

      ocean_pct = Enum.count(all_biomes, &(&1 == :ocean)) / length(all_biomes)
      # Pangaea should have very little ocean
      assert ocean_pct < 0.25
    end

    test "all presets generate valid terrain" do
      for preset <- TerrainGenerator.presets() do
        TerrainGenerator.generate(@width, @height, @seed, preset)
        assert :ets.info(:modus_terrain, :size) == @width * @height
      end
    end
  end

  describe "biome_at/2" do
    test "returns nil for out-of-bounds" do
      TerrainGenerator.generate(10, 10, @seed)
      assert TerrainGenerator.biome_at(100, 100) == nil
    end

    test "returns valid biome atom" do
      TerrainGenerator.generate(@width, @height, @seed)
      biome = TerrainGenerator.biome_at(25, 25)
      assert biome in TerrainGenerator.biomes()
    end
  end

  describe "assign_biome/3" do
    test "low elevation → ocean" do
      assert TerrainGenerator.assign_biome(0.1, 0.5, 0.5) == :ocean
    end

    test "high elevation → mountain" do
      assert TerrainGenerator.assign_biome(0.9, 0.5, 0.5) == :mountain
    end

    test "cold → tundra" do
      assert TerrainGenerator.assign_biome(0.5, 0.1, 0.3) == :tundra
    end

    test "hot and dry → desert" do
      assert TerrainGenerator.assign_biome(0.5, 0.8, 0.2) == :desert
    end

    test "wet and low → swamp" do
      assert TerrainGenerator.assign_biome(0.35, 0.5, 0.8) == :swamp
    end

    test "moderate moisture → forest" do
      assert TerrainGenerator.assign_biome(0.5, 0.5, 0.6) == :forest
    end

    test "default → plains" do
      assert TerrainGenerator.assign_biome(0.5, 0.5, 0.3) == :plains
    end
  end

  describe "movement_cost/1" do
    test "ocean is impassable" do
      assert TerrainGenerator.movement_cost(:ocean) == :impassable
    end

    test "plains is baseline" do
      assert TerrainGenerator.movement_cost(:plains) == 1.0
    end

    test "mountain is most expensive land" do
      assert TerrainGenerator.movement_cost(:mountain) > TerrainGenerator.movement_cost(:forest)
    end

    test "all biomes have defined cost" do
      for biome <- TerrainGenerator.biomes() do
        cost = TerrainGenerator.movement_cost(biome)
        assert cost == :impassable or is_number(cost)
      end
    end
  end

  describe "walkable?/2" do
    test "ocean not walkable" do
      TerrainGenerator.generate(@width, @height, @seed)
      # Find an ocean tile
      ocean_pos =
        Enum.find(for(x <- 0..(@width - 1), y <- 0..(@height - 1), do: {x, y}), fn {x, y} ->
          TerrainGenerator.biome_at(x, y) == :ocean
        end)

      if ocean_pos do
        {x, y} = ocean_pos
        refute TerrainGenerator.walkable?(x, y)
      end
    end

    test "plains is walkable" do
      TerrainGenerator.generate(@width, @height, @seed)

      plains_pos =
        Enum.find(for(x <- 0..(@width - 1), y <- 0..(@height - 1), do: {x, y}), fn {x, y} ->
          TerrainGenerator.biome_at(x, y) == :plains
        end)

      if plains_pos do
        {x, y} = plains_pos
        assert TerrainGenerator.walkable?(x, y)
      end
    end
  end

  describe "terrain_type/1" do
    test "maps biomes to terrain atoms" do
      assert TerrainGenerator.terrain_type(:ocean) == :water
      assert TerrainGenerator.terrain_type(:plains) == :grass
      assert TerrainGenerator.terrain_type(:forest) == :forest
      assert TerrainGenerator.terrain_type(:mountain) == :mountain
      assert TerrainGenerator.terrain_type(:desert) == :desert
    end
  end

  describe "perlin/4" do
    test "returns values in [0, 1]" do
      for x <- 0..20, y <- 0..20 do
        val = TerrainGenerator.perlin(x, y, @seed, 16)
        assert val >= 0.0 and val <= 1.0
      end
    end

    test "continuous — adjacent cells similar" do
      v1 = TerrainGenerator.perlin(10, 10, @seed, 32)
      v2 = TerrainGenerator.perlin(11, 10, @seed, 32)
      assert abs(v1 - v2) < 0.3
    end
  end
end
