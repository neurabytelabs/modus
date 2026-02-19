# Next Sprint Plan — v7.2

## Focus: Testing Infrastructure + Frontend Polish

Using RUNE L4 cognitive prioritization (impact × effort ratio):

### 5 Specific Tasks

1. **Add ETS-based read path for Observatory.world_stats()** — Currently calls GenServer.call on every agent to collect stats. Should read from ETS/Registry directly for O(1) reads instead of N GenServer calls. High impact on tick performance.

2. **Implement Phoenix.Presence for DemoLive** — Track connected demo viewers, show viewer count in the demo banner. Small feature, high engagement value.

3. **Add telemetry events to Ticker** — `:telemetry.execute` on each tick with duration, agent_count, tick_number. Enables LiveDashboard metrics without code changes.

4. **SaveManager: add slot metadata caching** — `list_slots` currently reads and decompresses all 5 slot files on every call. Cache metadata in GenServer state, invalidate on save/delete.

5. **Frontend: add keyboard shortcuts to DemoLive** — Arrow keys for map panning, +/- for zoom. Pure JS in DemoCanvas hook, no backend changes needed.
