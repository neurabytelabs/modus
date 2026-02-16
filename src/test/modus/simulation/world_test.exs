defmodule Modus.Simulation.WorldTest do
  use ExUnit.Case, async: false
  alias Modus.Simulation.World

  describe "new/2" do
    test "creates world with default grid size" do
      world = World.new("Test Universe")

      assert world.name == "Test Universe"
      assert world.grid_size == {50, 50}
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
end
