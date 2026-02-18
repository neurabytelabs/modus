# Sprint v4 — "Mundus" (World Depth)
> 18 Şubat 2026, 07:00-22:00 (15 iterations × 1h)
> "The world is not a thing, but a process." — Spinoza

## Philosophy
Sprint v3 made agents truly alive. Sprint v4 makes the WORLD truly alive.
Terrain, weather, paths, ruins — the world becomes a character itself.

## Current State: v3.8.0 Harmonia
- 92 modules, 505 tests (0 failures), 21,108 LOC
- 22 compile warnings (non-critical)
- Full agent intelligence: memory, planning, creativity, social structures
- Economy, crafting, ecology, LLM optimization
- Save/load, data dashboard, world language system
- Docker: modus-app + modus-llm

## Sprint v4 Goals
1. **Fix v3 gaps** — Compile warnings, undefined function refs
2. **Terrain generation** — Perlin noise, biomes, visual variety
3. **Water simulation** — Rivers and lakes form naturally
4. **Road/path system** — Agents create paths by walking
5. **Weather system** — Rain, snow, wind affecting gameplay
6. **Resource respawn** — Ecosystem-balanced regrowth
7. **Sleep cycles** — Day/night agent behavior
8. **Ruins & archaeology** — Dead civilizations leave traces
9. **Map zoom** — World → region → local views
10. **Divine Intervention UI** — God Mode command panel
11. **UI Overhaul** — Modern glassmorphism design system
12. **Quality pass** — Tests, docs, coverage
13. **Performance benchmark** — 200+ agents at 60fps
14. **Integration & Sprint Genesis** — Perpetual development

---

## IT-01 (07:00) — v4.0.1 Emendatio: Fix v3 Issues
**"Before building higher, strengthen the foundation"**

### Görevler
1. Fix `SaveManager.collect_wildlife/0` — calls undefined `Wildlife.get_all/0` → use `get_animals/0`
2. Fix `SaveManager.collect_economy/0` — calls undefined `Economy.prices/0`
3. Fix `SaveManager.collect_groups/0` — calls undefined `SocialEngine.list_groups/0` → use `get_groups/0`
4. Fix `Creativity.generate_story_llm/3` — calls undefined `AntigravityClient.simple_prompt/2` and `OllamaClient.simple_prompt/2`
5. Clean up 22 compile warnings (unused variables, ungrouped clauses)
6. Add @moduledoc to boilerplate modules (telemetry, router, endpoint, etc.)
7. Run full test suite, ensure 0 failures
8. Commit: v4.0.1

### Files
- `src/lib/modus/persistence/save_manager.ex`
- `src/lib/modus/mind/creativity.ex`
- `src/lib/modus/simulation/world_history.ex`
- `src/lib/modus/simulation/wildlife.ex`
- `src/lib/modus/simulation/story_engine.ex`
- `src/lib/modus_web/*.ex` (boilerplate moduledocs)

### Versiyon: v4.0.1 Emendatio ("correction")

---

## IT-02 (08:00) — v4.1.0 Territorium: Terrain Generation
**"The land shapes those who live upon it"**

### Görevler
1. Create `Modus.Simulation.TerrainGenerator` — Perlin noise algorithm (pure Elixir)
2. Biome types: forest, plains, desert, mountain, tundra, swamp, ocean
3. Temperature/moisture maps → biome assignment
4. Terrain stored in ETS `:modus_terrain` for fast reads
5. Integrate with World init — generate terrain on world creation
6. Visual: assign terrain colors/emoji per biome in renderer
7. Agent behavior: movement speed varies by terrain
8. Resource distribution tied to biome (fish near water, wood in forest)
9. Template presets: "Island", "Continent", "Archipelago", "Pangaea"
10. Tests: terrain generation, biome assignment, movement cost

### Files
- `src/lib/modus/simulation/terrain_generator.ex` (NEW)
- `src/lib/modus/simulation/world.ex`
- `src/lib/modus_web/channels/world_channel.ex`
- `src/test/modus/simulation/terrain_generator_test.exs` (NEW)

### Versiyon: v4.1.0 Territorium ("territory")

---

## IT-03 (09:00) — v4.2.0 Aqua: Water Flow Simulation
**"Water finds its own level"**

### Görevler
1. Create `Modus.Simulation.WaterSystem` — water flow from high to low terrain
2. River generation: trace paths from mountain to ocean using elevation
3. Lake formation: water pools in terrain depressions
4. Fishing spots along rivers and lakes
5. Water as movement barrier (agents need bridges or fords)
6. Irrigation bonus: farms near water grow faster
7. Seasonal: rivers flood in spring, dry in summer
8. Visual: blue tiles for water, animated flow direction
9. Water pollution from large settlements
10. Tests: river generation, lake detection, flood mechanics

### Files
- `src/lib/modus/simulation/water_system.ex` (NEW)
- `src/lib/modus/simulation/terrain_generator.ex`
- `src/lib/modus/simulation/resource.ex`
- `src/test/modus/simulation/water_system_test.exs` (NEW)

### Versiyon: v4.2.0 Aqua ("water")

---

## IT-04 (10:00) — v4.3.0 Via: Road & Path System
**"All roads are made by walking"**

### Görevler
1. Create `Modus.Simulation.PathSystem` — tracks agent movement patterns
2. Desire paths: frequently walked tiles become paths (ETS counter)
3. Path tiers: dirt trail (10+ walks) → road (50+) → highway (200+)
4. Movement speed bonus on paths (+20% trail, +50% road, +100% highway)
5. Path decay: unused paths slowly disappear
6. Visual: path overlay on terrain (brown lines)
7. Trade routes: paths between settlements get trade bonus
8. Bridge construction: agents can build bridges over water
9. Pathfinding: A* algorithm using terrain + path costs
10. Tests: path creation, tier upgrade, decay, bridge placement

### Files
- `src/lib/modus/simulation/path_system.ex` (NEW)
- `src/lib/modus/simulation/agent.ex`
- `src/lib/modus/simulation/building.ex`
- `src/test/modus/simulation/path_system_test.exs` (NEW)

### Versiyon: v4.3.0 Via ("road/path")

---

## IT-05 (11:00) — v4.4.0 Caelum: Weather System
**"Even the gods cannot control the weather"**

### Görevler
1. Create `Modus.Simulation.Weather` — dynamic weather engine
2. Weather types: clear, cloudy, rain, storm, snow, fog, wind, heatwave
3. Weather affects: movement speed, resource gathering, mood, crop growth
4. Season-linked probabilities (more rain in spring, snow in winter)
5. Micro-climates: desert = hot/dry, tundra = cold/snowy, forest = temperate
6. Weather events: hurricane, blizzard, drought (multi-tick duration)
7. Shelter bonus: agents in buildings unaffected by weather
8. Weather UI: icon + description in top bar
9. Weather forecast: 100-tick lookahead for planning agents
10. Tests: weather generation, effect calculations, season correlation

### Files
- `src/lib/modus/simulation/weather.ex` (NEW)
- `src/lib/modus/simulation/seasons.ex`
- `src/lib/modus/mind/planner.ex`
- `src/lib/modus_web/live/universe_live.ex`
- `src/test/modus/simulation/weather_test.exs` (NEW)

### Versiyon: v4.4.0 Caelum ("sky/weather")

---

## IT-06 (12:00) — v4.5.0 Renascentia: Resource Respawn & Balance
**"Nature always restores its balance"**

### Görevler
1. Rework `Modus.Simulation.Resource` — ecosystem-balanced respawn
2. Respawn rates tied to biome (forest: fast wood, plains: fast food)
3. Depletion zones: over-harvested areas go barren for 500 ticks
4. Soil fertility: farming depletes soil, rotation restores
5. Rare resources: gold/gems in mountains, herbs in swamps
6. Resource discovery: agents can find new resource veins
7. Carrying capacity: max resources per tile based on biome
8. Resource visual: density indicators (sparse → dense)
9. Season impact: winter reduces all regrowth by 50%
10. Tests: respawn rates, depletion, fertility, biome distribution

### Files
- `src/lib/modus/simulation/resource.ex`
- `src/lib/modus/simulation/terrain_generator.ex`
- `src/lib/modus/simulation/seasons.ex`
- `src/test/modus/simulation/resource_test.exs`

### Versiyon: v4.5.0 Renascentia ("rebirth/renewal")

---

## IT-07 (13:00) — v4.6.0 Somnus: Sleep Cycles & Daily Routine
**"Even the soul needs rest"**

### Görevler
1. Create `Modus.Simulation.DailyRoutine` — agent daily schedule
2. Sleep cycle: agents sleep at night (rest need drops to 0), wake at dawn
3. Nocturnal agents: some personalities prefer night activity
4. Energy system: activity drains energy, sleep restores
5. Morning routine: agents eat, plan, then work
6. Evening social: agents gather for conversation at dusk
7. Exhaustion: agents who don't sleep get mood/performance penalties
8. Buildings: houses required for quality sleep (outdoor = poor rest)
9. Dreams: sleeping agents occasionally have "dream" events (LLM)
10. Tests: sleep detection, energy drain/restore, routine scheduling

### Files
- `src/lib/modus/simulation/daily_routine.ex` (NEW)
- `src/lib/modus/simulation/agent.ex`
- `src/lib/modus/simulation/seasons.ex`
- `src/lib/modus/mind/mind_engine.ex`
- `src/test/modus/simulation/daily_routine_test.exs` (NEW)

### Versiyon: v4.6.0 Somnus ("sleep")

---

## IT-08 (14:00) — v4.7.0 Ruina: Ruins & Archaeology
**"Every civilization leaves its mark"**

### Görevler
1. Create `Modus.Simulation.Archaeology` — ruins and artifacts
2. Dead settlements become ruins (buildings decay over 2000 ticks)
3. Ruins contain artifacts: tools, writings, treasures
4. Exploration: agents can excavate ruins (skill-based)
5. Knowledge from ruins: old recipes, cultural traditions
6. Ancient landmarks: pre-generated ruins in new worlds
7. Ruin types: temple, fortress, village, monument
8. Haunted ruins: some have negative mood effects
9. Museum building: display artifacts for culture bonus
10. Tests: ruin creation, decay, excavation, artifact discovery

### Files
- `src/lib/modus/simulation/archaeology.ex` (NEW)
- `src/lib/modus/simulation/building.ex`
- `src/lib/modus/mind/creativity.ex`
- `src/test/modus/simulation/archaeology_test.exs` (NEW)

### Versiyon: v4.7.0 Ruina ("ruin")

---

## IT-09 (15:00) — v4.8.0 Conspectus: Map Zoom Levels
**"To see the forest AND the trees"**

### Görevler
1. Create zoom level system: World (1x) → Region (4x) → Local (16x)
2. World view: settlements as dots, terrain as colored blocks
3. Region view: individual buildings visible, agents as dots
4. Local view: full detail (current default)
5. Mini-map overlay: always visible in corner
6. Click-to-zoom: click area to zoom in
7. Keyboard: +/- keys for zoom, M for mini-map toggle
8. Performance: only render visible area at current zoom
9. Fog of war option: unexplored areas dimmed
10. Tests: zoom calculations, viewport, render culling

### Files
- `src/lib/modus_web/live/universe_live.ex`
- `src/lib/modus_web/channels/world_channel.ex`
- `assets/js/world_socket.js`
- `src/test/modus_web/zoom_test.exs` (NEW)

### Versiyon: v4.8.0 Conspectus ("overview/survey")

---

## IT-10 (16:00) — v4.9.0 Imperium: Divine Intervention UI
**"The gods watch, and sometimes they act"**

### Görevler
1. Create God Mode command panel — dropdown/modal with intervention options
2. Spawn events: earthquake, plague, treasure, meteor, flood, migration
3. Direct agent commands: move, speak, give item, change mood
4. World manipulation: change weather, season, time speed
5. Create/destroy buildings instantly
6. Spawn/remove agents
7. Resource manipulation: add/remove from area
8. Event chains: trigger cascading events
9. Command history: log of all divine interventions
10. Tests: command execution, validation, rollback

### Files
- `src/lib/modus_web/live/universe_live.ex`
- `src/lib/modus_web/channels/world_channel.ex`
- `src/lib/modus/simulation/world_events.ex`
- `src/test/modus/simulation/divine_intervention_test.exs` (NEW)

### Versiyon: v4.9.0 Imperium ("command/power")

---

## IT-11 (17:00) — v5.0.0 Forma: UI Design Overhaul ⭐ MAJOR
**"Beauty is the splendor of truth"**

### Görevler
1. Design system: consistent color palette, spacing, typography
2. Glassmorphism panels: frosted glass with blur backdrop
3. Agent detail redesign: tabbed view (Stats / Memory / Social / Goals)
4. Top bar redesign: compact, informative, beautiful
5. Sidebar navigation: collapsible panel list
6. Animation: smooth transitions, hover effects
7. Responsive: works on tablet screens
8. Dark/light theme toggle
9. Accessibility: keyboard navigation, focus indicators
10. Loading states: skeleton loaders for async data

### Files
- `src/lib/modus_web/live/universe_live.ex`
- `assets/css/app.css`
- `assets/js/world_socket.js`

### Versiyon: v5.0.0 Forma ("form/beauty") — MAJOR VERSION

---

## IT-12 (18:00) — v5.1.0 Sensus: Agent Aging & Appearance
**"Time writes its story on every face"**

### Görevler
1. Agent aging: visual progression (child → young → adult → elder)
2. Age-based abilities: children learn fast, elders have wisdom
3. Lifespan: agents live ~3000-5000 ticks (affected by lifestyle)
4. Appearance: emoji/icon changes with age
5. Age milestones: coming-of-age ceremony, elder council eligibility
6. Retirement: old agents reduce activity, share stories
7. Legacy: elder death creates memorial event
8. Generational knowledge: elders teach rare skills to young
9. Population pyramid: age distribution chart in observatory
10. Tests: aging, lifespan, milestone detection, knowledge transfer

### Files
- `src/lib/modus/simulation/agent.ex`
- `src/lib/modus/simulation/lifecycle.ex`
- `src/lib/modus/mind/learning.ex`
- `src/test/modus/simulation/aging_test.exs` (NEW)

### Versiyon: v5.1.0 Sensus ("perception/feeling")

---

## IT-13 (19:00) — v5.2.0 Probatio: Quality Pass
**"Trust, but verify"**

### Görevler
1. Run full test suite — fix any failures
2. Add missing tests for new modules (target: 600+ tests)
3. Test coverage measurement
4. @moduledoc audit: every module documented
5. Typespec audit: key public functions have @spec
6. Code cleanup: dead code removal, consistent formatting
7. mix format --check-formatted
8. Update README.md with Sprint v4 features
9. Error handling audit: no unhandled crashes
10. Documentation: architecture diagram update

### Files
- All test files
- All source files (@moduledoc, @spec)
- README.md
- docs/architecture.md

### Versiyon: v5.2.0 Probatio ("testing/proof")

---

## IT-14 (20:00) — v5.3.0 Velocitas: Performance Benchmark
**"Speed is the essence of war — and simulation"**

### Görevler
1. Benchmark suite: 50, 100, 200, 500 agents
2. Measure: tick time, memory usage, GC pressure
3. Profile hotspots: which modules consume most CPU
4. ETS optimization: read patterns, table sizes
5. Spatial indexing: grid-based lookup for nearby agents
6. Render optimization: only send changed tiles
7. Memory limits: enforce per-agent caps
8. Tick budget: target <100ms for 200 agents
9. Generate performance report (HTML/markdown)
10. Compare vs Sprint v3 baseline

### Files
- `src/lib/modus/performance/benchmark.ex`
- `src/lib/modus/simulation/ticker.ex`
- `src/lib/modus/simulation/world.ex`
- `docs/reports/sprint-v4-perf.md` (NEW)

### Versiyon: v5.3.0 Velocitas ("speed")

---

## IT-15 (21:00) — v5.4.0 Harmonia: Integration & Polish + Sprint Genesis 🔮
**"The whole is greater than the sum of its parts"**

### Görevler
1. Full integration test: all v4 systems working together
2. Edge case fixes: 0 agents, 1 agent, 200 agents with terrain+weather+paths
3. Memory leak check: 1000 tick monitoring
4. UI polish: all new panels consistent with design system
5. Error handling: no crashes reach the user
6. CHANGELOG.md update: all v4 changes documented
7. Final `mix test` → 0 failures
8. Docker rebuild + smoke test
9. Git tag v5.4.0 + push
10. **Sprint Genesis**: retrospective, analysis, plan Sprint v5 "Anima"
11. Create cron jobs for Sprint v5
12. Send sprint report to Mustafa

### Files
- CHANGELOG.md
- docs/sprint-v5-spec.md (GENERATED)
- docs/sprint-chain-state.json
- All source files (final fixes)

### Versiyon: v5.4.0 Harmonia ("harmony")

---

## Sprint v4 Version Map
```
v4.0.1 Emendatio    → Fix v3 issues
v4.1.0 Territorium  → Terrain generation
v4.2.0 Aqua         → Water simulation
v4.3.0 Via          → Road/path system
v4.4.0 Caelum       → Weather system
v4.5.0 Renascentia  → Resource respawn
v4.6.0 Somnus       → Sleep cycles
v4.7.0 Ruina        → Ruins & archaeology
v4.8.0 Conspectus   → Map zoom levels
v4.9.0 Imperium     → Divine intervention UI
v5.0.0 Forma        → UI overhaul (MAJOR)
v5.1.0 Sensus       → Agent aging
v5.2.0 Probatio     → Quality pass
v5.3.0 Velocitas    → Performance benchmark
v5.4.0 Harmonia     → Integration + Sprint Genesis
```

## Cron Pattern
- Each iteration: 1 hour
- First 45 min: implementation
- Last 15 min: bugfix + test + commit
- Docker rebuild test after each commit
- Full test suite every 5 iterations
