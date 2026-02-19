# MODUS Sprint v7.9 — Next 5 Tasks

## Completed (v7.8)
- ✅ EventLog ETS table cleanup on reset — clear/0 + WorldChannel integration
- ✅ Snapshot diff API — StateSnapshots.diff/3 + WorldChannel "snapshot_diff" endpoint
- ✅ Ticker Observatory dirty flag — :persistent_term skip when no agent state changed
- ✅ Agent death cause tracking — :kill cast now logs :death with cause: "external_event"
- ✅ StateSnapshots delta compression — full state for latest 3, delta for older snapshots

## v7.9 Tasks

1. **[Bug] StateSnapshots reconstruct_snapshots delta reconstruction** — Currently deltas are returned as partial maps. Implement proper reconstruction by applying deltas against the nearest full snapshot base.

2. **[Feature] EventLog event expiry/TTL** — Add configurable max age for :event_log_by_tick entries. Prune events older than N ticks on each log insert (or every 100 inserts) to prevent unbounded growth even without reset.

3. **[Optimization] Ticker — batch PubSub broadcasts** — Instead of broadcasting every tick, batch non-critical updates (WorldHistory metrics, StoryEngine population) into a single message every 10 ticks to reduce PubSub overhead.

4. **[Feature] Agent death summary in WorldHistory** — Track death causes in WorldHistory era metrics (deaths_by_cause map). Enable "Why did the population decline?" analysis.

5. **[Optimization] SpatialIndex rebuild skip** — Track a spatial_dirty flag (set on agent position change). Skip SpatialIndex.rebuild() when no agents moved since last rebuild.
