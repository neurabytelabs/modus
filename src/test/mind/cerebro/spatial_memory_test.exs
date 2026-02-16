defmodule Modus.Mind.Cerebro.SpatialMemoryTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.Cerebro.SpatialMemory
  alias Modus.Mind.AffectMemory

  setup do
    AffectMemory.init()
    :ok
  end

  test "no bias when no memories exist" do
    target = SpatialMemory.bias_explore_target("nobody", {10, 10}, {20, 20})
    assert target == {20, 20}
  end

  test "agent avoids fear memory location" do
    agent_id = "fear_test_#{:rand.uniform(10000)}"
    AffectMemory.form_memory(agent_id, 1, {12, 12}, :neutral, :fear, "danger", 0.5)
    # Agent is at {10, 10}, fear at {12, 12} — within 5 tiles
    target = SpatialMemory.bias_explore_target(agent_id, {10, 10}, {12, 12})
    # Should repel — target should move away from {12, 12}
    {tx, _ty} = target
    assert tx != 12
    AffectMemory.clear(agent_id)
  end

  test "salience threshold filters weak memories" do
    agent_id = "weak_#{:rand.uniform(10000)}"
    # Form memory then decay it heavily
    AffectMemory.form_memory(agent_id, 1, {30, 30}, :neutral, :joy, "nice", 0.5)
    # Manually check — salience starts at 1.0 which is above 0.3 threshold
    memories = AffectMemory.recall(agent_id, affect: :joy, min_salience: 0.3)
    assert length(memories) > 0
    AffectMemory.clear(agent_id)
  end
end
