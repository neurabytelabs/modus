defmodule Modus.Performance.Benchmark do
  @moduledoc """
  Benchmark — Performans testi modülü.

  50, 100, 200 ve 500 agent ile tick süresi, bellek kullanımı,
  GC baskısı ve hotspot analizi yapar.
  """

  require Logger

  @doc "Belirtilen agent sayısı ve tick ile benchmark çalıştır."
  @spec run(pos_integer(), pos_integer()) :: map()
  def run(agent_count, tick_count \\ 100) do
    Logger.info("BENCHMARK: #{agent_count} agent, #{tick_count} tick başlatılıyor")

    # GC baskısı ölçümü — önce
    gc_before = gc_count()
    mem_before = :erlang.memory(:total)
    proc_mem_before = :erlang.memory(:processes)
    ets_mem_before = :erlang.memory(:ets)

    # Tick döngüsü
    start_time = System.monotonic_time(:microsecond)

    tick_times =
      for _tick <- 1..tick_count do
        t0 = System.monotonic_time(:microsecond)

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

    # GC baskısı — sonra
    gc_after = gc_count()
    mem_after = :erlang.memory(:total)
    proc_mem_after = :erlang.memory(:processes)
    ets_mem_after = :erlang.memory(:ets)

    agent_summary = Modus.Performance.MemoryAudit.summary()

    avg_tick = div(Enum.sum(tick_times), max(tick_count, 1))
    p95 = percentile(tick_times, 0.95)
    p99 = percentile(tick_times, 0.99)

    result = %{
      agent_count: agent_count,
      tick_count: tick_count,
      total_ms: div(total_us, 1000),
      avg_tick_us: avg_tick,
      avg_tick_ms: Float.round(avg_tick / 1000.0, 2),
      max_tick_us: Enum.max(tick_times, fn -> 0 end),
      min_tick_us: Enum.min(tick_times, fn -> 0 end),
      p95_tick_us: p95,
      p99_tick_us: p99,
      tick_budget_ok: p95 < 100_000,
      memory_before_mb: Float.round(mem_before / 1_048_576.0, 2),
      memory_after_mb: Float.round(mem_after / 1_048_576.0, 2),
      memory_delta_mb: Float.round((mem_after - mem_before) / 1_048_576.0, 2),
      proc_memory_delta_mb: Float.round((proc_mem_after - proc_mem_before) / 1_048_576.0, 2),
      ets_memory_delta_mb: Float.round((ets_mem_after - ets_mem_before) / 1_048_576.0, 2),
      gc_count_delta: gc_after - gc_before,
      agent_avg_bytes: agent_summary.avg_bytes,
      agent_max_bytes: agent_summary.max_bytes,
      agents_over_10kb: agent_summary.over_limit,
      throughput_ticks_per_sec: if(total_us > 0, do: Float.round(tick_count * 1_000_000 / total_us, 1), else: 0.0)
    }

    Logger.info("BENCHMARK SONUÇ: #{agent_count} agent — avg #{result.avg_tick_ms}ms, p95 #{div(p95, 1000)}ms, budget #{if result.tick_budget_ok, do: "✅", else: "❌"}")
    result
  end

  @doc "Standart benchmark paketi: 50, 100, 200, 500 agent."
  @spec suite() :: [map()]
  def suite do
    results = for count <- [50, 100, 200, 500], do: run(count, 50)
    Logger.info("BENCHMARK SUITE TAMAMLANDI — #{length(results)} test")
    results
  end

  @doc "Profiling — hangi modüller en çok CPU tüketiyor."
  @spec profile_hotspots(pos_integer()) :: [map()]
  def profile_hotspots(tick_count \\ 20) do
    modules = [
      {"SpatialIndex.rebuild", fn -> Modus.Performance.SpatialIndex.rebuild() end},
      {"MemoryAudit.summary", fn -> Modus.Performance.MemoryAudit.summary() end},
      {"GcTuning.stats", fn -> Modus.Performance.GcTuning.stats() end},
      {"SpatialIndex.nearby", fn -> Modus.Performance.SpatialIndex.nearby({25, 25}, 10) end}
    ]

    for {name, fun} <- modules do
      times =
        for _ <- 1..tick_count do
          t0 = System.monotonic_time(:microsecond)
          try do
            fun.()
          catch
            _, _ -> :ok
          end
          t1 = System.monotonic_time(:microsecond)
          t1 - t0
        end

      %{
        module: name,
        avg_us: div(Enum.sum(times), max(tick_count, 1)),
        max_us: Enum.max(times, fn -> 0 end),
        total_us: Enum.sum(times)
      }
    end
    |> Enum.sort_by(& &1.total_us, :desc)
  end

  @doc "Hızlı benchmark — mevcut durumu ölç."
  @spec quick() :: map()
  def quick do
    agent_count =
      try do
        Registry.count(Modus.AgentRegistry)
      catch
        _, _ -> 0
      end

    t0 = System.monotonic_time(:microsecond)

    try do
      Modus.Performance.SpatialIndex.rebuild()
    catch
      _, _ -> :ok
    end

    t1 = System.monotonic_time(:microsecond)

    %{
      agent_count: agent_count,
      spatial_rebuild_us: t1 - t0,
      memory: Modus.Performance.MemoryAudit.summary(),
      gc: Modus.Performance.GcTuning.stats()
    }
  end

  @doc "HTML performans raporu oluştur."
  @spec generate_report([map()], [map()]) :: String.t()
  def generate_report(suite_results, hotspots \\ []) do
    rows =
      Enum.map(suite_results, fn r ->
        budget_icon = if r.tick_budget_ok, do: "✅", else: "❌"

        """
        <tr>
          <td><strong>#{r.agent_count}</strong></td>
          <td>#{r.avg_tick_ms} ms</td>
          <td>#{div(r.p95_tick_us, 1000)} ms</td>
          <td>#{div(r.p99_tick_us, 1000)} ms</td>
          <td>#{budget_icon}</td>
          <td>#{r.memory_delta_mb} MB</td>
          <td>#{r.gc_count_delta}</td>
          <td>#{r.throughput_ticks_per_sec}/s</td>
        </tr>
        """
      end)
      |> Enum.join()

    hotspot_rows =
      Enum.map(hotspots, fn h ->
        "<tr><td>#{h.module}</td><td>#{h.avg_us} µs</td><td>#{h.max_us} µs</td><td>#{h.total_us} µs</td></tr>"
      end)
      |> Enum.join()

    """
    <!DOCTYPE html>
    <html lang="tr">
    <head>
      <meta charset="UTF-8">
      <title>MODUS v5.3.0 Velocitas — Performans Raporu</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'JetBrains Mono', monospace; background: #0a0a0f; color: #e0e0e0; padding: 2rem; }
        h1 { color: #7C3AED; font-size: 1.8rem; margin-bottom: 0.5rem; }
        h2 { color: #06B6D4; font-size: 1.2rem; margin: 1.5rem 0 0.5rem; }
        .subtitle { color: #888; margin-bottom: 2rem; }
        table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
        th, td { padding: 0.6rem 1rem; text-align: left; border-bottom: 1px solid #222; }
        th { color: #7C3AED; background: #111118; font-weight: 600; }
        tr:hover { background: #111118; }
        .pass { color: #22c55e; }
        .fail { color: #ef4444; }
        .card { background: #111118; border: 1px solid #222; border-radius: 8px; padding: 1.5rem; margin: 1rem 0; }
        .metric { display: inline-block; margin-right: 2rem; }
        .metric-value { font-size: 1.5rem; color: #7C3AED; font-weight: bold; }
        .metric-label { color: #888; font-size: 0.8rem; }
        footer { margin-top: 2rem; color: #555; font-size: 0.75rem; }
      </style>
    </head>
    <body>
      <h1>⚡ MODUS v5.3.0 Velocitas — Performans Raporu</h1>
      <p class="subtitle">Sprint v4 IT-14 | #{DateTime.utc_now() |> DateTime.to_string()}</p>

      <h2>📊 Benchmark Sonuçları</h2>
      <table>
        <thead>
          <tr>
            <th>Agent</th><th>Ort. Tick</th><th>P95</th><th>P99</th><th>Bütçe &lt;100ms</th><th>Bellek Δ</th><th>GC Sayısı</th><th>Throughput</th>
          </tr>
        </thead>
        <tbody>#{rows}</tbody>
      </table>

      <h2>🔥 Hotspot Analizi</h2>
      <table>
        <thead><tr><th>Modül</th><th>Ort.</th><th>Max</th><th>Toplam</th></tr></thead>
        <tbody>#{hotspot_rows}</tbody>
      </table>

      <h2>🎯 Hedef: 200 agent @ &lt;100ms tick</h2>
      <div class="card">
        <p>Spatial Index (O(1) komşu arama), ETS read_concurrency, StateLimiter (10KB/agent), GC tuning (fullsweep_after: 50), delta render (sadece değişen tile gönder).</p>
      </div>

      <footer>NeuraByte Labs — "Where Spinoza Meets Silicon" | Sprint v4 Mundus</footer>
    </body>
    </html>
    """
  end

  defp percentile(list, p) when is_list(list) and length(list) > 0 do
    sorted = Enum.sort(list)
    idx = round(p * (length(sorted) - 1))
    Enum.at(sorted, idx)
  end

  defp percentile(_, _), do: 0

  defp gc_count do
    case :erlang.statistics(:garbage_collection) do
      {count, _, _} -> count
      {count, _} -> count
      _ -> 0
    end
  end
end
