defmodule Modus.Intelligence.LlmMetrics do
  @moduledoc """
  LlmMetrics — ETS-backed metrics for LLM call tracking.

  Tracks: calls per tick, cache hits, latency, active model.
  Provides sparkline data for the last 50 ticks.
  """

  @table :llm_metrics
  @sparkline_table :llm_sparkline
  @max_sparkline 50

  # ── Setup ──────────────────────────────────────────────

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end

    if :ets.whereis(@sparkline_table) == :undefined do
      :ets.new(@sparkline_table, [:named_table, :public, :ordered_set, read_concurrency: true])
    end

    reset_tick_counters()
    :ok
  end

  # ── Recording ──────────────────────────────────────────

  @doc "Record an LLM API call with latency in ms."
  def record_call(latency_ms, model \\ nil) do
    :ets.update_counter(@table, :calls_this_tick, {2, 1}, {:calls_this_tick, 0})
    :ets.update_counter(@table, :total_calls, {2, 1}, {:total_calls, 0})

    # Track latency (running average)
    old_avg = get_counter(:avg_latency_ms)
    total = get_counter(:total_calls)
    new_avg = if total > 1, do: old_avg + (latency_ms - old_avg) / total, else: latency_ms * 1.0
    :ets.insert(@table, {:avg_latency_ms, new_avg})

    if model, do: :ets.insert(@table, {:active_model, model})
    :ok
  end

  @doc "Record a cache hit."
  def record_cache_hit do
    :ets.update_counter(@table, :cache_hits, {2, 1}, {:cache_hits, 0})
    :ets.update_counter(@table, :cache_lookups, {2, 1}, {:cache_lookups, 0})
    :ok
  end

  @doc "Record a cache miss."
  def record_cache_miss do
    :ets.update_counter(@table, :cache_lookups, {2, 1}, {:cache_lookups, 0})
    :ok
  end

  @doc "Called at end of each tick to snapshot and reset per-tick counters."
  def tick_snapshot(tick) do
    calls = get_counter(:calls_this_tick)
    # Store in sparkline
    :ets.insert(@sparkline_table, {tick, calls})
    # Prune old entries
    prune_sparkline(tick)
    # Reset per-tick
    :ets.insert(@table, {:calls_this_tick, 0})
    :ok
  end

  # ── Reading ────────────────────────────────────────────

  @doc "Get all metrics as a map for UI."
  def get_metrics do
    %{
      calls_this_tick: get_counter(:calls_this_tick),
      total_calls: get_counter(:total_calls),
      cache_hits: get_counter(:cache_hits),
      cache_lookups: get_counter(:cache_lookups),
      cache_hit_rate: cache_hit_rate(),
      avg_latency_ms: get_counter(:avg_latency_ms),
      active_model: get_value(:active_model, "none"),
      sparkline: get_sparkline()
    }
  end

  @doc "Get calls/tick sparkline as list of integers (last 50 ticks)."
  def get_sparkline do
    try do
      :ets.tab2list(@sparkline_table)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
      |> Enum.take(-@max_sparkline)
    rescue
      _ -> []
    end
  end

  def cache_hit_rate do
    hits = get_counter(:cache_hits)
    lookups = get_counter(:cache_lookups)
    if lookups > 0, do: Float.round(hits / lookups * 100.0, 1), else: 0.0
  end

  # ── Internals ──────────────────────────────────────────

  defp get_counter(key) do
    case :ets.lookup(@table, key) do
      [{^key, val}] -> val
      [] -> 0
    end
  rescue
    _ -> 0
  end

  defp get_value(key, default) do
    case :ets.lookup(@table, key) do
      [{^key, val}] -> val
      [] -> default
    end
  rescue
    _ -> default
  end

  defp reset_tick_counters do
    :ets.insert(@table, {:calls_this_tick, 0})
    :ok
  rescue
    _ -> :ok
  end

  defp prune_sparkline(current_tick) do
    min_tick = current_tick - @max_sparkline

    :ets.select_delete(@sparkline_table, [
      {{:"$1", :_}, [{:<, :"$1", min_tick}], [true]}
    ])
  rescue
    _ -> :ok
  end
end
