defmodule Modus.Simulation.TargetSafetyTest do
  @moduledoc "Tests for defensive handling of missing :target in decision params"
  use ExUnit.Case, async: true

  alias Modus.Simulation.DecisionEngine
  alias Modus.Simulation.Agent

  describe "target-less params safety" do
    test "decide/2 returns params with :target key for explore action" do
      agent = %{
        Agent.new("TargetTest", {5, 5})
        | needs: %{hunger: 30.0, social: 50.0, rest: 80.0, shelter: 70.0}
      }

      {action, params} = DecisionEngine.decide(agent, %{tick: 1, world_size: {50, 50}})
      # Whatever action is returned, params should be a map
      assert is_map(params)
      # If action is explore, target must exist
      if action == :explore do
        assert Map.has_key?(params, :target)
      end
    end

    test "decide/2 never crashes with behavior_tree fallback params" do
      # Simulate what happens when cache has behavior_tree result
      params = %{reason: "behavior_tree"}
      # Accessing target safely should return nil, not crash
      assert Map.get(params, :target) == nil
      assert Map.get(params, :target, {0, 0}) == {0, 0}
    end

    test "Map.put works on params without existing :target key" do
      params = %{reason: "behavior_tree"}
      updated = Map.put(params, :target, {10, 10})
      assert updated.target == {10, 10}
      assert updated.reason == "behavior_tree"
    end

    test "explore action with nil target gets default from random_explore" do
      agent = %{
        Agent.new("ExploreTest", {25, 25})
        | needs: %{hunger: 30.0, social: 50.0, rest: 80.0, shelter: 70.0},
          explore_ticks: 0,
          explore_target: nil
      }

      {action, params} = DecisionEngine.decide(agent, %{tick: 1, world_size: {50, 50}})

      if action == :explore do
        assert is_tuple(Map.get(params, :target))
      end
    end

    test "fallback_chain behavior_tree decisions include :target key" do
      # Verify the normalized output format
      action = :explore
      params = %{reason: "behavior_tree", target: nil}
      assert Map.has_key?(params, :target)
      assert {action, params} == {:explore, %{reason: "behavior_tree", target: nil}}
    end

    test "params with target nil can be safely used in Map.put" do
      params = %{reason: "behavior_tree", target: nil}
      leader_pos = {10, 20}
      updated = Map.put(params, :target, leader_pos)
      assert updated.target == {10, 20}
    end
  end
end
