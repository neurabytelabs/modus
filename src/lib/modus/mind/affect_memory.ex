defmodule Modus.Mind.AffectMemory do
  @moduledoc "ETS-based affect memory store for agents — episodic memory of emotional transitions."

  @table :affect_memories
  @max_per_agent 50

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:bag, :public, :named_table, read_concurrency: true])
    end
    :ok
  end

  def form_memory(agent_id, tick, position, affect_from, affect_to, reason, conatus) do
    memory = %{
      id: :crypto.strong_rand_bytes(4) |> Base.encode16(),
      agent_id: agent_id,
      tick: tick,
      position: position,
      affect_from: affect_from,
      affect_to: affect_to,
      reason: reason,
      conatus_at: conatus,
      salience: 1.0
    }

    :ets.insert(@table, {agent_id, memory})

    # Enforce max per agent
    all = :ets.lookup(@table, agent_id)
    if length(all) > @max_per_agent do
      sorted = all |> Enum.sort_by(fn {_, m} -> m.salience end)
      to_remove = Enum.take(sorted, length(all) - @max_per_agent)
      for {_id, m} <- to_remove do
        :ets.match_delete(@table, {agent_id, m})
      end
    end

    memory
  end

  def recall(agent_id, opts \\ []) do
    affect_filter = Keyword.get(opts, :affect)
    min_salience = Keyword.get(opts, :min_salience, 0.0)
    limit = Keyword.get(opts, :limit, 20)

    :ets.lookup(@table, agent_id)
    |> Enum.map(fn {_, m} -> m end)
    |> Enum.filter(fn m ->
      m.salience >= min_salience and
        (affect_filter == nil or m.affect_to == affect_filter)
    end)
    |> Enum.sort_by(& &1.tick, :desc)
    |> Enum.take(limit)
  end

  def spatial_recall(agent_id, {x, y}, radius) do
    :ets.lookup(@table, agent_id)
    |> Enum.map(fn {_, m} -> m end)
    |> Enum.filter(fn m ->
      {mx, my} = m.position
      abs(mx - x) <= radius and abs(my - y) <= radius
    end)
    |> Enum.sort_by(& &1.salience, :desc)
  end

  def decay_all(current_tick) do
    # Traverse entire table efficiently
    :ets.tab2list(@table)
    |> Enum.each(fn {agent_id, memory} ->
      ticks_passed = max(current_tick - memory.tick, 0)
      rate = if memory.affect_to == :fear, do: 0.002, else: 0.005
      new_salience = max(memory.salience - rate * (ticks_passed / 50), 0.0)

      if new_salience < 0.1 do
        :ets.match_delete(@table, {agent_id, memory})
      else
        :ets.match_delete(@table, {agent_id, memory})
        :ets.insert(@table, {agent_id, %{memory | salience: new_salience}})
      end
    end)
  end

  def memories_for_llm_context(agent_id, limit \\ 5) do
    recall(agent_id, limit: limit)
    |> Enum.map(fn m ->
      {x, y} = m.position
      "Tick #{m.tick}: felt #{m.affect_to} after #{m.reason} at (#{x},#{y})"
    end)
  end

  def clear(agent_id) do
    :ets.match_delete(@table, {agent_id, :_})
    :ok
  end
end
