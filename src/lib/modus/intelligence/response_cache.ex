defmodule Modus.Intelligence.ResponseCache do
  @moduledoc """
  ResponseCache — Situation-based LLM response cache with tick-based TTL.

  Hashes agent situation (needs + personality + context) to cache similar decisions.
  TTL = 100 ticks. Uses ETS for fast concurrent reads.
  """

  use GenServer

  @table :llm_response_cache
  @ttl_ticks 100
  @cleanup_interval_ms 30_000

  # ── Public API ──────────────────────────────────────────

  @doc "Look up cached response for a situation hash. Returns nil if miss."
  def get(situation_hash, current_tick) do
    case :ets.lookup(@table, situation_hash) do
      [{^situation_hash, response, cached_tick}] ->
        if current_tick - cached_tick < @ttl_ticks do
          Modus.Intelligence.LlmMetrics.record_cache_hit()
          response
        else
          :ets.delete(@table, situation_hash)
          Modus.Intelligence.LlmMetrics.record_cache_miss()
          nil
        end
      [] ->
        Modus.Intelligence.LlmMetrics.record_cache_miss()
        nil
    end
  rescue
    _ -> nil
  end

  @doc "Store a response with current tick."
  def put(situation_hash, response, current_tick) do
    :ets.insert(@table, {situation_hash, response, current_tick})
    :ok
  rescue
    _ -> :ok
  end

  @doc "Build a situation hash from agent state — bucketizes needs for cache hits."
  def situation_hash(agent) do
    # Bucketize needs to 10-unit ranges for better cache hits
    h = bucket(agent.needs.hunger)
    s = bucket(agent.needs.social)
    r = bucket(agent.needs.rest)
    # Personality is stable, use 0.1 buckets
    o = Float.round(agent.personality.openness, 1)
    e = Float.round(agent.personality.extraversion, 1)
    :erlang.phash2({h, s, r, o, e, agent.occupation})
  end

  @doc "Clear all cached responses."
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    _ -> :ok
  end

  # ── GenServer ───────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    table = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Cleanup done lazily on get(), but also do periodic sweep
    current_tick = try do
      Modus.Simulation.Ticker.current_tick()
    catch
      _, _ -> 0
    end

    if current_tick > 0 do
      min_tick = current_tick - @ttl_ticks
      :ets.select_delete(@table, [
        {{:_, :_, :"$1"}, [{:<, :"$1", min_tick}], [true]}
      ])
    end

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp bucket(val) when is_number(val), do: trunc(val / 10) * 10
  defp bucket(_), do: 0
end
