defmodule Modus.Persistence.AgentMemoryTest do
  use ExUnit.Case, async: false

  alias Modus.Persistence.AgentMemory
  alias Modus.Schema.AgentMemory, as: MemorySchema
  alias Modus.Repo

  @agent_id "test_agent_001"
  @agent_name "TestAgent"

  setup do
    # Clean up test memories
    import Ecto.Query

    MemorySchema
    |> where([m], m.agent_id == ^@agent_id)
    |> Repo.delete_all()

    :ok
  end

  describe "record/5" do
    test "records a memory with default importance" do
      assert {:ok, memory} =
               AgentMemory.record(@agent_id, @agent_name, :death, "Agent died of starvation")

      assert memory.agent_id == @agent_id
      assert memory.agent_name == @agent_name
      assert memory.memory_type == "death"
      assert memory.content == "Agent died of starvation"
      assert memory.importance == 0.5
    end

    test "records a memory with custom importance and tick" do
      assert {:ok, memory} =
               AgentMemory.record(
                 @agent_id,
                 @agent_name,
                 :friendship,
                 "Made a friend",
                 importance: 0.9,
                 tick: 100
               )

      assert memory.importance == 0.9
      assert memory.tick == 100
    end

    test "records memory with metadata" do
      assert {:ok, memory} =
               AgentMemory.record(
                 @agent_id,
                 @agent_name,
                 :discovery,
                 "Found gold",
                 metadata: %{location: [10, 20]}
               )

      assert memory.metadata_json != nil
      assert {:ok, meta} = Jason.decode(memory.metadata_json)
      assert meta["location"] != nil
    end
  end

  describe "get_memories/2" do
    test "returns memories ordered by importance" do
      AgentMemory.record(@agent_id, @agent_name, :death, "Died", importance: 1.0, tick: 10)

      AgentMemory.record(@agent_id, @agent_name, :discovery, "Found water",
        importance: 0.3,
        tick: 20
      )

      AgentMemory.record(@agent_id, @agent_name, :friendship, "Met someone",
        importance: 0.8,
        tick: 30
      )

      memories = AgentMemory.get_memories(@agent_id)
      assert length(memories) == 3
      [first | _] = memories
      assert first.importance == 1.0
    end

    test "filters by type" do
      AgentMemory.record(@agent_id, @agent_name, :death, "Died", importance: 1.0)
      AgentMemory.record(@agent_id, @agent_name, :friendship, "Friend", importance: 0.5)

      memories = AgentMemory.get_memories(@agent_id, type: :death)
      assert length(memories) == 1
      assert hd(memories).memory_type == "death"
    end
  end

  describe "format_for_context/2" do
    test "returns default text when no memories" do
      result = AgentMemory.format_for_context("nonexistent_agent")
      assert result =~ "No notable"
    end

    test "formats memories for LLM context" do
      AgentMemory.record(@agent_id, @agent_name, :death, "Öldü: açlık", importance: 1.0)
      AgentMemory.record(@agent_id, @agent_name, :friendship, "Arkadaş oldu", importance: 0.8)

      result = AgentMemory.format_for_context(@agent_id)
      assert result =~ "Death"
      assert result =~ "Friendship"
    end
  end

  describe "maybe_record_from_event/5" do
    test "records death events" do
      assert {:ok, _} =
               AgentMemory.maybe_record_from_event(
                 @agent_id,
                 @agent_name,
                 :death,
                 50,
                 %{cause: "starvation"}
               )

      memories = AgentMemory.get_memories(@agent_id, type: :death)
      assert length(memories) == 1
      assert hd(memories).importance == 1.0
    end

    test "skips neutral conversation events" do
      result =
        AgentMemory.maybe_record_from_event(
          @agent_id,
          @agent_name,
          :conversation,
          50,
          %{affect: :neutral}
        )

      assert result == :skip
    end

    test "records emotional conversation events" do
      assert {:ok, _} =
               AgentMemory.maybe_record_from_event(
                 @agent_id,
                 @agent_name,
                 :conversation,
                 50,
                 %{affect: :joy, partner: "Ayşe"}
               )

      memories = AgentMemory.get_memories(@agent_id, type: :conversation)
      assert length(memories) == 1
    end
  end

  describe "count/1 and clear/1" do
    test "counts and clears memories" do
      AgentMemory.record(@agent_id, @agent_name, :death, "Died 1", importance: 1.0)
      AgentMemory.record(@agent_id, @agent_name, :death, "Died 2", importance: 0.9)
      assert AgentMemory.count(@agent_id) == 2

      AgentMemory.clear(@agent_id)
      assert AgentMemory.count(@agent_id) == 0
    end
  end

  describe "load_bulk/1" do
    test "loads memories grouped by agent_id" do
      agent2 = "test_agent_002"
      AgentMemory.record(@agent_id, @agent_name, :death, "Died", importance: 1.0)
      AgentMemory.record(agent2, "Agent2", :friendship, "Friend", importance: 0.8)

      result = AgentMemory.load_bulk([@agent_id, agent2])
      assert Map.has_key?(result, @agent_id)
      assert Map.has_key?(result, agent2)

      # Cleanup agent2
      AgentMemory.clear(agent2)
    end
  end
end
