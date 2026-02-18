defmodule Modus.Simulation.AgingTest do
  use ExUnit.Case, async: true

  alias Modus.Simulation.Aging

  setup do
    Aging.init()
    :ok
  end

  describe "stage/1" do
    test "child stage for age 0-4" do
      assert Aging.stage(0) == :child
      assert Aging.stage(4) == :child
    end

    test "young stage for age 5-14" do
      assert Aging.stage(5) == :young
      assert Aging.stage(14) == :young
    end

    test "adult stage for age 15-29" do
      assert Aging.stage(15) == :adult
      assert Aging.stage(29) == :adult
    end

    test "elder stage for age 30+" do
      assert Aging.stage(30) == :elder
      assert Aging.stage(50) == :elder
    end
  end

  describe "emoji/1" do
    test "returns correct emoji per stage" do
      assert Aging.emoji(:child) == "👶"
      assert Aging.emoji(:young) == "🧑"
      assert Aging.emoji(:adult) == "🧔"
      assert Aging.emoji(:elder) == "👴"
    end
  end

  describe "modifiers/1" do
    test "children learn fast" do
      mods = Aging.modifiers(:child)
      assert mods.learning_rate == 2.0
      assert mods.strength == 0.5
    end

    test "elders are wise but slow" do
      mods = Aging.modifiers(:elder)
      assert mods.wisdom == 2.0
      assert mods.speed == 0.6
    end

    test "adults are balanced" do
      mods = Aging.modifiers(:adult)
      assert mods.learning_rate == 1.0
      assert mods.strength == 1.0
    end
  end

  describe "init_agent/2 and get_data/1" do
    test "creates aging data with lifespan" do
      Aging.init_agent("test-agent-1")
      data = Aging.get_data("test-agent-1")
      assert data != nil
      assert data.stage == :child
      assert data.lifespan >= 30
      assert data.lifespan <= 50
      assert data.milestones == []
    end

    test "returns nil for unknown agent" do
      assert Aging.get_data("nonexistent") == nil
    end
  end

  describe "should_die_of_age?/2" do
    test "false when young" do
      Aging.init_agent("young-agent")
      refute Aging.should_die_of_age?("young-agent", 10)
    end

    test "true when age exceeds lifespan" do
      Aging.init_agent("old-agent")
      # Lifespan max is 50, so 60 should always trigger
      assert Aging.should_die_of_age?("old-agent", 60)
    end
  end

  describe "stage_label/1" do
    test "returns correct labels" do
      assert Aging.stage_label(:child) == "Child"
      assert Aging.stage_label(:elder) == "Elder"
    end
  end

  describe "serialize/2" do
    test "serializes aging data" do
      Aging.init_agent("ser-agent")
      result = Aging.serialize("ser-agent", 5)
      assert result["stage"] == "young"
      assert result["emoji"] == "🧑"
      assert is_map(result["modifiers"])
      assert result["modifiers"]["learning_rate"] == 1.5
    end
  end

  describe "population_pyramid/0" do
    test "returns valid structure" do
      pyramid = Aging.population_pyramid()
      assert Map.has_key?(pyramid, :child)
      assert Map.has_key?(pyramid, :young)
      assert Map.has_key?(pyramid, :adult)
      assert Map.has_key?(pyramid, :elder)
      assert Map.has_key?(pyramid, :total)
    end
  end
end
