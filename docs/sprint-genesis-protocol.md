# Sprint Genesis Protocol
> "Each thing, as far as it lies in itself, strives to persevere in its being." — Spinoza, Ethics III, Prop. 6
>
> The sprint chain perpetuates itself. Each ending is a beginning.

## What Is Sprint Genesis?

The final iteration of every sprint doesn't just polish — it **births the next sprint**.
This is the MODUS development process's own conatus: the drive to persist and improve.

## Protocol Steps (executed by Harmonia / final iteration)

### Phase 1: Retrospective (10 min)
```
1. Run: docker compose exec modus-app mix test --no-color
   → Record: total tests, passed, failed, skipped
   
2. Run: docker compose exec modus-app mix compile --warnings-as-errors --no-color
   → Record: errors, warnings
   
3. Read: CHANGELOG.md
   → Extract: features completed this sprint
   
4. Read: docs/overnight-sprint-v3.md (or current sprint spec)
   → Compare: planned vs completed
   → Calculate: completion rate (%)
   
5. Generate sprint report:
   - Duration, iterations completed
   - Features shipped (with commit hashes)
   - Test health (pass rate)
   - Compile health (warning count)
   - Completion rate
```

### Phase 2: Analysis (10 min)
```
6. Read: docs/ROADMAP.md
   → Identify: next priority backlog items
   
7. Read: recent memory files (memory/YYYY-MM-DD.md)
   → Check: any human requests or direction changes?
   
8. Analyze current codebase:
   - Module count: find src/lib -name "*.ex" | wc -l
   - Test count: grep -r "test " test/ | wc -l
   - LOC: find src/lib -name "*.ex" | xargs wc -l
   
9. Identify gaps:
   - Incomplete features from this sprint
   - Broken tests that need fixing
   - Missing @moduledoc
   - Performance concerns
```

### Phase 3: Planning (10 min)
```
10. Select 10-15 tasks for next sprint:
    - Priority 1: Fix anything broken from this sprint (max 2 iterations)
    - Priority 2: ROADMAP.md highest priority incomplete items
    - Priority 3: Human-requested features
    - Priority 4: Quality improvements (tests, docs, perf)
    
11. For each task, write:
    - Codename (Spinoza Latin term)
    - Version number (increment from current)
    - 8-12 concrete implementation steps
    - Files to modify
    - Test expectations
    
12. Save as: docs/sprint-v{N+1}-spec.md
```

### Phase 4: Scheduling (5 min)
```
13. Create cron jobs:
    - 1 hour intervals
    - Each job spawns a sub-agent with task spec
    - Delivery: announce to Telegram group
    - deleteAfterRun: true
    
14. First iteration starts 2 HOURS after Harmonia completes
    (grace period for human review/override)
    
15. Send sprint plan summary to Mustafa:
    - What was completed
    - What's planned next
    - Estimated duration
    - Budget estimate
    - "Reply PAUSE to halt, or sprint begins in 2h"
```

### Phase 5: Safeguards
```
16. Check chain depth:
    - Read: docs/sprint-chain-state.json
    - If chain_depth >= 3 → STOP, require human approval
    - Else → increment chain_depth, continue
    
17. Check budget:
    - Estimate: ~$0.50-1.00 per iteration (sub-agent + announce)
    - 15 iterations = ~$7.50-15.00
    - If cumulative > $30 → STOP, alert human
    
18. Quality gate:
    - If test pass rate < 70% → STOP
    - If compile errors > 0 → STOP (fix first)
    - If previous sprint completion < 50% → STOP (drift detected)
```

## File Structure

```
modus/
├── docs/
│   ├── ROADMAP.md                    # Long-term vision (human + AI maintained)
│   ├── sprint-genesis-protocol.md    # This file
│   ├── sprint-chain-state.json       # Chain tracking
│   ├── sprint-v3-spec.md            # Current sprint
│   ├── sprint-v4-spec.md            # Next sprint (generated)
│   └── reports/
│       ├── sprint-v3-report.html    # Sprint retrospective
│       └── sprint-v4-report.html
├── SPRINT_PAUSE                      # Touch this file to halt chain
└── BUDGET.json                       # Cost tracking
```

## sprint-chain-state.json Schema
```json
{
  "current_sprint": "v3",
  "chain_depth": 1,
  "max_chain_depth": 3,
  "sprints_completed": ["v1", "v2", "v3"],
  "total_iterations": 45,
  "total_estimated_cost": 22.50,
  "budget_limit": 30.00,
  "last_human_approval": "2026-02-17T15:00:00Z",
  "started_at": "2026-02-17T15:00:00Z",
  "paused": false
}
```

## BUDGET.json Schema
```json
{
  "daily_limit": 10.00,
  "sprint_limit": 15.00,
  "cumulative_limit": 30.00,
  "spent_today": 0.00,
  "spent_this_sprint": 0.00,
  "spent_total": 0.00,
  "last_reset": "2026-02-17"
}
```

## Human Override Commands
- **PAUSE**: Touch `SPRINT_PAUSE` file or send "PAUSE" in Telegram → halts chain
- **RESUME**: Remove `SPRINT_PAUSE` or send "RESUME" → continues from where it stopped
- **REDIRECT**: Update ROADMAP.md priorities → next sprint picks up changes
- **SKIP**: Send "SKIP IT-XX" → skips specific iteration
- **BUDGET**: Update BUDGET.json limits anytime

## Naming Convention
Sprint codenames follow Spinoza's philosophical evolution:
- v1: Genesis → Substantia (being)
- v2: Architectus → Amor (love/polish)
- v3: Veritas → Harmonia (truth to harmony)
- v4: Mundus series (world depth)
- v5: Anima series (soul/agent depth)
- v6: Imperium series (civilization)
- v7: Spectaculum series (experience)
- v8: Nexus Mundi series (connection)
