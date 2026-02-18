defmodule Modus.Mind.EpisodicMemory do
  @moduledoc """
  ETS-backed per-agent episodic memory system.

  Stores typed memories (event, social, spatial, emotional) with decay.
  Emotional memories persist longer. Provides top-N recall for LLM context.
  """

  @table :episodic_memories
  @max_per_agent 100

  @decay_rates %{
    event: 0.005,
    social: 0.004,
    spatial: 0.006,
    emotional: 0.002
  }

  defmodule Memory do
    @moduledoc "Episodic memory struct with typed fields."
    defstruct [
      :id,
      :agent_id,
      :type,
      :tick,
      :position,
      :content,
      :tags,
      :related_agent_id,
      :emotion,
      :intensity,
      :metadata,
      weight: 1.0
    ]
  end

  # --- Init ---

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:bag, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  # --- Store ---

  def store(agent_id, type, tick, content, opts \\ [])
      when type in [:event, :social, :spatial, :emotional] do
    init()

    memory = %Memory{
      id: :crypto.strong_rand_bytes(4) |> Base.encode16(),
      agent_id: agent_id,
      type: type,
      tick: ensure_float(tick),
      position: Keyword.get(opts, :position, {0, 0}),
      content: content,
      tags: Keyword.get(opts, :tags, []),
      related_agent_id: Keyword.get(opts, :related_agent_id),
      emotion: Keyword.get(opts, :emotion),
      intensity: safe_float(Keyword.get(opts, :intensity)),
      metadata: Keyword.get(opts, :metadata),
      weight: ensure_float(Keyword.get(opts, :weight, 1.0))
    }

    :ets.insert(@table, {agent_id, memory})
    enforce_limit(agent_id)
    memory
  end

  # --- Recall ---

  def recall(agent_id, opts \\ []) do
    init()
    limit = Keyword.get(opts, :limit, 10)
    type_filter = Keyword.get(opts, :type)
    min_weight = ensure_float(Keyword.get(opts, :min_weight, 0.0))

    :ets.lookup(@table, agent_id)
    |> Enum.map(fn {_, m} -> m end)
    |> Enum.filter(fn m ->
      ensure_float(m.weight) >= min_weight and
        (type_filter == nil or m.type == type_filter)
    end)
    |> Enum.sort_by(&ensure_float(&1.weight), :desc)
    |> Enum.take(limit)
  end

  def recall_for_context(agent_id, limit \\ 5) do
    recall(agent_id, limit: limit)
    |> Enum.map(&format_memory/1)
  end

  defp format_memory(%Memory{} = m) do
    {x, y} = m.position
    type_label = m.type |> Atom.to_string() |> String.upcase()
    base = "Tick #{round(m.tick)} [#{type_label}]: #{m.content} at (#{x},#{y})"
    parts = [base]
    parts = if m.emotion, do: parts ++ [" (felt #{m.emotion})"], else: parts
    parts = if m.related_agent_id, do: parts ++ [" with #{m.related_agent_id}"], else: parts
    Enum.join(parts)
  end

  # --- Decay ---

  def decay_all(current_tick) do
    init()
    current = ensure_float(current_tick)

    :ets.tab2list(@table)
    |> Enum.each(fn {agent_id, memory} ->
      ticks_passed = max(current - ensure_float(memory.tick), 0.0)
      rate = Map.get(@decay_rates, memory.type, 0.005)
      decay = ensure_float(rate) * (ticks_passed / 50.0)
      new_weight = max(ensure_float(memory.weight) - decay, 0.0)

      :ets.match_delete(@table, {agent_id, memory})

      if new_weight >= 0.1 do
        :ets.insert(@table, {agent_id, %{memory | weight: new_weight}})
      end
    end)

    :ok
  end

  # --- Count / Clear ---

  def count(agent_id) do
    if :ets.whereis(@table) != :undefined do
      :ets.lookup(@table, agent_id) |> length()
    else
      0
    end
  end

  def clear(agent_id) do
    if :ets.whereis(@table) != :undefined do
      :ets.match_delete(@table, {agent_id, :_})
    end

    :ok
  end

  def clear_all do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  # --- Helpers ---

  defp enforce_limit(agent_id) do
    all = :ets.lookup(@table, agent_id)

    if length(all) > @max_per_agent do
      sorted = Enum.sort_by(all, fn {_, m} -> ensure_float(m.weight) end)
      to_remove = Enum.take(sorted, length(all) - @max_per_agent)

      for {_id, m} <- to_remove do
        :ets.match_delete(@table, {agent_id, m})
      end
    end
  end

  defp ensure_float(val) when is_float(val), do: val
  defp ensure_float(val) when is_integer(val), do: val * 1.0
  defp ensure_float(_), do: 0.0

  defp safe_float(nil), do: nil
  defp safe_float(val), do: ensure_float(val)
end
