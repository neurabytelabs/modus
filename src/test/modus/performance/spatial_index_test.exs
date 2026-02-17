defmodule Modus.Performance.SpatialIndexTest do
  use ExUnit.Case, async: true

  alias Modus.Performance.SpatialIndex

  setup do
    SpatialIndex.init()
    # Clean up
    try do :ets.delete_all_objects(:modus_spatial_index) catch _, _ -> :ok end
    :ok
  end

  describe "insert/2 and nearby/2" do
    test "finds inserted agents nearby" do
      SpatialIndex.insert("agent1", {10, 10})
      SpatialIndex.insert("agent2", {12, 12})
      SpatialIndex.insert("agent3", {50, 50})

      nearby = SpatialIndex.nearby({10, 10}, 5)
      assert "agent1" in nearby
      assert "agent2" in nearby
      refute "agent3" in nearby
    end

    test "returns empty for no agents" do
      assert SpatialIndex.nearby({0, 0}, 5) == []
    end
  end

  describe "update/3" do
    test "moves agent between cells" do
      SpatialIndex.insert("agent1", {5, 5})
      assert "agent1" in SpatialIndex.nearby({5, 5}, 5)

      SpatialIndex.update("agent1", {5, 5}, {50, 50})
      refute "agent1" in SpatialIndex.nearby({5, 5}, 5)
      assert "agent1" in SpatialIndex.nearby({50, 50}, 5)
    end
  end

  describe "remove/2" do
    test "removes agent from index" do
      SpatialIndex.insert("agent1", {10, 10})
      assert "agent1" in SpatialIndex.nearby({10, 10}, 5)

      SpatialIndex.remove("agent1", {10, 10})
      refute "agent1" in SpatialIndex.nearby({10, 10}, 5)
    end
  end

  describe "cell_key/2" do
    test "computes correct cell" do
      assert SpatialIndex.cell_key(0, 0) == {0, 0}
      assert SpatialIndex.cell_key(4, 4) == {0, 0}
      assert SpatialIndex.cell_key(5, 5) == {1, 1}
      assert SpatialIndex.cell_key(10, 15) == {2, 3}
    end
  end
end
