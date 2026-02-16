defmodule Modus.Intelligence.BehaviorTreeTest do
  use ExUnit.Case, async: true

  alias Modus.Intelligence.BehaviorTree
  alias Modus.Simulation.Agent

  describe "evaluate/2 — need-driven" do
    test "hungry agent seeks food" do
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 85.0, social: 50.0, rest: 80.0, shelter: 70.0}}
      assert BehaviorTree.evaluate(agent, 1) == :find_food
    end

    test "exhausted agent goes to sleep" do
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 50.0, social: 50.0, rest: 15.0, shelter: 70.0}}
      assert BehaviorTree.evaluate(agent, 1) == :go_home_sleep
    end

    test "lonely agent seeks friend" do
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 50.0, social: 25.0, rest: 80.0, shelter: 70.0}}
      assert BehaviorTree.evaluate(agent, 1) == :find_friend
    end

    test "hunger takes priority over low social" do
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 90.0, social: 10.0, rest: 80.0, shelter: 70.0}}
      assert BehaviorTree.evaluate(agent, 1) == :find_food
    end
  end

  describe "evaluate/2 — personality-driven" do
    test "returns :idle on non-10th ticks with satisfied needs" do
      agent = Agent.new("Test", {5, 5})
      assert BehaviorTree.evaluate(agent, 3) == :idle
    end

    test "personality check fires on tick divisible by 10" do
      # Run many times — should not crash
      agent = %{Agent.new("Test", {5, 5}) | personality: %{
        openness: 0.9, conscientiousness: 0.5,
        extraversion: 0.5, agreeableness: 0.9, neuroticism: 0.3
      }}
      results = for _ <- 1..100, do: BehaviorTree.evaluate(agent, 10)
      assert Enum.all?(results, &(&1 in [:explore, :help_nearby, :gather, :idle]))
    end
  end
end
