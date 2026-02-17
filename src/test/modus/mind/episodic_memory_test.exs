defmodule Modus.Mind.EpisodicMemoryTest do
  use ExUnit.Case, async: false

  alias Modus.Mind.EpisodicMemory

  setup do
    EpisodicMemory.init()
    agent_id = "test_agent_#{:erlang.unique_integer([:positive])}"
    on_exit(fn -> EpisodicMemory.clear(agent_id) end)
    %{agent_id: agent_id}
  end

  describe "store/5" do
    test "stores an event memory", %{agent_id: aid} do
      mem = EpisodicMemory.store(aid, :event, 10, "found berries")
      assert mem.type == :event
      assert mem.content == "found berries"
      assert mem.weight == 1.0
    end

    test "stores all four memory types", %{agent_id: aid} do
      for type <- [:event, :social, :spatial, :emotional] do
        mem = EpisodicMemory.store(aid, type, 1, "#{type} memory")
        assert mem.type == type
      end
      assert length(EpisodicMemory.recall(aid, limit: 100)) == 4
    end

    test "stores with position", %{agent_id: aid} do
      mem = EpisodicMemory.store(aid, :spatial, 5, "river found",
        position: {10, 20})
      assert mem.position == {10, 20}
    end

    test "stores social memory with related_agent_id", %{agent_id: aid} do
      mem = EpisodicMemory.store(aid, :social, 5, "traded with Kai",
        related_agent_id: "kai_01")
      assert mem.related_agent_id == "kai_01"
    end
  end

  describe "recall/2" do
    test "returns memories sorted by weight descending", %{agent_id: aid} do
      EpisodicMemory.store(aid, :event, 1, "weak", weight: 0.3)
      EpisodicMemory.store(aid, :event, 2, "strong", weight: 0.9)
      [first | _] = EpisodicMemory.recall(aid)
      assert first.content == "strong"
    end

    test "filters by type", %{agent_id: aid} do
      EpisodicMemory.store(aid, :event, 1, "e1")
      EpisodicMemory.store(aid, :social, 2, "s1")
      result = EpisodicMemory.recall(aid, type: :social)
      assert length(result) == 1
      assert hd(result).type == :social
    end

    test "filters by min_weight", %{agent_id: aid} do
      EpisodicMemory.store(aid, :event, 1, "weak", weight: 0.1)
      EpisodicMemory.store(aid, :event, 2, "strong", weight: 0.8)
      result = EpisodicMemory.recall(aid, min_weight: 0.5)
      assert length(result) == 1
      assert hd(result).content == "strong"
    end

    test "respects limit", %{agent_id: aid} do
      for i <- 1..10, do: EpisodicMemory.store(aid, :event, i, "event #{i}")
      result = EpisodicMemory.recall(aid, limit: 3)
      assert length(result) == 3
    end
  end

  describe "recall_for_context/2" do
    test "returns formatted strings", %{agent_id: aid} do
      EpisodicMemory.store(aid, :event, 42, "found gold", position: {5, 10})
      [line] = EpisodicMemory.recall_for_context(aid, 1)
      assert line =~ "EVENT"
      assert line =~ "42"
      assert line =~ "found gold"
    end
  end

  describe "decay_all/1" do
    test "reduces weight over time", %{agent_id: aid} do
      EpisodicMemory.store(aid, :event, 0, "old event", weight: 1.0)
      EpisodicMemory.decay_all(200)
      [mem] = EpisodicMemory.recall(aid, min_weight: 0.0)
      assert mem.weight < 1.0
    end

    test "emotional memories decay slower than events", %{agent_id: aid} do
      EpisodicMemory.store(aid, :event, 0, "evt", weight: 1.0)
      EpisodicMemory.store(aid, :emotional, 0, "emo", weight: 1.0)
      EpisodicMemory.decay_all(200)
      mems = EpisodicMemory.recall(aid, min_weight: 0.0)
      emo = Enum.find(mems, &(&1.type == :emotional))
      evt = Enum.find(mems, &(&1.type == :event))
      assert emo.weight > evt.weight
    end

    test "removes memories below threshold", %{agent_id: aid} do
      EpisodicMemory.store(aid, :event, 0, "vanish", weight: 0.15)
      EpisodicMemory.decay_all(5000)
      assert EpisodicMemory.recall(aid) == []
    end
  end

  describe "clear/1" do
    test "removes all memories for agent", %{agent_id: aid} do
      EpisodicMemory.store(aid, :event, 1, "a")
      EpisodicMemory.store(aid, :social, 2, "b")
      assert length(EpisodicMemory.recall(aid, limit: 100)) == 2
      EpisodicMemory.clear(aid)
      assert EpisodicMemory.recall(aid) == []
    end
  end
end
