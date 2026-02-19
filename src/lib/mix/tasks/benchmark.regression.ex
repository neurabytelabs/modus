defmodule Mix.Tasks.Benchmark.Regression do
  @moduledoc """
  Mix task for automated performance regression testing.

  Runs `Benchmark.regression_test/1` and exits with code 1 on failure.
  Designed for CI integration (GitHub Actions).

  ## Usage

      mix benchmark.regression
      mix benchmark.regression --ticks 500 --max-avg 30 --max-p95 80

  ## v7.5 — Initial implementation
  """
  use Mix.Task

  @shortdoc "Run performance regression test (exits 1 on failure)"

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    opts = parse_args(args)

    IO.puts("\n⚡ MODUS Performance Regression Test")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("  Ticks:     #{Keyword.get(opts, :ticks, 1000)}")
    IO.puts("  Max avg:   #{Keyword.get(opts, :max_avg_ms, 50)}ms")
    IO.puts("  Max P95:   #{Keyword.get(opts, :max_p95_ms, 100)}ms")
    IO.puts("")

    case Modus.Performance.Benchmark.regression_test(opts) do
      {:ok, result} ->
        IO.puts("✅ PASSED — avg=#{result.avg_tick_ms}ms p95=#{div(result.p95_tick_us, 1000)}ms")
        IO.puts("   Throughput: #{result.throughput_ticks_per_sec} ticks/s")
        IO.puts("   Memory Δ: #{result.memory_delta_mb} MB")

      {:fail, result, reason} ->
        IO.puts("❌ FAILED — #{reason}")
        IO.puts("   avg=#{result.avg_tick_ms}ms p95=#{div(result.p95_tick_us, 1000)}ms")
        IO.puts("   Throughput: #{result.throughput_ticks_per_sec} ticks/s")
        System.halt(1)
    end
  end

  defp parse_args(args) do
    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [ticks: :integer, max_avg: :integer, max_p95: :integer],
        aliases: [t: :ticks]
      )

    opts = []
    opts = if parsed[:ticks], do: [{:ticks, parsed[:ticks]} | opts], else: opts
    opts = if parsed[:max_avg], do: [{:max_avg_ms, parsed[:max_avg]} | opts], else: opts
    opts = if parsed[:max_p95], do: [{:max_p95_ms, parsed[:max_p95]} | opts], else: opts
    opts
  end
end
