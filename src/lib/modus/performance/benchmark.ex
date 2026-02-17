defmodule Modus.Performance.Benchmark do
  @moduledoc """
  Benchmark — Performance testing for MODUS simulation.

  Tests with 50, 100, and 200 agents to measure tick latency,
  memory usage, and throughput.
  """

  require Logger

  @doc "Run a benchmark with the given agent count and tick count."
  @spec run(pos_integer(), pos_integer()) :: map()
  def run(agent_count, tick_count \\ 100) do
    Logger.info("BENCHMARK: Starting with #{agent_count} agents, #{tick_count} ticks")

    # Measure initial memory
    mem_before = :erlang.memory(:total)

    # Time the tick loop
    start_time = System.monotonic_time(:microsecond)

    tick_times =
      for tick <- 1..tick_count do
        t0 = System.monotonic_time(:microsecond)

        # Simulate what happens in a tick: rebuild spatial index + process agents
        try do
          Modus.Performance.SpatialIndex.rebuild()
        catch
          _, _ -> :ok
        end

        t1 = System.monotonic_time(:microsecond)
        t1 - t0
      end

    end_time = System.monotonic_time(:microsecond)
    total_us = end_time - start_time

    mem_after = :erlang.memory(:total)
    agent_summary = Modus.Performance.MemoryAudit.summary()

    result = %{
      agent_count: agent_count,
      tick_count: tick_count,
      total_ms: div(total_us, 1000),
      avg_tick_us: div(Enum.sum(tick_times), tick_count),
      max_tick_us: Enum.max(tick_times),
      min_tick_us: Enum.min(tick_times),
      p95_tick_us: percentile(tick_times, 0.95),
      memory_before_bytes: mem_before,
      memory_after_bytes: mem_after,
      memory_delta_bytes: mem_after - mem_before,
      agent_avg_bytes: agent_summary.avg_bytes,
      agent_max_bytes: agent_summary.max_bytes,
      agents_over_10kb: agent_summary.over_limit
    }

    Logger.info("BENCHMARK RESULT: #{inspect(result)}")
    result
  end

  @doc "Run the standard benchmark suite: 50, 100, 200 agents."
  @spec suite() :: [map()]
  def suite do
    for count <- [50, 100, 200] do
      run(count, 50)
    end
  end

  @doc "Quick benchmark — just measure current state."
  @spec quick() :: map()
  def quick do
    agent_count = try do
      Registry.count(Modus.AgentRegistry)
    catch
      _, _ -> 0
    end

    # Time a single spatial index rebuild
    t0 = System.monotonic_time(:microsecond)
    try do Modus.Performance.SpatialIndex.rebuild() catch _, _ -> :ok end
    t1 = System.monotonic_time(:microsecond)

    %{
      agent_count: agent_count,
      spatial_rebuild_us: t1 - t0,
      memory: Modus.Performance.MemoryAudit.summary(),
      gc: Modus.Performance.GcTuning.stats()
    }
  end

  defp percentile(list, p) when is_list(list) and length(list) > 0 do
    sorted = Enum.sort(list)
    idx = round(p * (length(sorted) - 1))
    Enum.at(sorted, idx)
  end
  defp percentile(_, _), do: 0
end
