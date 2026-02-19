defmodule Modus.World.AgentChatViewerTest do
  use ExUnit.Case, async: false

  alias Modus.World.AgentChatViewer

  setup do
    case Process.whereis(AgentChatViewer) do
      nil ->
        AgentChatViewer.start_link([])
      _pid ->
        :ets.delete_all_objects(:modus_agent_chats)
        :sys.replace_state(AgentChatViewer, fn _state ->
          %{next_id: 1, oldest_id: 1}
        end)
    end
    :ok
  end

  describe "record_chat/1" do
    test "records a chat and returns entry with id" do
      chat =
        AgentChatViewer.record_chat(%{
          agent_a_id: "agent-1",
          agent_b_id: "agent-2",
          agent_a_name: "Alice",
          agent_b_name: "Bob",
          messages: "Alice: Hello!\nBob: Hi there!",
          topic: :gossip,
          tick: 42,
          affect_a: :joy,
          affect_b: :neutral
        })

      assert chat.id >= 1
      assert chat.agent_a == "agent-1"
      assert chat.agent_b == "agent-2"
      assert chat.agent_a_name == "Alice"
      assert chat.agent_b_name == "Bob"
      assert chat.messages == "Alice: Hello!\nBob: Hi there!"
      assert chat.topic == :gossip
      assert chat.tick == 42
      assert chat.affect_states.agent_a == :joy
      assert chat.affect_states.agent_b == :neutral
      assert is_integer(chat.timestamp)
    end

    test "broadcasts via PubSub" do
      Phoenix.PubSub.subscribe(Modus.PubSub, "agent_chats")

      AgentChatViewer.record_chat(%{
        agent_a_id: "agent-1",
        agent_b_id: "agent-2",
        messages: "Hello!",
        tick: 1
      })

      assert_receive {:new_agent_chat, chat_data}
      assert chat_data.agent_a == "agent-1"
      assert chat_data.topic == "general"
    end
  end

  describe "list_chats/1" do
    test "returns empty list when no chats" do
      assert AgentChatViewer.list_chats() == []
    end

    test "returns chats sorted by timestamp desc" do
      for i <- 1..5 do
        AgentChatViewer.record_chat(%{
          agent_a_id: "a-#{i}",
          agent_b_id: "b-#{i}",
          messages: "Chat #{i}",
          tick: i
        })
      end

      chats = AgentChatViewer.list_chats()
      assert length(chats) == 5
      # Most recent first
      assert hd(chats).tick == 5
    end

    test "filters by agent_id" do
      AgentChatViewer.record_chat(%{agent_a_id: "alice", agent_b_id: "bob", messages: "hi", tick: 1})
      AgentChatViewer.record_chat(%{agent_a_id: "charlie", agent_b_id: "dave", messages: "hey", tick: 2})
      AgentChatViewer.record_chat(%{agent_a_id: "eve", agent_b_id: "alice", messages: "yo", tick: 3})

      chats = AgentChatViewer.list_chats(agent_id: "alice")
      assert length(chats) == 2
      assert Enum.all?(chats, fn c -> c.agent_a == "alice" or c.agent_b == "alice" end)
    end

    test "filters by topic" do
      AgentChatViewer.record_chat(%{agent_a_id: "a", agent_b_id: "b", messages: "hi", tick: 1, topic: :trade})
      AgentChatViewer.record_chat(%{agent_a_id: "c", agent_b_id: "d", messages: "hey", tick: 2, topic: :gossip})

      chats = AgentChatViewer.list_chats(topic: :trade)
      assert length(chats) == 1
      assert hd(chats).topic == :trade
    end

    test "respects limit" do
      for i <- 1..10 do
        AgentChatViewer.record_chat(%{agent_a_id: "a", agent_b_id: "b", messages: "#{i}", tick: i})
      end

      chats = AgentChatViewer.list_chats(limit: 3)
      assert length(chats) == 3
    end
  end

  describe "ring buffer" do
    test "evicts oldest entries beyond max (100)" do
      for i <- 1..105 do
        AgentChatViewer.record_chat(%{
          agent_a_id: "a",
          agent_b_id: "b",
          messages: "msg-#{i}",
          tick: i
        })
      end

      assert AgentChatViewer.count() == 100
      # Oldest (id 1-5) should be gone
      assert AgentChatViewer.get_chat(1) == nil
      assert AgentChatViewer.get_chat(6) != nil
    end
  end

  describe "get_chat/1" do
    test "returns chat by id" do
      chat = AgentChatViewer.record_chat(%{agent_a_id: "a", agent_b_id: "b", messages: "hi", tick: 1})
      assert AgentChatViewer.get_chat(chat.id) == chat
    end

    test "returns nil for missing id" do
      assert AgentChatViewer.get_chat(99999) == nil
    end
  end

  describe "serialize_chat/1" do
    test "converts atoms to strings" do
      chat = AgentChatViewer.record_chat(%{
        agent_a_id: "a",
        agent_b_id: "b",
        messages: "hi",
        tick: 1,
        topic: :trade,
        affect_a: :joy,
        affect_b: :fear
      })

      serialized = AgentChatViewer.serialize_chat(chat)
      assert serialized.topic == "trade"
      assert serialized.affect_states.agent_a == "joy"
      assert serialized.affect_states.agent_b == "fear"
    end
  end
end
