defmodule Modus.Intelligence.LlmMetricsTest do
  use ExUnit.Case, async: false

  alias Modus.Intelligence.LlmMetrics

  setup do
    LlmMetrics.init()
    :ok
  end

  test "init creates ETS tables" do
    assert :ets.whereis(:llm_metrics) != :undefined
    assert :ets.whereis(:llm_sparkline) != :undefined
  end

  test "record_call increments counters" do
    LlmMetrics.record_call(150, "test-model")
    metrics = LlmMetrics.get_metrics()
    assert metrics.calls_this_tick >= 1
    assert metrics.total_calls >= 1
    assert metrics.active_model == "test-model"
  end

  test "cache hit rate tracks hits and misses" do
    LlmMetrics.record_cache_hit()
    LlmMetrics.record_cache_hit()
    LlmMetrics.record_cache_miss()
    rate = LlmMetrics.cache_hit_rate()
    # 2 hits out of 3 lookups (2 hit + 1 miss = 3 lookups, but hits also increment lookups)
    assert rate > 0
  end

  test "tick_snapshot stores sparkline data" do
    LlmMetrics.record_call(100)
    LlmMetrics.record_call(200)
    LlmMetrics.tick_snapshot(1)
    sparkline = LlmMetrics.get_sparkline()
    assert length(sparkline) >= 1
  end

  test "get_metrics returns complete map" do
    metrics = LlmMetrics.get_metrics()
    assert Map.has_key?(metrics, :calls_this_tick)
    assert Map.has_key?(metrics, :total_calls)
    assert Map.has_key?(metrics, :cache_hit_rate)
    assert Map.has_key?(metrics, :avg_latency_ms)
    assert Map.has_key?(metrics, :active_model)
    assert Map.has_key?(metrics, :sparkline)
  end
end
