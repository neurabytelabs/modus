defmodule Modus.Simulation.WorldTest do
  use ExUnit.Case, async: false
  alias Modus.Simulation.World

  describe "new/2" do
    test "creates world with default grid size" do
      world = World.new("Test Universe")

      assert world.name == "Test Universe"
      assert world.grid_size == {100, 100}
      assert world.current_tick == 0
      assert world.status == :initializing
    end

    test "creates world with custom grid size" do
      world = World.new("Small", grid_size: {20, 20})
      assert world.grid_size == {20, 20}
    end

    test "stores config options" do
      world =
        World.new("Custom",
          template: :island,
          resource_abundance: :high,
          danger_level: :chaos
        )

      assert world.config.template == :island
      assert world.config.resource_abundance == :high
      assert world.config.danger_level == :chaos
    end

    test "generates unique ids" do
      w1 = World.new("A")
      w2 = World.new("B")
      assert w1.id != w2.id
    end

    test "default grid size is 100x100" do
      world = World.new("Big")
      assert world.grid_size == {100, 100}
    end
  end

  describe "GenServer with ETS grid" do
    setup do
      world = World.new("Grid Test", grid_size: {10, 10}, seed: 42)
      pid = start_supervised!({World, world})
      %{pid: pid}
    end

    test "initializes with :paused status", %{pid: pid} do
      state = World.get_state(pid)
      assert state.status == :paused
    end

    test "get_cell returns terrain data for valid coords", %{pid: pid} do
      {:ok, cell} = World.get_cell(pid, {0, 0})
      assert cell.terrain in [:grass, :water, :forest, :mountain]
      assert is_list(cell.occupants)
      assert is_map(cell.resources)
    end

    test "get_cell returns error for out-of-bounds", %{pid: pid} do
      assert {:error, :out_of_bounds} = World.get_cell(pid, {-1, 0})
      assert {:error, :out_of_bounds} = World.get_cell(pid, {10, 0})
      assert {:error, :out_of_bounds} = World.get_cell(pid, {0, 10})
    end

    test "set_cell merges data into existing cell", %{pid: pid} do
      :ok = World.set_cell(pid, {5, 5}, %{terrain: :water})
      {:ok, cell} = World.get_cell(pid, {5, 5})
      assert cell.terrain == :water
    end

    test "set_cell returns error for out-of-bounds", %{pid: pid} do
      assert {:error, :out_of_bounds} = World.set_cell(pid, {99, 99}, %{terrain: :grass})
    end

    test "neighbors returns valid adjacent coords", %{pid: pid} do
      # Corner cell — only 2 neighbors
      n = World.neighbors(pid, {0, 0})
      assert length(n) == 2
      assert {1, 0} in n
      assert {0, 1} in n

      # Middle cell — 4 neighbors
      n = World.neighbors(pid, {5, 5})
      assert length(n) == 4
    end

    test "all 10x10 cells are populated", %{pid: pid} do
      for x <- 0..9, y <- 0..9 do
        {:ok, cell} = World.get_cell(pid, {x, y})
        assert cell.terrain in [:grass, :water, :forest, :mountain]
      end
    end

    test "terrain is deterministic with same seed" do
      w1 = World.new("Det1", grid_size: {5, 5}, seed: 123)
      w2 = World.new("Det2", grid_size: {5, 5}, seed: 123)

      {:ok, pid1} = GenServer.start_link(World, w1)
      {:ok, pid2} = GenServer.start_link(World, w2)

      for x <- 0..4, y <- 0..4 do
        {:ok, c1} = World.get_cell(pid1, {x, y})
        {:ok, c2} = World.get_cell(pid2, {x, y})
        assert c1.terrain == c2.terrain, "Mismatch at {#{x}, #{y}}"
      end

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end

  describe "biome system" do
    test "biome_at returns valid biome types" do
      for x <- [0, 10, 25, 50, 75, 99], y <- [0, 10, 25, 50, 75, 99] do
        biome = World.biome_at(x, y, 42)
        assert biome in [:plains, :forest_village, :coastal, :mountain_pass],
               "Invalid biome #{biome} at {#{x}, #{y}}"
      end
    end

    test "biome_at is deterministic with same seed" do
      for x <- 0..20, y <- 0..20 do
        b1 = World.biome_at(x, y, 999)
        b2 = World.biome_at(x, y, 999)
        assert b1 == b2, "Biome not deterministic at {#{x}, #{y}}"
      end
    end

    test "different seeds produce different biome maps" do
      biomes1 = for x <- 0..9, y <- 0..9, do: World.biome_at(x, y, 100)
      biomes2 = for x <- 0..9, y <- 0..9, do: World.biome_at(x, y, 200)
      # Not all should be the same
      assert biomes1 != biomes2
    end
  end

  describe "village generation" do
    test "generates villages within bounds" do
      villages = World.generate_villages(100, 100, 42)
      assert length(villages) >= 3
      assert length(villages) <= 6

      for {vx, vy} <- villages do
        assert vx >= 0 and vx < 100, "Village x=#{vx} out of bounds"
        assert vy >= 0 and vy < 100, "Village y=#{vy} out of bounds"
      end
    end

    test "near_village? detects proximity" do
      villages = [{50, 50}]
      assert World.near_village?(52, 50, villages, 6)
      refute World.near_village?(60, 60, villages, 6)
    end

    test "villages are deterministic with same seed" do
      v1 = World.generate_villages(100, 100, 777)
      v2 = World.generate_villages(100, 100, 777)
      assert v1 == v2
    end
  end

  describe "seed determinism (full world)" do
    test "same seed + same grid_size = identical terrain" do
      w1 = World.new("S1", grid_size: {30, 30}, seed: 54321)
      w2 = World.new("S2", grid_size: {30, 30}, seed: 54321)

      {:ok, pid1} = GenServer.start_link(World, w1)
      {:ok, pid2} = GenServer.start_link(World, w2)

      for x <- 0..29, y <- 0..29 do
        {:ok, c1} = World.get_cell(pid1, {x, y})
        {:ok, c2} = World.get_cell(pid2, {x, y})
        assert c1.terrain == c2.terrain, "Mismatch at {#{x}, #{y}}"
      end

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end

  describe "configurable grid size" do
    test "100x100 grid initializes all cells" do
      w = World.new("Big", grid_size: {100, 100}, seed: 1)
      {:ok, pid} = GenServer.start_link(World, w)

      # Check corners
      {:ok, _} = World.get_cell(pid, {0, 0})
      {:ok, _} = World.get_cell(pid, {99, 99})
      assert {:error, :out_of_bounds} = World.get_cell(pid, {100, 0})

      GenServer.stop(pid)
    end

    test "custom grid sizes work" do
      for size <- [20, 50, 75] do
        w = World.new("Custom#{size}", grid_size: {size, size}, seed: 1)
        {:ok, pid} = GenServer.start_link(World, w)
        {:ok, _} = World.get_cell(pid, {size - 1, size - 1})
        assert {:error, :out_of_bounds} = World.get_cell(pid, {size, 0})
        GenServer.stop(pid)
      end
    end
  end

  describe "river generation" do
    test "on_river? returns boolean and is deterministic" do
      r1 = World.on_river?(25, 25, 42, 100, 100)
      r2 = World.on_river?(25, 25, 42, 100, 100)
      assert r1 == r2
      assert is_boolean(r1)
    end
  end
end
