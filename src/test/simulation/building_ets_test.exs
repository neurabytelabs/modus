defmodule Modus.Simulation.BuildingETSTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.Building

  describe "init_table/0 race condition safety" do
    test "init_table can be called multiple times without crash" do
      assert :ok = Building.init_table()
      assert :ok = Building.init_table()
      assert :ok = Building.init_table()
    end

    test "concurrent init_table calls do not crash" do
      tasks =
        for _ <- 1..10 do
          Task.async(fn -> Building.init_table() end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end
end
