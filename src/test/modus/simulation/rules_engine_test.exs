defmodule Modus.Simulation.RulesEngineTest do
  use ExUnit.Case, async: false

  alias Modus.Simulation.RulesEngine

  setup do
    RulesEngine.init()
    :ok
  end

  test "init creates default rules" do
    rules = RulesEngine.get_rules()
    assert rules.time_speed == 1.0
    assert rules.resource_abundance == :normal
    assert rules.danger_level == :moderate
    assert rules.birth_rate == 1.0
    assert rules.language == "en"
    assert rules.preset == "Custom"
  end

  test "update changes rules and sets preset to Custom" do
    RulesEngine.update(%{time_speed: 2.0, birth_rate: 1.5})
    rules = RulesEngine.get_rules()
    assert rules.time_speed == 2.0
    assert rules.birth_rate == 1.5
    assert rules.preset == "Custom"
  end

  test "apply_preset sets all values and preset name" do
    {:ok, rules} = RulesEngine.apply_preset("Peaceful Paradise")
    assert rules.preset == "Peaceful Paradise"
    assert rules.resource_abundance == :abundant
    assert rules.danger_level == :peaceful
    assert rules.birth_rate == 1.5
  end

  test "apply unknown preset returns error" do
    assert {:error, :unknown_preset} = RulesEngine.apply_preset("NonExistent")
  end

  test "convenience accessors work" do
    RulesEngine.update(%{time_speed: 2.5, mutation_rate: 0.8})
    assert RulesEngine.time_speed() == 2.5
    assert RulesEngine.mutation_rate() == 0.8
  end

  test "serialize returns string keys for atoms" do
    serialized = RulesEngine.serialize()
    assert serialized.resource_abundance == "normal"
    assert serialized.danger_level == "moderate"
    assert serialized.language == "en"
    assert is_binary(serialized.preset)
  end

  test "language can be set and retrieved" do
    RulesEngine.update(%{language: "tr"})
    assert RulesEngine.language() == "tr"
    RulesEngine.update(%{language: "de"})
    assert RulesEngine.language() == "de"
  end

  test "preset_names returns all preset names" do
    names = RulesEngine.preset_names()
    assert "Peaceful Paradise" in names
    assert "Harsh Survival" in names
    assert "Chaotic" in names
    assert "Utopia" in names
    assert "Evolution Lab" in names
    assert length(names) == 5
  end
end
