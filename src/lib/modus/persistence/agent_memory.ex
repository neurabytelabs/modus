defmodule Modus.Persistence.AgentMemory do
  @moduledoc """
  AgentMemory — Persistent long-term memory for agents.

  Memoria: Agents remember significant events across world saves/loads.
  Important events (high affect, deaths, friendships, discoveries) are
  automatically stored in SQLite and retrieved when worlds are loaded.
  """
  require Logger

  alias Modus.Repo
  alias Modus.Schema.AgentMemory, as: MemorySchema
  import Ecto.Query

  @max_memories_per_agent 50

  # ── Public API ──────────────────────────────────────────

  @doc "Record a memory for an agent. Returns {:ok, memory} or {:error, changeset}."
  def record(agent_id, agent_name, memory_type, content, opts \\ []) do
    importance = Keyword.get(opts, :importance, 0.5)
    tick = Keyword.get(opts, :tick, 0)
    metadata = Keyword.get(opts, :metadata, %{})

    attrs = %{
      agent_id: agent_id,
      agent_name: agent_name,
      memory_type: to_string(memory_type),
      content: content,
      importance: ensure_float(importance),
      tick: tick,
      metadata_json: Jason.encode!(metadata)
    }

    case Repo.insert(MemorySchema.changeset(%MemorySchema{}, attrs)) do
      {:ok, memory} ->
        # Prune old low-importance memories if over limit
        prune(agent_id)
        {:ok, memory}

      {:error, changeset} ->
        Logger.warning("Failed to record memory: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc "Get all memories for an agent, ordered by importance desc."
  def get_memories(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    type = Keyword.get(opts, :type, nil)

    query =
      MemorySchema
      |> where([m], m.agent_id == ^agent_id)
      |> order_by([m], [desc: m.importance, desc: m.tick])
      |> limit(^limit)

    query =
      if type do
        where(query, [m], m.memory_type == ^to_string(type))
      else
        query
      end

    Repo.all(query)
  end

  @doc "Get formatted memories for LLM context."
  def format_for_context(agent_id, limit \\ 5) do
    memories = get_memories(agent_id, limit: limit)

    case memories do
      [] ->
        "No notable experiences in your past."

      mems ->
        mems
        |> Enum.map(fn m ->
          type_label = type_to_label(m.memory_type)
          "- [#{type_label}] #{m.content} (importance: #{round_importance(m.importance)})"
        end)
        |> Enum.join("\n")
    end
  end

  @doc "Record event from simulation automatically based on event type and affect."
  def maybe_record_from_event(agent_id, agent_name, event_type, tick, data \\ %{}) do
    case event_type do
      :death ->
        cause = Map.get(data, :cause, "unknown")
        record(agent_id, agent_name, :death,
          "#{agent_name} died: #{cause} (tick #{tick})",
          importance: 1.0, tick: tick, metadata: data)

      :conversation ->
        # Only record if affect is high
        affect = Map.get(data, :affect, :neutral)
        if affect in [:joy, :fear, :sadness, :desire] do
          partner = Map.get(data, :partner, "someone")
          record(agent_id, agent_name, :conversation,
            "#{agent_name} had a meaningful conversation with #{partner} (mood: #{affect})",
            importance: 0.7, tick: tick, metadata: data)
        else
          :skip
        end

      :friendship ->
        partner = Map.get(data, :partner, "someone")
        record(agent_id, agent_name, :friendship,
          "#{agent_name} and #{partner} became friends",
          importance: 0.8, tick: tick, metadata: data)

      :conflict ->
        partner = Map.get(data, :partner, "someone")
        record(agent_id, agent_name, :conflict,
          "#{agent_name} and #{partner} had a conflict",
          importance: 0.7, tick: tick, metadata: data)

      :discovery ->
        what = Map.get(data, :what, "something")
        record(agent_id, agent_name, :discovery,
          "#{agent_name} discovered: #{what}",
          importance: 0.6, tick: tick, metadata: data)

      :emotional ->
        affect = Map.get(data, :affect, :neutral)
        record(agent_id, agent_name, :emotional,
          "#{agent_name} experienced intense #{affect}",
          importance: 0.6, tick: tick, metadata: data)

      _ ->
        :skip
    end
  end

  @doc "Load memories for multiple agents at once (for world load)."
  def load_bulk(agent_ids) when is_list(agent_ids) do
    MemorySchema
    |> where([m], m.agent_id in ^agent_ids)
    |> order_by([m], [desc: m.importance, desc: m.tick])
    |> Repo.all()
    |> Enum.group_by(& &1.agent_id)
  end

  @doc "Delete all memories for an agent."
  def clear(agent_id) do
    MemorySchema
    |> where([m], m.agent_id == ^agent_id)
    |> Repo.delete_all()
  end

  @doc "Count memories for an agent."
  def count(agent_id) do
    MemorySchema
    |> where([m], m.agent_id == ^agent_id)
    |> Repo.aggregate(:count, :id)
  end

  # ── Private ─────────────────────────────────────────────

  defp prune(agent_id) do
    count = count(agent_id)

    if count > @max_memories_per_agent do
      # Delete lowest importance memories beyond the limit
      to_keep =
        MemorySchema
        |> where([m], m.agent_id == ^agent_id)
        |> order_by([m], [desc: m.importance, desc: m.tick])
        |> limit(@max_memories_per_agent)
        |> select([m], m.id)
        |> Repo.all()

      MemorySchema
      |> where([m], m.agent_id == ^agent_id and m.id not in ^to_keep)
      |> Repo.delete_all()
    end
  end

  defp type_to_label("death"), do: "Death"
  defp type_to_label("friendship"), do: "Friendship"
  defp type_to_label("discovery"), do: "Discovery"
  defp type_to_label("conversation"), do: "Conversation"
  defp type_to_label("conflict"), do: "Conflict"
  defp type_to_label("emotional"), do: "Emotion"
  defp type_to_label(_), do: "Event"

  defp round_importance(val), do: Float.round(ensure_float(val), 1)

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val / 1
  defp ensure_float(_), do: 0.0
end
