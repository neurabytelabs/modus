defmodule Modus.Mind.ConversationMemory do
  @moduledoc "Stores last N conversations per agent in ETS"

  @table :conversation_memory
  @max_entries 10

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  def record(agent_id, partner_name, messages, tick) do
    init()

    entry = %{
      partner: partner_name,
      messages: messages,
      tick: tick,
      timestamp: System.system_time(:second)
    }

    existing = get_all(agent_id)
    updated = Enum.take([entry | existing], @max_entries)
    :ets.insert(@table, {agent_id, updated})
    :ok
  end

  def get_all(agent_id) do
    init()

    case :ets.lookup(@table, agent_id) do
      [{_, entries}] -> entries
      [] -> []
    end
  end

  def get_recent(agent_id, count \\ 3) do
    Enum.take(get_all(agent_id), count)
  end

  def format_for_context(agent_id) do
    memories = get_recent(agent_id)

    case memories do
      [] ->
        "You haven't talked to anyone yet."

      _ ->
        memories
        |> Enum.map(fn m ->
          msgs =
            Map.get(m, :messages)
            |> Enum.take(2)
            |> Enum.map(fn {speaker, line} -> "#{speaker}: #{line}" end)
            |> Enum.join(" / ")

          "- #{Map.get(m, :partner)} ile: #{msgs}"
        end)
        |> Enum.join("\n")
    end
  end

  def clear(agent_id) do
    init()
    :ets.delete(@table, agent_id)
    :ok
  end
end
