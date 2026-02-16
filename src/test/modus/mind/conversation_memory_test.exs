defmodule Modus.Mind.ConversationMemoryTest do
  use ExUnit.Case, async: true

  alias Modus.Mind.ConversationMemory

  test "init creates ETS table" do
    assert ConversationMemory.init() == :ok
  end

  test "record and get_all" do
    ConversationMemory.init()
    agent_id = "test_agent_#{:rand.uniform(99999)}"
    ConversationMemory.record(agent_id, "Ali", [{"Ali", "Merhaba!"}], 100)
    entries = ConversationMemory.get_all(agent_id)
    assert length(entries) == 1
    assert hd(entries).partner == "Ali"
    ConversationMemory.clear(agent_id)
  end

  test "max entries cap at 10" do
    ConversationMemory.init()
    agent_id = "test_max_#{:rand.uniform(99999)}"
    for i <- 1..15 do
      ConversationMemory.record(agent_id, "Agent#{i}", [{"Agent#{i}", "Hi"}], i)
    end
    assert length(ConversationMemory.get_all(agent_id)) == 10
    ConversationMemory.clear(agent_id)
  end

  test "format_for_context returns string" do
    ConversationMemory.init()
    agent_id = "test_fmt_#{:rand.uniform(99999)}"
    result = ConversationMemory.format_for_context(agent_id)
    assert is_binary(result)
    ConversationMemory.clear(agent_id)
  end

  test "get_recent returns limited entries" do
    ConversationMemory.init()
    agent_id = "test_recent_#{:rand.uniform(99999)}"
    for i <- 1..5 do
      ConversationMemory.record(agent_id, "Agent#{i}", [{"Agent#{i}", "Hi"}], i)
    end
    assert length(ConversationMemory.get_recent(agent_id, 2)) == 2
    ConversationMemory.clear(agent_id)
  end
end
