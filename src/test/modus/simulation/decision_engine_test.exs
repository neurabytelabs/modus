defmodule Modus.Simulation.DecisionEngineTest do
  use ExUnit.Case, async: true

  alias Modus.Simulation.DecisionEngine
  alias Modus.Simulation.Agent

  describe "decide/2" do
    test "hungry agent decides to find food or explore" do
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 90.0, social: 50.0, rest: 80.0, shelter: 70.0}}
      {action, _params} = DecisionEngine.decide(agent, %{tick: 1})
      assert action in [:move_to, :explore]
    end

    test "exhausted agent decides to sleep" do
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 50.0, social: 50.0, rest: 10.0, shelter: 70.0}}
      {action, _params} = DecisionEngine.decide(agent, %{tick: 1})
      assert action == :sleep
    end

    test "lonely agent with nearby agents decides to talk" do
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 50.0, social: 20.0, rest: 80.0, shelter: 70.0}}
      {action, params} = DecisionEngine.decide(agent, %{tick: 1, nearby_agents: ["agent1"]})
      assert action == :talk
      assert params.target_agent == "agent1"
    end

    test "satisfied agent is idle on non-10 tick" do
      agent = Agent.new("Test", {5, 5})
      {action, _params} = DecisionEngine.decide(agent, %{tick: 3})
      assert action == :idle
    end

    test "find_food with nearby food resource" do
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 90.0, social: 50.0, rest: 80.0, shelter: 70.0}}
      ctx = %{tick: 1, nearby_resources: [{:food, {7, 7}, 5.0}]}
      {action, params} = DecisionEngine.decide(agent, ctx)
      assert action == :move_to
      assert params.target == {7, 7}
    end
  end
end
