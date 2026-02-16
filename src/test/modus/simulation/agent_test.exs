defmodule Modus.Simulation.AgentTest do
  use ExUnit.Case, async: true
  alias Modus.Simulation.Agent

  describe "new/3" do
    test "creates agent with valid defaults" do
      agent = Agent.new("Elif", {5, 10}, :farmer)
      
      assert agent.name == "Elif"
      assert agent.position == {5, 10}
      assert agent.occupation == :farmer
      assert agent.alive? == true
      assert agent.age == 0
      assert agent.conatus_score == 5.0
      assert agent.current_action == :idle
    end

    test "generates unique ids" do
      a1 = Agent.new("A", {0, 0})
      a2 = Agent.new("B", {1, 1})
      
      assert a1.id != a2.id
    end

    test "creates random personality with Big Five traits" do
      agent = Agent.new("Test", {0, 0})
      
      assert Map.has_key?(agent.personality, :openness)
      assert Map.has_key?(agent.personality, :conscientiousness)
      assert Map.has_key?(agent.personality, :extraversion)
      assert Map.has_key?(agent.personality, :agreeableness)
      assert Map.has_key?(agent.personality, :neuroticism)

      # All values between 0 and 1
      for {_trait, value} <- agent.personality do
        assert value >= 0.0 and value <= 1.0
      end
    end

    test "initializes needs at balanced levels" do
      agent = Agent.new("Test", {0, 0})
      
      assert agent.needs.hunger == 50.0
      assert agent.needs.social == 50.0
      assert agent.needs.rest == 80.0
      assert agent.needs.shelter == 70.0
    end

    test "defaults to explorer occupation" do
      agent = Agent.new("Test", {0, 0})
      assert agent.occupation == :explorer
    end
  end
end
