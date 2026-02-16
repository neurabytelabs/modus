defmodule Modus.Simulation.WorldTest do
  use ExUnit.Case, async: true
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
      world = World.new("Custom", 
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
end
