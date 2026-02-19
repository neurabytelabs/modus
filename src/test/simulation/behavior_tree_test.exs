defmodule Modus.Intelligence.BehaviorTreeTest do
  use ExUnit.Case, async: true

  alias Modus.Intelligence.BehaviorTree

  describe "evaluate/2 defensive guards" do
    test "returns :idle for nil agent" do
      assert :idle == BehaviorTree.evaluate(nil, 100)
    end

    test "returns :idle for agent with nil needs" do
      agent = %Modus.Simulation.Agent{
        id: "test",
        name: "Test",
        needs: nil,
        personality: %{openness: 0.5, conscientiousness: 0.5, extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.5},
        position: {5, 5},
        conatus_energy: 0.5,
        inventory: %{}
      }

      assert :idle == BehaviorTree.evaluate(agent, 100)
    end

    test "returns :idle for agent with nil personality" do
      agent = %Modus.Simulation.Agent{
        id: "test",
        name: "Test",
        needs: %{hunger: 50.0, rest: 50.0, social: 50.0, shelter: 50.0},
        personality: nil,
        position: {5, 5},
        conatus_energy: 0.5,
        inventory: %{}
      }

      assert :idle == BehaviorTree.evaluate(agent, 100)
    end
  end
end
