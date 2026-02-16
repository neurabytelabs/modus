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
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 30.0, social: 50.0, rest: 15.0, shelter: 70.0}}
      assert BehaviorTree.evaluate(agent, 1) == :go_home_sleep
    end

    test "lonely agent seeks friend (critical)" do
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 30.0, social: 15.0, rest: 80.0, shelter: 70.0}}
      assert BehaviorTree.evaluate(agent, 1) == :find_friend
    end

    test "hunger takes priority over low social" do
      agent = %{Agent.new("Test", {5, 5}) | needs: %{hunger: 90.0, social: 10.0, rest: 80.0, shelter: 70.0}}
      assert BehaviorTree.evaluate(agent, 1) == :find_food
    end
  end

  describe "evaluate/2 — personality-driven" do
    test "agents with satisfied needs are active (not always idle)" do
      agent = %{Agent.new("Test", {5, 5}) | personality: %{
        openness: 0.8, conscientiousness: 0.5,
        extraversion: 0.5, agreeableness: 0.5, neuroticism: 0.3
      }, needs: %{hunger: 30.0, social: 70.0, rest: 80.0, shelter: 70.0}}
      results = for _ <- 1..100, do: BehaviorTree.evaluate(agent, 3)
      # Most should NOT be idle
      idle_count = Enum.count(results, &(&1 == :idle))
      assert idle_count < 30, "Too many idle actions: #{idle_count}/100"
    end

    test "personality check produces valid actions" do
      agent = %{Agent.new("Test", {5, 5}) | personality: %{
        openness: 0.9, conscientiousness: 0.5,
        extraversion: 0.5, agreeableness: 0.9, neuroticism: 0.3
      }}
      results = for _ <- 1..100, do: BehaviorTree.evaluate(agent, 10)
      assert Enum.all?(results, &(&1 in [:explore, :help_nearby, :gather, :find_friend, :idle, :find_food, :go_home_sleep]))
    end
  end
end
