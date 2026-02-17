defmodule Modus.Simulation.CraftingSystemTest do
  use ExUnit.Case, async: true

  alias Modus.Simulation.CraftingSystem

  describe "recipes/0" do
    test "returns all recipes" do
      recipes = CraftingSystem.recipes()
      assert Map.has_key?(recipes, :sword)
      assert Map.has_key?(recipes, :bread)
      assert Map.has_key?(recipes, :medicine)
      assert Map.has_key?(recipes, :rope)
      assert Map.has_key?(recipes, :torch)
    end

    test "sword requires iron and wood" do
      assert CraftingSystem.recipes()[:sword] == [:iron, :wood]
    end
  end

  describe "skill_level/1" do
    test "novice at 0 xp" do
      assert CraftingSystem.skill_level(0) == :novice
    end

    test "novice at 24 xp" do
      assert CraftingSystem.skill_level(24) == :novice
    end

    test "apprentice at 25 xp" do
      assert CraftingSystem.skill_level(25) == :apprentice
    end

    test "expert at 50 xp" do
      assert CraftingSystem.skill_level(50) == :expert
    end

    test "master at 75 xp" do
      assert CraftingSystem.skill_level(75) == :master
    end

    test "master at 100 xp" do
      assert CraftingSystem.skill_level(100) == :master
    end
  end

  describe "quality/1" do
    test "novice quality is 0.25" do
      assert CraftingSystem.quality(:novice) == 0.25
    end

    test "master quality is 1.0" do
      assert CraftingSystem.quality(:master) == 1.0
    end
  end

  describe "craft/5" do
    test "successfully crafts sword with ingredients" do
      inventory = %{iron: 2, wood: 3}
      skills = %{}

      assert {:ok, result} = CraftingSystem.craft("agent1", :sword, inventory, skills)
      assert result.item == :sword
      assert result.quality == 0.25
      assert result.level == :novice
      assert result.skill.xp == 5.0
      assert result.skill.crafted_count == 1
      assert result.inventory[:iron] == 1
      assert result.inventory[:wood] == 2
    end

    test "crafts rope with single ingredient" do
      inventory = %{fiber: 1}
      assert {:ok, result} = CraftingSystem.craft("agent1", :rope, inventory, %{})
      assert result.item == :rope
      assert result.inventory[:fiber] == 0
    end

    test "fails with missing ingredients" do
      inventory = %{iron: 1}
      assert {:error, :missing_ingredients} = CraftingSystem.craft("a1", :sword, inventory, %{})
    end

    test "fails with unknown recipe" do
      assert {:error, :unknown_recipe} = CraftingSystem.craft("a1", :laser, %{}, %{})
    end

    test "xp accumulates with repeated crafting" do
      inventory = %{fiber: 10}
      skills = %{}

      {:ok, r1} = CraftingSystem.craft("a1", :rope, inventory, skills)
      {:ok, r2} = CraftingSystem.craft("a1", :rope, r1.inventory, r1.skills)
      assert r2.skill.xp == 10.0
      assert r2.skill.crafted_count == 2
    end

    test "quality improves with skill level" do
      # Simulate expert-level skill
      skills = %{rope: %{xp: 50.0, crafted_count: 20}}
      inventory = %{fiber: 1}

      {:ok, result} = CraftingSystem.craft("a1", :rope, inventory, skills)
      assert result.quality == 0.75
      assert result.level == :expert
    end

    test "xp caps at 100" do
      skills = %{rope: %{xp: 99.9, crafted_count: 100}}
      inventory = %{fiber: 1}

      {:ok, result} = CraftingSystem.craft("a1", :rope, inventory, skills)
      assert result.skill.xp == 100.0
    end
  end

  describe "teach/6" do
    test "master can teach student" do
      teacher_skills = %{sword: %{xp: 80.0, crafted_count: 50}}
      student_skills = %{}

      assert {:ok, result} =
               CraftingSystem.teach("teacher", "student", :sword, teacher_skills, student_skills)

      assert result.xp_gained == 10.0
      assert result.student_skills[:sword].xp == 10.0
    end

    test "non-master cannot teach" do
      teacher_skills = %{sword: %{xp: 40.0, crafted_count: 10}}
      student_skills = %{}

      assert {:error, :teacher_not_master} =
               CraftingSystem.teach("t", "s", :sword, teacher_skills, student_skills)
    end

    test "teaching accumulates student xp" do
      teacher_skills = %{sword: %{xp: 90.0, crafted_count: 50}}
      student_skills = %{sword: %{xp: 20.0, crafted_count: 5}}

      {:ok, result} =
        CraftingSystem.teach("t", "s", :sword, teacher_skills, student_skills)

      assert result.student_skills[:sword].xp == 30.0
    end

    test "student xp caps at 100 via teaching" do
      teacher_skills = %{sword: %{xp: 90.0, crafted_count: 50}}
      student_skills = %{sword: %{xp: 95.0, crafted_count: 40}}

      {:ok, result} =
        CraftingSystem.teach("t", "s", :sword, teacher_skills, student_skills)

      assert result.student_skills[:sword].xp == 100.0
    end
  end
end
