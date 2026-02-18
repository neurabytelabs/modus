defmodule Modus.Mind.PlannerTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.Planner
  alias Modus.Mind.Planner.{Plan, Step}

  setup do
    Planner.init()
    Planner.clear_all()
    :ok
  end

  # --- Goal Decomposition ---

  describe "decompose/2" do
    test "build_house decomposes into 4 steps" do
      steps = Planner.decompose(:build_house, %{})
      assert length(steps) == 4
      actions = Enum.map(steps, & &1.action)
      assert actions == [:gather_wood, :gather_stone, :find_location, :build]
    end

    test "satisfy_hunger decomposes into 3 steps" do
      steps = Planner.decompose(:satisfy_hunger, %{})
      assert length(steps) == 3
      assert List.first(steps).action == :find_food_source
    end

    test "find_rest decomposes into 2 steps" do
      steps = Planner.decompose(:find_rest, %{})
      assert length(steps) == 2
    end

    test "socialize decomposes into 3 steps" do
      steps = Planner.decompose(:socialize, %{})
      assert length(steps) == 3
      assert List.last(steps).action == :talk
    end

    test "flee_danger includes threat position" do
      steps = Planner.decompose(:flee_danger, %{threat_position: {10, 10}})
      flee_step = Enum.find(steps, &(&1.action == :flee))
      assert flee_step.params.from == {10, 10}
    end

    test "unknown goal creates single-step plan" do
      steps = Planner.decompose(:meditate, %{})
      assert length(steps) == 1
      assert List.first(steps).action == :meditate
    end

    test "all steps start as pending" do
      steps = Planner.decompose(:build_house, %{})
      assert Enum.all?(steps, &(&1.status == :pending))
    end
  end

  # --- Plan Creation ---

  describe "create_plan/3" do
    test "creates a plan and stores it" do
      plan = Planner.create_plan("agent_1", :build_house)
      assert plan.goal == :build_house
      assert plan.status == :active
      assert plan.agent_id == "agent_1"
      assert length(plan.steps) == 4
    end

    test "plan has correct default priority" do
      hunger_plan = Planner.create_plan("a1", :satisfy_hunger)
      assert hunger_plan.priority == 80

      build_plan = Planner.create_plan("a1", :build_house)
      assert build_plan.priority == 40

      social_plan = Planner.create_plan("a1", :socialize)
      assert social_plan.priority == 20
    end

    test "custom priority overrides default" do
      plan = Planner.create_plan("a1", :build_house, priority: 99)
      assert plan.priority == 99
    end

    test "multiple plans for same agent" do
      Planner.create_plan("a1", :build_house)
      Planner.create_plan("a1", :satisfy_hunger)
      plans = Planner.get_plans("a1")
      assert length(plans) == 2
    end
  end

  # --- Priority Queue ---

  describe "active_plans/1" do
    test "returns plans sorted by priority desc" do
      # 20
      Planner.create_plan("a1", :socialize)
      # 40
      Planner.create_plan("a1", :build_house)
      # 80
      Planner.create_plan("a1", :satisfy_hunger)

      plans = Planner.active_plans("a1")
      priorities = Enum.map(plans, & &1.priority)
      assert priorities == Enum.sort(priorities, :desc)
      assert List.first(plans).goal == :satisfy_hunger
    end

    test "excludes completed and failed plans" do
      plan = Planner.create_plan("a1", :build_house)
      Planner.create_plan("a1", :satisfy_hunger)

      # Complete first plan's all steps
      Enum.each(plan.steps, fn s ->
        Planner.complete_step("a1", plan.id, s.action, 10)
      end)

      active = Planner.active_plans("a1")
      assert length(active) == 1
      assert List.first(active).goal == :satisfy_hunger
    end
  end

  # --- Next Action ---

  describe "next_action/3" do
    test "returns action from highest priority plan" do
      Planner.create_plan("a1", :build_house)
      agent_state = %{needs: %{hunger: 50.0, rest: 80.0, shelter: 70.0, social: 50.0}}

      assert {:ok, :gather_wood, _params, _plan_id} = Planner.next_action("a1", agent_state, 1)
    end

    test "urgent needs override all plans" do
      Planner.create_plan("a1", :build_house)
      agent_state = %{needs: %{hunger: 95.0, rest: 80.0, shelter: 70.0, social: 50.0}}

      assert {:ok, :gather, %{resource_type: :food}, :urgent} =
               Planner.next_action("a1", agent_state, 1)
    end

    test "threat overrides everything" do
      Planner.create_plan("a1", :build_house)

      agent_state = %{
        needs: %{hunger: 50.0, rest: 80.0, shelter: 70.0, social: 50.0},
        under_threat: true,
        threat_position: {5, 5}
      }

      assert {:ok, :flee, %{from: {5, 5}}, :urgent} =
               Planner.next_action("a1", agent_state, 1)
    end

    test "returns :no_plan when no active plans" do
      agent_state = %{needs: %{hunger: 50.0, rest: 80.0, shelter: 70.0, social: 50.0}}
      assert :no_plan = Planner.next_action("a1", agent_state, 1)
    end

    test "critical rest triggers urgent sleep" do
      agent_state = %{needs: %{hunger: 50.0, rest: 5.0, shelter: 70.0, social: 50.0}}
      assert {:ok, :sleep, %{}, :urgent} = Planner.next_action("a1", agent_state, 1)
    end
  end

  # --- Step Completion ---

  describe "complete_step/4" do
    test "advances to next step" do
      plan = Planner.create_plan("a1", :build_house)
      Planner.complete_step("a1", plan.id, :gather_wood, 5)

      updated = Planner.get_plans("a1") |> Enum.find(&(&1.id == plan.id))
      first_step = List.first(updated.steps)
      assert first_step.status == :completed
      assert first_step.completed_at == 5
    end

    test "completing all steps completes the plan" do
      plan = Planner.create_plan("a1", :find_rest)
      Planner.complete_step("a1", plan.id, :find_shelter, 1)
      Planner.complete_step("a1", plan.id, :sleep, 2)

      updated = Planner.get_plans("a1") |> Enum.find(&(&1.id == plan.id))
      assert updated.status == :completed
    end
  end

  # --- Plan Revision ---

  describe "block_step/4" do
    test "revises plan when step is blocked" do
      plan = Planner.create_plan("a1", :build_house)
      assert {:revised, revised} = Planner.block_step("a1", plan.id, :gather_wood, 5)

      assert revised.revision == 1
      assert revised.status == :active
      # Should have alternative steps instead of blocked one
      assert length(revised.steps) > length(plan.steps)
    end

    test "fails after 3 revisions" do
      plan = Planner.create_plan("a1", :build_house)

      {:revised, _} = Planner.block_step("a1", plan.id, :gather_wood, 1)
      {:revised, _} = Planner.block_step("a1", plan.id, :gather_wood, 2)
      {:revised, _} = Planner.block_step("a1", plan.id, :gather_wood, 3)
      result = Planner.block_step("a1", plan.id, :gather_wood, 4)

      assert {:failed, failed_plan} = result
      assert failed_plan.status == :failed
    end

    test "returns :not_found for unknown plan" do
      assert :not_found = Planner.block_step("a1", "nonexistent", :foo, 1)
    end
  end

  # --- Auto Planning ---

  describe "evaluate_and_plan/3" do
    test "creates hunger plan when hungry" do
      agent_state = %{needs: %{hunger: 80.0, rest: 80.0, shelter: 70.0, social: 50.0}}
      plans = Planner.evaluate_and_plan("a1", agent_state, 1)

      assert length(plans) == 1
      assert List.first(plans).goal == :satisfy_hunger
    end

    test "creates rest plan when exhausted" do
      agent_state = %{needs: %{hunger: 50.0, rest: 10.0, shelter: 70.0, social: 50.0}}
      plans = Planner.evaluate_and_plan("a1", agent_state, 1)

      goals = Enum.map(plans, & &1.goal)
      assert :find_rest in goals
    end

    test "creates shelter plan when exposed" do
      agent_state = %{needs: %{hunger: 50.0, rest: 80.0, shelter: 20.0, social: 50.0}}
      plans = Planner.evaluate_and_plan("a1", agent_state, 1)

      goals = Enum.map(plans, & &1.goal)
      assert :build_house in goals
    end

    test "creates social plan when lonely" do
      agent_state = %{needs: %{hunger: 50.0, rest: 80.0, shelter: 70.0, social: 15.0}}
      plans = Planner.evaluate_and_plan("a1", agent_state, 1)

      goals = Enum.map(plans, & &1.goal)
      assert :socialize in goals
    end

    test "does not duplicate existing plans" do
      agent_state = %{needs: %{hunger: 80.0, rest: 80.0, shelter: 70.0, social: 50.0}}
      Planner.evaluate_and_plan("a1", agent_state, 1)
      Planner.evaluate_and_plan("a1", agent_state, 2)

      plans = Planner.active_plans("a1")
      hunger_plans = Enum.filter(plans, &(&1.goal == :satisfy_hunger))
      assert length(hunger_plans) == 1
    end

    test "creates no plans when all needs are met" do
      agent_state = %{needs: %{hunger: 40.0, rest: 80.0, shelter: 70.0, social: 60.0}}
      plans = Planner.evaluate_and_plan("a1", agent_state, 1)
      assert plans == []
    end
  end

  # --- Progress ---

  describe "plan_progress/1" do
    test "empty plan returns 1.0" do
      assert Planner.plan_progress(%Plan{steps: []}) == 1.0
    end

    test "no completed steps returns 0.0" do
      plan = Planner.create_plan("a1", :build_house)
      assert Planner.plan_progress(plan) == 0.0
    end

    test "partial completion returns fraction" do
      plan = Planner.create_plan("a1", :build_house)
      Planner.complete_step("a1", plan.id, :gather_wood, 1)

      updated = Planner.get_plans("a1") |> Enum.find(&(&1.id == plan.id))
      assert Planner.plan_progress(updated) == 0.25
    end
  end

  # --- Serialization ---

  describe "serialize/1" do
    test "serializes plans to maps" do
      Planner.create_plan("a1", :build_house)
      serialized = Planner.serialize("a1")

      assert length(serialized) == 1
      plan = List.first(serialized)
      assert plan.goal == "build_house"
      assert plan.status == "active"
      assert is_list(plan.steps)
      assert is_float(plan.progress)
    end
  end

  # --- Cleanup ---

  describe "remove_plan/2" do
    test "removes a specific plan" do
      plan1 = Planner.create_plan("a1", :build_house)
      _plan2 = Planner.create_plan("a1", :satisfy_hunger)

      Planner.remove_plan("a1", plan1.id)
      plans = Planner.get_plans("a1")
      assert length(plans) == 1
      assert List.first(plans).goal == :satisfy_hunger
    end
  end

  describe "clear_all/0" do
    test "removes all plans" do
      Planner.create_plan("a1", :build_house)
      Planner.create_plan("a2", :satisfy_hunger)

      Planner.clear_all()
      assert Planner.get_plans("a1") == []
      assert Planner.get_plans("a2") == []
    end
  end
end
