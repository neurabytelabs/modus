defmodule Modus.Mind.ConversationMemory do
  @moduledoc """
  ETS-backed conversation memory for agents.

  Stores user-agent and agent-agent chat exchanges with timestamps.
  Supports keyword-based search and recency-based retrieval.
  Integrates with ContextBuilder to inject past conversation context into prompts.
  """

  @table :conversation_memory
  @max_entries 20

  @doc "Initialize the ETS table for conversation memory."
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  @doc """
  Record a conversation exchange.

  ## Parameters
    - agent_id: The agent's unique identifier
    - partner_name: Name of the conversation partner (e.g. "user")
    - messages: List of {speaker, text} tuples
    - tick: Simulation tick when conversation occurred
    - opts: Optional keyword list with :category (:user_chat | :agent_chat)
  """
  @spec record(String.t(), String.t(), [{String.t(), String.t()}], number(), keyword()) :: :ok
  def record(agent_id, partner_name, messages, tick, opts \\ []) do
    init()
    category = Keyword.get(opts, :category, :agent_chat)

    entry = %{
      id: :crypto.strong_rand_bytes(4) |> Base.encode16(),
      partner: partner_name,
      messages: messages,
      tick: tick,
      category: category,
      timestamp: System.system_time(:second)
    }

    existing = get_all(agent_id)
    updated = Enum.take([entry | existing], @max_entries)
    :ets.insert(@table, {agent_id, updated})

    # Also store as episodic memory when it's a user chat
    if category == :user_chat do
      content =
        messages
        |> Enum.map(fn {speaker, text} -> "#{speaker}: #{text}" end)
        |> Enum.join(" | ")

      Modus.Mind.EpisodicMemory.store(agent_id, :social, tick, content,
        tags: [:user_chat, :conversation],
        related_agent_id: partner_name,
        metadata: %{category: :user_chat, messages: messages}
      )
    end

    :ok
  end

  @doc "Get all conversation entries for an agent."
  @spec get_all(String.t()) :: [map()]
  def get_all(agent_id) do
    init()

    case :ets.lookup(@table, agent_id) do
      [{_, entries}] -> entries
      [] -> []
    end
  end

  @doc "Get recent conversation entries, optionally filtered by category."
  @spec get_recent(String.t(), integer(), keyword()) :: [map()]
  def get_recent(agent_id, count \\ 3, opts \\ []) do
    category = Keyword.get(opts, :category)

    entries = get_all(agent_id)

    entries =
      if category do
        Enum.filter(entries, fn e -> Map.get(e, :category) == category end)
      else
        entries
      end

    Enum.take(entries, count)
  end

  @doc """
  Search conversations by keyword matching against message content.

  Returns entries where any message text contains one of the given keywords.
  """
  @spec search(String.t(), String.t()) :: [map()]
  def search(agent_id, query) when is_binary(query) do
    keywords =
      query
      |> String.downcase()
      |> String.split(~r/\s+/, trim: true)

    get_all(agent_id)
    |> Enum.filter(fn entry ->
      entry.messages
      |> Enum.any?(fn {_speaker, text} ->
        lower = String.downcase(text)
        Enum.any?(keywords, fn kw -> String.contains?(lower, kw) end)
      end)
    end)
  end

  @doc "Get only user chat entries for an agent."
  @spec get_user_chats(String.t(), integer()) :: [map()]
  def get_user_chats(agent_id, count \\ 5) do
    get_recent(agent_id, count, category: :user_chat)
  end

  @doc "Format recent conversations for LLM context injection."
  @spec format_for_context(String.t()) :: String.t()
  def format_for_context(agent_id) do
    memories = get_recent(agent_id, 5)

    case memories do
      [] ->
        ""

      _ ->
        memories
        |> Enum.map(fn m ->
          msgs =
            Map.get(m, :messages)
            |> Enum.take(4)
            |> Enum.map(fn {speaker, line} -> "#{speaker}: #{line}" end)
            |> Enum.join(" / ")

          category_label =
            case Map.get(m, :category) do
              :user_chat -> "[User chat]"
              _ -> "[Agent chat]"
            end

          "- #{category_label} #{Map.get(m, :partner)} ile: #{msgs}"
        end)
        |> Enum.join("\n")
    end
  end

  @doc "Clear all conversation memory for an agent."
  @spec clear(String.t()) :: :ok
  def clear(agent_id) do
    init()
    :ets.delete(@table, agent_id)
    :ok
  end

  @doc "Clear all conversation memory."
  @spec clear_all() :: :ok
  def clear_all do
    init()
    :ets.delete_all_objects(@table)
    :ok
  end
end
