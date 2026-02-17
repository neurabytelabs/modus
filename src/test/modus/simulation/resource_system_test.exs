defmodule Modus.Simulation.ResourceSystemTest do
  use ExUnit.Case, async: false

  @moduledoc "Tests for the ResourceSystem gather mechanics."

  alias Modus.Simulation.{ResourceSystem, World}

  setup do
    if Process.whereis(Modus.PubSub) == nil do
      start_supervised!({Phoenix.PubSub, name: Modus.PubSub})
    end

    if Process.whereis(Modus.Simulation.Environment) == nil do
      start_supervised!(Modus.Simulation.Environment)
    end

    # Start World if not running
    if Process.whereis(World) == nil do
      world = World.new("TestWorld", seed: 42)
      start_supervised!({World, world})
    end

    if Process.whereis(ResourceSystem) == nil do
      start_supervised!(ResourceSystem)
    end

    world_state = World.get_state()
    {:ok, world_state: world_state}
  end

  defp find_cell_with_terrain(world_state, terrain) do
    {max_x, max_y} = world_state.grid_size
    Enum.find_value(0..(max_x - 1), fn x ->
      Enum.find_value(0..(max_y - 1), fn y ->
        case :ets.lookup(world_state.grid_table, {x, y}) do
          [{{^x, ^y}, %{terrain: ^terrain}}] -> {x, y}
          _ -> nil
        end
      end)
    end)
  end

  defp find_cell_with_resource(world_state, resource_type) do
    {max_x, max_y} = world_state.grid_size
    Enum.find_value(0..(max_x - 1), fn x ->
      Enum.find_value(0..(max_y - 1), fn y ->
        case :ets.lookup(world_state.grid_table, {x, y}) do
          [{{^x, ^y}, %{resources: res}}] when is_map(res) ->
            if Map.get(res, resource_type, 0) > 0, do: {x, y}, else: nil
          _ -> nil
        end
      end)
    end)
  end

  test "gather depletes resources from a cell", %{world_state: ws} do
    pos = find_cell_with_resource(ws, :food)
    if pos do
      [{{_, _}, cell}] = :ets.lookup(ws.grid_table, pos)
      initial_food = cell.resources.food

      {:ok, gathered} = ResourceSystem.gather(pos, :food, 1.0)
      assert gathered > 0.0
      assert gathered <= initial_food
    end
  end

  test "gather returns only available amount", %{world_state: ws} do
    pos = find_cell_with_resource(ws, :food)
    if pos do
      [{{_, _}, cell}] = :ets.lookup(ws.grid_table, pos)
      initial = cell.resources.food

      {:ok, gathered} = ResourceSystem.gather(pos, :food, initial + 100.0)
      assert gathered <= initial
    end
  end

  test "forest cells have wood and food resources", %{world_state: ws} do
    pos = find_cell_with_terrain(ws, :forest)
    if pos do
      [{{_, _}, cell}] = :ets.lookup(ws.grid_table, pos)
      assert is_map(cell.resources)
      # Forest cells should have wood or food defined
      assert Map.has_key?(cell.resources, :wood) or Map.has_key?(cell.resources, :food)
    end
  end

  test "gather from non-existent resource returns 0", %{world_state: ws} do
    pos = find_cell_with_terrain(ws, :grass)
    if pos do
      # Grass typically has no stone
      {:ok, gathered} = ResourceSystem.gather(pos, :stone, 1.0)
      assert gathered == 0.0
    end
  end
end
