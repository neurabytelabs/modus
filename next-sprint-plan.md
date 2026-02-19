# MODUS Sprint v7.7 — Next 5 Tasks

## Completed (v7.6)
- ✅ PubSub consolidation — single "modus:tick" topic (removed "simulation:ticks" duplication)
- ✅ Agent state ETS mirror — O(1) reads via :agent_states_cache, no GenServer.call blocking
- ✅ EventLog ETS read path — recent/1 and counts_by_type/0 read from ETS directly
- ✅ Ticker health metrics — consecutive lag tracking, :tick_lag events, health/0 API
- ✅ WorldChannel health endpoint — "get_ticker_health" returns ticker health + event counts

## v7.7 Tasks

1. **[Bug] Agent ETS cleanup on termination** — When agent dies/terminates, its entry remains in :agent_states_cache. Add terminate/2 callback to delete from ETS, or periodic sweep in Ticker.

2. **[Optimization] Batch ETS writes for agent states** — Currently each agent writes to ETS individually every tick. Batch into a single :ets.insert/2 call from Ticker after all agents processed to reduce ETS contention.

3. **[Feature] LiveDashboard integration** — Register :telemetry_metrics_summary for [:modus, :ticker, :tick] with custom LiveDashboard page showing agent count, tick duration, lag streak.

4. **[Optimization] EventLog ETS — ordered_set for time-range queries** — Switch from :set to :ordered_set keyed by tick number for efficient "events since tick N" queries.

5. **[Feature] Agent state snapshots for time-travel** — Store agent state snapshots every 100 ticks in ETS ring buffer (last 10). Enable "rewind" inspection from dashboard.
