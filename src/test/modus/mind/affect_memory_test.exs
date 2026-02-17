defmodule Modus.Mind.AffectMemoryTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.AffectMemory

  setup_all do
    AffectMemory.init()
    :ok
  end

  setup do
    agent_id = "test-agent-#{:rand.uniform(100_000)}"
    on_exit(fn -> AffectMemory.clear(agent_id) end)
    %{agent_id: agent_id}
  end

  test "form_memory and recall", %{agent_id: agent_id} do
    AffectMemory.form_memory(agent_id, 100, {10, 15}, :neutral, :joy, "found food", 0.8)
    memories = AffectMemory.recall(agent_id)
    assert length(memories) == 1
    [m] = memories
    assert m.agent_id == agent_id
    assert m.affect_to == :joy
    assert m.salience == 1.0
  end

  test "recall with affect filter", %{agent_id: agent_id} do
    AffectMemory.form_memory(agent_id, 100, {10, 15}, :neutral, :joy, "food", 0.8)
    AffectMemory.form_memory(agent_id, 200, {5, 5}, :joy, :fear, "danger", 0.3)

    joy_memories = AffectMemory.recall(agent_id, affect: :joy)
    assert length(joy_memories) == 1
    assert hd(joy_memories).affect_to == :joy
  end

  test "recall with limit", %{agent_id: agent_id} do
    for i <- 1..10 do
      AffectMemory.form_memory(agent_id, i * 10, {i, i}, :neutral, :joy, "event #{i}", 0.5)
    end

    memories = AffectMemory.recall(agent_id, limit: 3)
    assert length(memories) == 3
  end

  test "spatial_recall", %{agent_id: agent_id} do
    AffectMemory.form_memory(agent_id, 100, {10, 10}, :neutral, :joy, "near", 0.8)
    AffectMemory.form_memory(agent_id, 200, {50, 50}, :neutral, :sadness, "far", 0.8)

    near = AffectMemory.spatial_recall(agent_id, {12, 12}, 5)
    assert length(near) == 1
    assert hd(near).reason == "near"
  end

  test "decay_all reduces salience", %{agent_id: agent_id} do
    AffectMemory.form_memory(agent_id, 10, {5, 5}, :neutral, :joy, "old memory", 0.8)
    AffectMemory.decay_all(1000)

    memories = AffectMemory.recall(agent_id)
    # Should have decayed or been removed
    if memories != [] do
      assert hd(memories).salience < 1.0
    end
  end

  test "memories_for_llm_context returns strings", %{agent_id: agent_id} do
    AffectMemory.form_memory(agent_id, 500, {10, 15}, :neutral, :joy, "finding food", 0.8)
    lines = AffectMemory.memories_for_llm_context(agent_id, 5)
    assert length(lines) == 1
    assert hd(lines) =~ "Tick 500"
    assert hd(lines) =~ "joy"
  end

  test "clear removes all memories", %{agent_id: agent_id} do
    AffectMemory.form_memory(agent_id, 100, {1, 1}, :neutral, :joy, "test", 0.8)
    assert length(AffectMemory.recall(agent_id)) == 1
    AffectMemory.clear(agent_id)
    assert AffectMemory.recall(agent_id) == []
  end

  test "max 50 memories per agent", %{agent_id: agent_id} do
    for i <- 1..60 do
      AffectMemory.form_memory(agent_id, i, {1, 1}, :neutral, :joy, "m#{i}", 0.5 + i * 0.001)
    end

    memories = AffectMemory.recall(agent_id, limit: 100)
    assert length(memories) <= 50
  end
end
