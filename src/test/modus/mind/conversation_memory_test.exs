defmodule Modus.Mind.ConversationMemoryTest do
  use ExUnit.Case, async: true

  alias Modus.Mind.ConversationMemory

  setup do
    ConversationMemory.init()
    agent_id = "test_agent_#{:rand.uniform(99999)}"
    on_exit(fn -> ConversationMemory.clear(agent_id) end)
    %{agent_id: agent_id}
  end

  test "init creates ETS table" do
    assert ConversationMemory.init() == :ok
  end

  test "record and get_all", %{agent_id: agent_id} do
    ConversationMemory.record(agent_id, "Ali", [{"Ali", "Merhaba!"}], 100)
    entries = ConversationMemory.get_all(agent_id)
    assert length(entries) == 1
    assert hd(entries).partner == "Ali"
  end

  test "record with user_chat category", %{agent_id: agent_id} do
    ConversationMemory.record(
      agent_id, "user",
      [{"user", "Hello!"}, {"Agent", "Hi there!"}],
      100, category: :user_chat
    )
    entries = ConversationMemory.get_all(agent_id)
    assert length(entries) == 1
    assert hd(entries).category == :user_chat
    assert length(hd(entries).messages) == 2
  end

  test "max entries cap at 20", %{agent_id: agent_id} do
    for i <- 1..25 do
      ConversationMemory.record(agent_id, "Agent#{i}", [{"Agent#{i}", "Hi"}], i)
    end

    assert length(ConversationMemory.get_all(agent_id)) == 20
  end

  test "format_for_context returns string", %{agent_id: agent_id} do
    result = ConversationMemory.format_for_context(agent_id)
    assert is_binary(result)
  end

  test "format_for_context shows category labels", %{agent_id: agent_id} do
    ConversationMemory.record(agent_id, "user", [{"user", "Hi"}, {"Bot", "Hello"}], 1, category: :user_chat)
    result = ConversationMemory.format_for_context(agent_id)
    assert String.contains?(result, "[User chat]")
  end

  test "get_recent returns limited entries", %{agent_id: agent_id} do
    for i <- 1..5 do
      ConversationMemory.record(agent_id, "Agent#{i}", [{"Agent#{i}", "Hi"}], i)
    end

    assert length(ConversationMemory.get_recent(agent_id, 2)) == 2
  end

  test "get_recent filters by category", %{agent_id: agent_id} do
    ConversationMemory.record(agent_id, "user", [{"user", "Hi"}], 1, category: :user_chat)
    ConversationMemory.record(agent_id, "Ali", [{"Ali", "Hey"}], 2, category: :agent_chat)
    ConversationMemory.record(agent_id, "user", [{"user", "Bye"}], 3, category: :user_chat)

    user_chats = ConversationMemory.get_recent(agent_id, 10, category: :user_chat)
    assert length(user_chats) == 2
    assert Enum.all?(user_chats, fn e -> e.category == :user_chat end)
  end

  test "get_user_chats returns only user chat entries", %{agent_id: agent_id} do
    ConversationMemory.record(agent_id, "user", [{"user", "Hi"}], 1, category: :user_chat)
    ConversationMemory.record(agent_id, "Ali", [{"Ali", "Hey"}], 2)

    chats = ConversationMemory.get_user_chats(agent_id)
    assert length(chats) == 1
    assert hd(chats).category == :user_chat
  end

  test "search finds conversations by keyword", %{agent_id: agent_id} do
    ConversationMemory.record(agent_id, "user", [{"user", "What is the weather?"}, {"Bot", "It's sunny!"}], 1)
    ConversationMemory.record(agent_id, "user", [{"user", "Tell me about food"}, {"Bot", "I love berries"}], 2)

    results = ConversationMemory.search(agent_id, "weather")
    assert length(results) == 1
    assert hd(results).messages |> Enum.any?(fn {_, t} -> String.contains?(t, "weather") end)
  end

  test "search is case insensitive", %{agent_id: agent_id} do
    ConversationMemory.record(agent_id, "user", [{"user", "HELLO WORLD"}], 1)
    results = ConversationMemory.search(agent_id, "hello")
    assert length(results) == 1
  end

  test "search with multiple keywords", %{agent_id: agent_id} do
    ConversationMemory.record(agent_id, "user", [{"user", "I like cats"}], 1)
    ConversationMemory.record(agent_id, "user", [{"user", "Dogs are great"}], 2)

    results = ConversationMemory.search(agent_id, "cats dogs")
    assert length(results) == 2
  end

  test "clear removes all entries", %{agent_id: agent_id} do
    ConversationMemory.record(agent_id, "user", [{"user", "Hi"}], 1)
    ConversationMemory.clear(agent_id)
    assert ConversationMemory.get_all(agent_id) == []
  end

  test "entries have unique ids", %{agent_id: agent_id} do
    ConversationMemory.record(agent_id, "user", [{"user", "Hi"}], 1)
    ConversationMemory.record(agent_id, "user", [{"user", "Bye"}], 2)
    ids = ConversationMemory.get_all(agent_id) |> Enum.map(& &1.id)
    assert length(Enum.uniq(ids)) == 2
  end

  test "entries have timestamps", %{agent_id: agent_id} do
    ConversationMemory.record(agent_id, "user", [{"user", "Hi"}], 1)
    entry = hd(ConversationMemory.get_all(agent_id))
    assert is_integer(entry.timestamp)
    assert entry.timestamp > 0
  end
end
