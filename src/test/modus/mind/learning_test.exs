defmodule Modus.Mind.LearningTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.Learning

  setup do
    Learning.init()
    agent_id = "test_agent_#{:rand.uniform(100_000)}"
    {:ok, agent_id: agent_id}
  end

  describe "init_skills/1" do
    test "initializes all skills at level 0", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      skills = Learning.get_skills(agent_id)

      for skill <- Learning.skill_types() do
        assert Map.has_key?(skills, skill)
        assert skills[skill].level == 0
        assert skills[skill].xp == 0.0
      end
    end

    test "returns default skills for unknown agent" do
      skills = Learning.get_skills("nonexistent_agent")
      assert map_size(skills) == length(Learning.skill_types())
    end
  end

  describe "add_xp/3" do
    test "adds xp without level up", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      assert {:ok, 0} = Learning.add_xp(agent_id, :farming, 50.0)
      assert Learning.get_skill(agent_id, :farming).xp == 50.0
    end

    test "levels up when xp threshold reached", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      assert {:level_up, 0, 1} = Learning.add_xp(agent_id, :building, 100.0)
      assert Learning.skill_level(agent_id, :building) == 1
    end

    test "multiple level ups accumulate", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      Learning.add_xp(agent_id, :social, 50.0)
      Learning.add_xp(agent_id, :social, 60.0)
      # 110 xp -> level 1
      assert Learning.skill_level(agent_id, :social) == 1
      assert Learning.get_skill(agent_id, :social).xp == 110.0
    end

    test "ignores non-positive xp", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      assert {:ok, 0} = Learning.add_xp(agent_id, :farming, -10.0)
    end
  end

  describe "efficiency/2" do
    test "base efficiency is 1.0 at level 0", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      assert Learning.efficiency(agent_id, :farming) == 1.0
    end

    test "efficiency increases with level", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      # level 3
      Learning.add_xp(agent_id, :farming, 500.0)
      assert Learning.efficiency(agent_id, :farming) == 1.6
    end
  end

  describe "cultural inheritance" do
    test "child inherits fraction of parent skills" do
      Learning.init()
      parent_a = "parent_a_#{:rand.uniform(100_000)}"
      parent_b = "parent_b_#{:rand.uniform(100_000)}"
      child = "child_#{:rand.uniform(100_000)}"

      Learning.init_skills(parent_a)
      Learning.init_skills(parent_b)
      Learning.add_xp(parent_a, :farming, 1000.0)
      Learning.add_xp(parent_b, :farming, 500.0)

      Learning.init_skills_with_inheritance(child, parent_a, parent_b)

      child_farming = Learning.get_skill(child, :farming)
      # avg = 750, inheritance = 750 * 0.3 = 225 -> level 1
      assert child_farming.xp > 0.0
      assert child_farming.xp == 225.0
      assert child_farming.level == 1
    end

    test "child of unskilled parents starts at 0" do
      Learning.init()
      parent_a = "unskilled_a_#{:rand.uniform(100_000)}"
      parent_b = "unskilled_b_#{:rand.uniform(100_000)}"
      child = "unskilled_child_#{:rand.uniform(100_000)}"

      Learning.init_skills(parent_a)
      Learning.init_skills(parent_b)
      Learning.init_skills_with_inheritance(child, parent_a, parent_b)

      for skill <- Learning.skill_types() do
        assert Learning.get_skill(child, skill).xp == 0.0
      end
    end
  end

  describe "award_for_action/2" do
    test "awards xp for known actions", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      Learning.award_for_action(agent_id, :gather)
      assert Learning.get_skill(agent_id, :farming).xp == 5.0
    end

    test "ignores unknown actions", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      assert :ok = Learning.award_for_action(agent_id, :unknown_action)
    end
  end

  describe "to_map/1" do
    test "serializes skills for frontend", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      Learning.add_xp(agent_id, :farming, 150.0)
      map = Learning.to_map(agent_id)

      assert is_map(map)
      assert Map.has_key?(map, "farming")
      assert map["farming"]["xp"] == 150.0
      assert map["farming"]["level"] == 1
      assert is_float(map["farming"]["progress"])
    end
  end

  describe "cleanup/1" do
    test "removes agent skills", %{agent_id: agent_id} do
      Learning.init_skills(agent_id)
      Learning.add_xp(agent_id, :farming, 100.0)
      Learning.cleanup(agent_id)
      # After cleanup, get_skills returns defaults (all 0)
      skills = Learning.get_skills(agent_id)
      assert skills[:farming].xp == 0.0
    end
  end
end
