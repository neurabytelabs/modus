defmodule Modus.Llm.ChatHistoryTest do
  use ExUnit.Case, async: false

  alias Modus.Llm.ChatHistory

  setup do
    ChatHistory.init()
    ChatHistory.clear_all()
    :ok
  end

  test "add and get messages" do
    ChatHistory.add_message("agent_1", "user", "Hello")
    ChatHistory.add_message("agent_1", "agent", "Hi there!")
    messages = ChatHistory.get_messages("agent_1")
    assert length(messages) == 2
    assert hd(messages).text == "Hello"
  end

  test "returns empty list for unknown agent" do
    assert ChatHistory.get_messages("unknown") == []
  end

  test "limits to 50 messages" do
    for i <- 1..60 do
      ChatHistory.add_message("agent_1", "user", "msg #{i}")
    end

    messages = ChatHistory.get_messages("agent_1")
    assert length(messages) == 50
    assert hd(messages).text == "msg 11"
  end
end
