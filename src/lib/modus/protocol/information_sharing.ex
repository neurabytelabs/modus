defmodule Modus.Protocol.InformationSharing do
  @moduledoc """
  Information sharing — spatial knowledge transfer between agents.
  When agents converse, they share knowledge about locations,
  resources, dangers, and points of interest.
  """

  @table :shared_knowledge
  @max_knowledge 30

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  @knowledge_types [:resource_location, :danger_zone, :building_location, :wildlife_sighting, :safe_area]

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end
    :ok
  end

  @doc "Record a piece of spatial knowledge for an agent."
  @spec record_knowledge(String.t(), atom(), {integer(), integer()}, map()) :: :ok
  def record_knowledge(agent_id, type, position, metadata \\ %{}) when type in @knowledge_types do
    init()
    entry = %{
      type: type,
      position: position,
      metadata: metadata,
      source: :direct_observation,
      accuracy: 1.0,
      tick_observed: Map.get(metadata, :tick, 0),
      timestamp: System.system_time(:second)
    }
    existing = get_knowledge(agent_id)
    # Deduplicate by type+position
    filtered = Enum.reject(existing, fn k -> k.type == type and k.position == position end)
    updated = Enum.take([entry | filtered], @max_knowledge)
    :ets.insert(@table, {agent_id, updated})
    :ok
  end

  @doc "Share knowledge from one agent to another. Accuracy degrades on transfer."
  @spec share_knowledge(String.t(), String.t(), float()) :: {:ok, integer()}
  def share_knowledge(from_id, to_id, trust_level \\ 0.5) do
    init()
    source_knowledge = get_knowledge(from_id)
    target_knowledge = get_knowledge(to_id)

    # Only share knowledge the target doesn't already have (better version of)
    new_items = source_knowledge
    |> Enum.filter(fn k ->
      existing = Enum.find(target_knowledge, fn tk ->
        tk.type == k.type and tk.position == k.position
      end)
      # Share if target doesn't have it or source has higher accuracy
      is_nil(existing) or (existing.accuracy < k.accuracy * degrade_factor(trust_level))
    end)
    |> Enum.map(fn k ->
      %{k |
        source: :shared,
        accuracy: min(1.0, ensure_float(k.accuracy) * degrade_factor(trust_level))
      }
    end)
    |> Enum.take(5)  # Max 5 items per sharing event

    if new_items != [] do
      existing_target = get_knowledge(to_id)
      # Merge: replace existing with better accuracy, add new
      merged = Enum.reduce(new_items, existing_target, fn item, acc ->
        idx = Enum.find_index(acc, fn k -> k.type == item.type and k.position == item.position end)
        if idx do
          List.replace_at(acc, idx, item)
        else
          [item | acc]
        end
      end)
      updated = Enum.take(merged, @max_knowledge)
      :ets.insert(@table, {to_id, updated})
    end

    {:ok, length(new_items)}
  end

  @doc "Get all knowledge for an agent."
  @spec get_knowledge(String.t()) :: [map()]
  def get_knowledge(agent_id) do
    init()
    case :ets.lookup(@table, agent_id) do
      [{_, knowledge}] -> knowledge
      [] -> []
    end
  end

  @doc "Get knowledge of a specific type."
  @spec get_knowledge_by_type(String.t(), atom()) :: [map()]
  def get_knowledge_by_type(agent_id, type) do
    get_knowledge(agent_id) |> Enum.filter(&(&1.type == type))
  end

  @doc "Format knowledge for LLM context."
  @spec format_for_context(String.t()) :: String.t()
  def format_for_context(agent_id) do
    knowledge = get_knowledge(agent_id) |> Enum.take(10)
    case knowledge do
      [] -> ""
      items ->
        items
        |> Enum.map(fn k ->
          {x, y} = k.position
          acc = round(ensure_float(k.accuracy) * 100)
          "- #{format_type(k.type)} at (#{x},#{y}) [#{acc}% certain]"
        end)
        |> Enum.join("\n")
    end
  end

  # ── Helpers ────────────────────────────────────────────

  defp degrade_factor(trust_level) do
    # Higher trust = less degradation (0.6 to 0.95)
    0.6 + ensure_float(trust_level) * 0.35
  end

  defp format_type(:resource_location), do: "Resources"
  defp format_type(:danger_zone), do: "⚠️ Danger"
  defp format_type(:building_location), do: "Building"
  defp format_type(:wildlife_sighting), do: "Wildlife"
  defp format_type(:safe_area), do: "Safe area"
  defp format_type(other), do: to_string(other)
end
