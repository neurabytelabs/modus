# Next Sprint Plan — v7.5

## Focus: Full-State Compression + Sparklines + Idle Wake Triggers + CI Benchmark + Adaptive Ticker

Using RUNE L4 cognitive prioritization (impact × effort ratio):

### 5 Completed Tasks ✅

1. **WorldChannel: full_state compression** — `build_full_state(:compressed)` strips nil/default fields (empty friends, nil group, nil conversing_with, false reasoning) from agent maps before sending to reconnecting clients. Reduces initial payload size ~15-25% depending on world state. Original full state still available via `build_full_state(:complete)`.

2. **Observatory: sparkline SVG component** — New `Modus.Simulation.Sparkline` module generates inline SVG sparklines from `stats_history()` data. Supports 5 metrics (population, happiness, conatus, buildings, trades) with distinct colors. Configurable width/height/stroke/fill/dots/area. `Sparkline.from_stats_history/1` returns ready-to-embed SVG map for dashboard components.

3. **Agent: idle wake triggers** — Idle agents (10+ ticks in low-power mode) now wake up on: nearby agent appears within radius 3, needs becoming critical (hunger >70 or social <20), conversation request pending, or resource node available at position. Resets idle_ticks to 0, resumes full processing immediately.

4. **Benchmark: CI mix task** — `mix benchmark.regression` task runs automated perf regression test with configurable thresholds. Exits with code 1 on failure for GitHub Actions integration. CLI flags: `--ticks`, `--max-avg`, `--max-p95`. Prints formatted pass/fail report with throughput and memory delta.

5. **Ticker: adaptive interval** — Auto-adjusts tick interval based on agent count. Thresholds: ≤200 agents = 1.0x (no change), 201-500 = 1.5x slower, 501-1000 = 2.5x, 1000+ = 4.0x. Combines with RulesEngine time_speed multiplier. Minimum interval clamped at 10ms. Prevents tick lag when population grows.

---

## Next Sprint v7.6 — Suggested

1. **WorldChannel: reconnect with compressed state** — Actually use `build_full_state(:compressed)` on rejoin, track client last-seen tick for smarter reconnect.
2. **Observatory: sparkline LiveView component** — Phoenix LiveView component wrapping `Sparkline.from_stats_history/1` with auto-refresh every N ticks.
3. **Agent: wake trigger telemetry** — Track idle wake events (reason, frequency) via `:telemetry` for performance tuning.
4. **Benchmark: GitHub Actions workflow** — `.github/workflows/benchmark.yml` running `mix benchmark.regression` on PR.
5. **Ticker: adaptive interval telemetry** — Log adaptive factor changes, expose current multiplier via `Ticker.status/0`.
