defmodule Modus.Simulation.ResourceSystemTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.{ResourceSystem, World, Environment}

  setup do
    start_supervised!({Phoenix.PubSub, name: Modus.PubSub})
    start_supervised!(Environment)

    world = World.new("TestWorld", seed: 42)
    start_supervised!({World, world})
    start_supervised!(ResourceSystem)

    # Get a known cell for testing
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

  test "gather depletes resources from a cell", %{world_state: ws} do
    pos = find_cell_with_terrain(ws, :grass)
    assert pos != nil

    # Grass cells start with food: 3
    {:ok, gathered} = ResourceSystem.gather(pos, :food, 2.0)
    assert gathered == 2.0

    # Check remaining
    [{{_, _}, cell}] = :ets.lookup(ws.grid_table, pos)
    assert cell.resources.food == 1.0
  end

  test "gather returns only available amount", %{world_state: ws} do
    pos = find_cell_with_terrain(ws, :grass)
    assert pos != nil

    # Try to gather more than available (grass has food: 3)
    {:ok, gathered} = ResourceSystem.gather(pos, :food, 10.0)
    assert gathered == 3.0

    # Now should be 0
    {:ok, gathered2} = ResourceSystem.gather(pos, :food, 1.0)
    assert gathered2 == 0.0
  end

  test "forest cells have wood and food resources", %{world_state: ws} do
    pos = find_cell_with_terrain(ws, :forest)
    assert pos != nil

    {:ok, wood} = ResourceSystem.gather(pos, :wood, 1.0)
    assert wood == 1.0

    {:ok, food} = ResourceSystem.gather(pos, :food, 1.0)
    assert food == 1.0
  end

  test "gather from non-existent resource returns 0", %{world_state: ws} do
    pos = find_cell_with_terrain(ws, :grass)
    assert pos != nil

    # Grass has no wood
    {:ok, gathered} = ResourceSystem.gather(pos, :wood, 1.0)
    assert gathered == 0.0
  end
end
