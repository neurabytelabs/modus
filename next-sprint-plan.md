# MODUS Sprint v7.8 — Next 5 Tasks

## Completed (v7.7)
- ✅ Agent ETS cleanup on termination — terminate/2 + trap_exit + StateSnapshots.cleanup
- ✅ ETS write_concurrency on agent_states_cache — reduced contention
- ✅ LiveDashboard telemetry metrics — tick duration + agent_count in ModusWeb.Telemetry
- ✅ EventLog ordered_set — :event_log_by_tick + since_tick/2 API for time-range queries
- ✅ StateSnapshots time-travel — ring buffer (10 snapshots/agent, every 100 ticks), WorldChannel endpoints

## v7.8 Tasks

1. **[Bug] EventLog ETS table cleanup on reset** — When simulation resets, :event_log_by_tick ordered_set grows unbounded. Add clear/0 function to truncate both ETS tables, call from World reset.

2. **[Feature] Snapshot diff API** — Add StateSnapshots.diff(agent_id, tick_a, tick_b) that returns changed fields between two snapshots. Useful for dashboard "what changed" view.

3. **[Optimization] Ticker — skip Observatory update if no agents changed** — Track a dirty flag (set on agent ETS write, cleared on Observatory update). Skip update_cache() when clean.

4. **[Feature] Agent death cause tracking** — When agent dies, store cause (starvation, conflict, old_age) in EventLog :death event data. Currently data is empty.

5. **[Optimization] StateSnapshots — compress old snapshots** — Only store full state for latest 3 snapshots; older ones store delta from previous. Reduces ETS memory for long-running simulations.
