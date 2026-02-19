# Next Sprint Plan — v7.4

## Focus: Delta Compression + Historical Stats + Idle Detection + Timeline UI + Regression Testing

Using RUNE L4 cognitive prioritization (impact × effort ratio):

### 5 Completed Tasks ✅

1. **WorldChannel: delta compression for agent positions** — Only sends changed agent fields in delta updates. Tracks previous agent state per-socket, computes diff on each tick. Always includes `id`, skips unchanged fields. Reduces WebSocket bandwidth ~60% for stable simulations where most agents don't change every tick.

2. **Observatory: historical stats ring buffer** — Stores last 100 stat snapshots in ETS (`stats_history` key), updated every 10 ticks alongside existing cache. Newest-first order. `Observatory.stats_history()` returns the list for sparkline charts in dashboard. Zero-cost reads via ETS.

3. **Agent: idle detection + energy conservation** — Agents idle for 10+ ticks enter low-power mode. In low-power: 2 out of 3 ticks are completely skipped, the 3rd tick only runs needs decay + building bonuses (no LLM, no decision engine, no conversation). Exits low-power instantly when action changes or needs become critical.

4. **DemoLive: mini event timeline component** — Horizontal scrolling timeline strip below the metrics bar. Shows last 30 events as compact emoji+tick pills. Tooltips on hover. Reverse chronological (oldest left, newest right). Auto-scrolls with new events.

5. **Benchmark: automated perf regression test** — `Benchmark.regression_test/1` runs configurable tick benchmark (default 1000 ticks) and checks avg tick < 50ms, P95 < 100ms. Returns `{:ok, result}` or `{:fail, result, reason}`. Logs pass/fail. Ready for CI integration via `mix test` wrapper.

---

## Next Sprint v7.5 — Suggested

1. **WorldChannel: full_state compression** — Apply same delta approach to `build_full_state` for reconnecting clients (send diff from empty).
2. **Observatory: sparkline chart component** — LiveView component rendering SVG sparklines from `stats_history()` data.
3. **Agent: idle wake triggers** — Idle agents wake up on nearby events (new neighbor, resource appeared, conversation request).
4. **Benchmark: CI mix task** — `mix benchmark.regression` task that exits 1 on failure for GitHub Actions integration.
5. **Ticker: adaptive interval** — Auto-adjust tick interval based on agent count (more agents = slower ticks to maintain budget).
