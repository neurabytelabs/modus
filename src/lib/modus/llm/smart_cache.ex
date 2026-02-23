defmodule Modus.Llm.SmartCache do
  @moduledoc """
  Semantic similarity cache for LLM responses.

  Cache key: agent personality hash + mood + message_type hash
  TTL: 200 ticks
  """

  @table :modus_smart_cache
  @ttl 200

  @doc "Initialize the ETS table."
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ets.insert(@table, {:stats, 0, 0})
    :ok
  end

  @doc "Get a cached response. Returns {:ok, response} or :miss."
  def get(agent, mood, message_type) do
    key = cache_key(agent, mood, message_type)

    case :ets.lookup(@table, key) do
      [{^key, response, expire_tick}] ->
        current_tick = current_tick()

        if current_tick <= expire_tick do
          bump_hits()
          {:ok, response}
        else
          :ets.delete(@table, key)
          bump_misses()
          :miss
        end

      [] ->
        bump_misses()
        :miss
    end
  end

  @doc "Store a response in the cache."
  def put(agent, mood, message_type, response) do
    key = cache_key(agent, mood, message_type)
    expire_tick = current_tick() + @ttl
    :ets.insert(@table, {key, response, expire_tick})
    :ok
  end

  @doc "Get cache hit rate as a float 0.0-1.0."
  def hit_rate do
    case :ets.lookup(@table, :stats) do
      [{:stats, hits, misses}] ->
        total = hits + misses
        if total == 0, do: 0.0, else: hits / total

      _ ->
        0.0
    end
  end

  @doc "Clear all cached entries."
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
      :ets.insert(@table, {:stats, 0, 0})
    end

    :ok
  end

  defp cache_key(agent, mood, message_type) do
    personality_hash =
      if is_map(agent) and Map.has_key?(agent, :personality) do
        p = agent.personality
        :erlang.phash2({p.openness, p.conscientiousness, p.extraversion, p.agreeableness, p.neuroticism})
      else
        :erlang.phash2(agent)
      end

    {:smart_cache, personality_hash, mood, :erlang.phash2(message_type)}
  end

  defp bump_hits do
    :ets.update_counter(@table, :stats, {2, 1}, {:stats, 0, 0})
  rescue
    _ -> :ok
  end

  defp bump_misses do
    :ets.update_counter(@table, :stats, {3, 1}, {:stats, 0, 0})
  rescue
    _ -> :ok
  end

  defp current_tick do
    try do
      Modus.Simulation.Ticker.current_tick()
    catch
      _, _ -> 0
    end
  end
end
