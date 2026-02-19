# Next Sprint Plan — v7.3

## Focus: Performance Caching + Observability + API Polish

Using RUNE L4 cognitive prioritization (impact × effort ratio):

### 5 Completed Tasks ✅

1. **Observatory: cache leaderboards & building_breakdown in ETS** — Previously recomputed on every UI call. Now cached alongside world_stats in ETS, updated every 10 ticks. Falls back to live computation if cache empty. O(1) reads for dashboard.

2. **Ticker: tick lag detection** — Logs a warning when tick processing duration exceeds the configured interval. Helps diagnose slow ticks caused by too many agents or expensive subsystems. Uses System.convert_time_unit for accurate ms measurement.

3. **SaveManager: parallel agent collection with Task.async_stream** — collect_agents now uses Task.async_stream with max_concurrency=10 instead of sequential Enum.reduce. 5s timeout per task with kill on timeout. Faster save/autosave for large worlds.

4. **LlmScheduler: public stats API** — New `LlmScheduler.stats()` returns busy state, last batch tick, total batches, and cache hit counts. Enables dashboard/telemetry integration without internal state exposure.

5. **EventLog: type filtering + counts_by_type** — `EventLog.recent(type: :birth)` now filters by event type. New `EventLog.counts_by_type()` returns frequency map for dashboard event breakdowns.

---

## Next Sprint v7.4 — Suggested

1. **WorldChannel: delta compression for agent positions** — Only send changed fields in delta updates (currently sends full agent state). Reduce WebSocket bandwidth ~60%.
2. **Observatory: historical stats ring buffer** — Store last 100 stat snapshots for sparkline charts in dashboard.
3. **Agent: idle detection + energy conservation** — Agents doing nothing for 10+ ticks should enter low-power mode (skip LLM, reduce tick processing).
4. **DemoLive: add mini event timeline component** — Visual timeline of births/deaths/conflicts below the map.
5. **Benchmark: automated perf regression test** — Run 1000-tick benchmark in CI, fail if avg tick > 50ms.
