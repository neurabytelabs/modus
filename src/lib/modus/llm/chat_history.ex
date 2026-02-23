defmodule Modus.Llm.ChatHistory do
  @moduledoc """
  ETS-based chat history storage for the chat panel.
  Stores last 50 messages per agent.
  """

  @table :modus_chat_history
  @max_messages 50

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  @doc "Add a message to an agent's chat history."
  def add_message(agent_id, role, text, opts \\ []) do
    messages = get_messages(agent_id)

    msg = %{
      role: role,
      text: text,
      name: Keyword.get(opts, :name),
      topic: Keyword.get(opts, :topic),
      timestamp: System.system_time(:second)
    }

    updated = Enum.take(messages ++ [msg], -@max_messages)
    :ets.insert(@table, {agent_id, updated})
    :ok
  end

  @doc "Get chat history for an agent (last 50 messages)."
  def get_messages(agent_id) do
    if :ets.whereis(@table) != :undefined do
      case :ets.lookup(@table, agent_id) do
        [{^agent_id, messages}] -> messages
        [] -> []
      end
    else
      []
    end
  end

  @doc "Clear chat history for an agent."
  def clear(agent_id) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table, agent_id)
    end

    :ok
  end

  @doc "Clear all chat history."
  def clear_all do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end
end
