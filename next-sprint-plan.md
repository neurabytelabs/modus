# MODUS Sprint v7.3 — Next 5 Tasks

## Completed (v7.2)
- ✅ ETS-based read path for Observatory.world_stats()
- ✅ Phoenix.Presence for DemoLive viewer tracking
- ✅ Telemetry events in Ticker ([:modus, :ticker, :tick])
- ✅ SaveManager slot metadata caching
- ✅ DemoCanvas keyboard shortcuts (arrow pan, +/- zoom)

## v7.3 Tasks

1. **[Bug] Observatory.world_stats rescue on missing ETS table at boot** — Race condition: if world_stats() is called before Application.start inits the ETS table, ArgumentError. Add defensive `:ets.whereis` check or wrap in try/rescue consistently.

2. **[Optimization] Ticker batch PubSub — single broadcast per tick** — Currently broadcasts to `modus:tick` AND `simulation:ticks` separately. Consolidate into one topic with tagged messages to reduce PubSub overhead.

3. **[Feature] DemoLive mini-map toggle** — Add M key shortcut + UI button to toggle minimap in demo mode. Wire to renderer.toggleMinimap() already available.

4. **[Optimization] Agent state ETS mirror for read-heavy paths** — Agent.get_state/1 does GenServer.call. Mirror agent state to ETS on each tick for O(1) reads from Observatory, leaderboards, and export.

5. **[Feature] LiveDashboard telemetry panel for MODUS metrics** — Register `:telemetry_metrics_summary` for [:modus, :ticker, :tick] duration/agent_count. Add custom LiveDashboard page or metrics config.
