# MODUS — Product Roadmap
> "Deus sive Natura" — God, or Nature. The simulation IS the philosophy.
> Last updated: 2026-02-17

## Vision
MODUS is a universe simulation platform where AI agents live, think, feel, and build civilizations.
The long-term goal: the most philosophically grounded, technically deep agent simulation on the web.

## Completed ✅

### Sprint v1 — Genesis to Substantia (Feb 15-16)
- [x] Core engine: Agent GenServer, BehaviorTree, Ticker, World
- [x] Pixi.js 2D renderer with camera controls
- [x] Phoenix LiveView onboarding wizard
- [x] Spinoza Mind Engine: Conatus, Affect, AffectMemory, ReasoningEngine
- [x] Cerebro: SocialNetwork, AgentConversation, SpatialMemory
- [x] Protocol Bridge: Perception, IntentParser, ContextBuilder
- [x] Economy: proximity barter, trade tracking
- [x] Lifecycle: birth/death, population balance
- [x] Multi-LLM: Antigravity (60+ models) + Gemini + Ollama

### Sprint v2 — Architectus to Amor (Feb 16-17)
- [x] Building system: 6 types, upgrades, neighborhoods
- [x] StoryEngine: narrative generation, timeline, chronicle export
- [x] Multi-Universe Dashboard: gallery, save/load, 11 templates
- [x] Agent Designer: custom creation, Big Five sliders
- [x] World Events: 7 types, God Mode triggers
- [x] Seasons & Day/Night: 4 seasons, 5 ambient phases
- [x] Rules Engine: 7 parameters, 5 presets
- [x] Agent Goals: 5 types, auto-assign by personality
- [x] Cultural Evolution: catchphrases, traditions, generational transfer
- [x] World History: eras, key figures, chronicle
- [x] Observatory Dashboard: charts, leaderboard, network graph
- [x] Export/Import/Share: JSON, share codes, screenshots
- [x] Landing page, Text Mode, Zen Mode

### Sprint v3 — Truly Alive (Feb 17, in progress)
- [x] IT-01 Veritas: Test stabilization (37→0 failures)
- [x] IT-02 Memoria: Deep agent memory (episodic, decay, recall)
- [ ] IT-03 Consilium: Agent planning & goal decomposition
- [ ] IT-04 Mercatura: Trade system, barter, supply/demand
- [ ] IT-05 Ars: Agent creativity, naming, oral tradition
- [ ] IT-06 Natura: Ecology, food chain, migration
- [ ] IT-07 Societas: Clans, leadership, alliances
- [ ] IT-08 Fabrica: Crafting & skill trees
- [ ] IT-09 Ratio: LLM optimization, caching, fallback chain
- [ ] IT-10 Optimum: Performance, spatial indexing, memory limits
- [ ] IT-11 Nexus: Communication v2, rumors, persuasion
- [ ] IT-12 Eventus: Dynamic events v2, chains, festivals
- [ ] IT-13 Speculum: Data dashboard, SVG charts
- [ ] IT-14 Persistentia: Auto-save, slots, seeds, crash recovery
- [ ] IT-NEW Lingua Mundi: World language system (TR/DE/FR/ES/JA)
- [ ] IT-15 Harmonia: Integration, polish, sprint genesis

## Backlog — Future Sprints 🔮

### Sprint v4 — "Mundus" (World Depth)
Priority: HIGH — makes the world feel real
- [ ] Terrain generation algorithms (Perlin noise, biomes)
- [ ] Water flow simulation (rivers, lakes form naturally)
- [ ] Road/path system (agents create paths by walking)
- [ ] Weather system (rain, snow, wind affecting gameplay)
- [ ] Resource respawn with ecosystem balance
- [ ] Day/night agent behavior (sleep cycles, nocturnal animals)
- [ ] Ruins & archaeology (dead civilizations leave traces)
- [ ] Map zoom levels (world → region → local)

### Sprint v5 — "Anima" (Agent Depth)
Priority: HIGH — makes agents feel alive
- [ ] Agent aging & appearance change
- [ ] Personality evolution (experiences change Big Five over time)
- [ ] Dreams & aspirations (LLM-generated long-term desires)
- [ ] Agent-written books/journals (stored in buildings)
- [ ] Teaching chains (master→apprentice knowledge transfer)
- [ ] Grief & mourning (death of friend affects behavior for 500+ ticks)
- [ ] Agent reputation system (famous/infamous)
- [ ] Generational storytelling (grandparent stories)

### Sprint v6 — "Imperium" (Civilization)
Priority: MEDIUM — emergent civilization
- [ ] Government types (democracy, monarchy, council)
- [ ] Laws & rules (agents vote on community rules)
- [ ] Currency system (from barter → coins → paper)
- [ ] War & diplomacy mechanics
- [ ] Religion & belief systems (emergent from culture)
- [ ] Architecture styles (civilization visual identity)
- [ ] Trade routes between settlements
- [ ] Population specialization (farming village, mining town)

### Sprint v7 — "Spectaculum" (Experience)
Priority: MEDIUM — user experience & polish
- [ ] Cinematic camera mode (follow agent, time-lapse)
- [ ] Agent family tree visualization
- [ ] World comparison mode (side-by-side simulations)
- [ ] Sound design (ambient, events, seasons)
- [ ] Tutorial/guided first experience
- [ ] Achievement system for worlds
- [ ] World leaderboard (most advanced civilization)
- [ ] Replay system (rewind simulation)

### Sprint v8 — "Nexus Mundi" (Multiplayer & Platform)
Priority: LOW (requires infrastructure)
- [ ] Multiplayer: shared world, each player controls agents
- [ ] World marketplace: share/download worlds
- [ ] API: programmatic world control
- [ ] Mobile companion app (watch your world)
- [ ] Mod system: custom agent behaviors
- [ ] Plugin architecture for new building/resource types
- [ ] Cloud hosting option (run simulation on server)

### Continuous — Always Relevant
- [ ] Test coverage > 80%
- [ ] Performance: 200+ agents at 60fps
- [ ] Documentation: all modules documented
- [ ] Accessibility: keyboard nav, screen reader
- [ ] Security: input sanitization, rate limiting
- [ ] Analytics: anonymous usage data for improvement

## Design Principles
1. **Flat 2D only** — no 3D, no WebGL shaders. Colored rectangles + emoji.
2. **ETS over GenServer** — read from ETS, write through GenServer
3. **Spinoza-aligned** — every feature should map to a philosophical concept
4. **Emergent over scripted** — behaviors arise from rules, not hardcoded scenarios
5. **Offline-first** — works without internet (Ollama fallback)
6. **Cost-conscious** — LLM calls are expensive, cache aggressively

## Sprint Genesis Protocol
When the final iteration of a sprint completes, it MUST:
1. Run full test suite, record pass/fail count
2. Analyze what was completed vs planned
3. Read this ROADMAP.md for next priorities
4. Check for human messages/requests since sprint started
5. Pick next 10-15 tasks from backlog (highest priority first)
6. Generate sprint spec document
7. Create cron jobs (1 hour intervals)
8. Send sprint plan to Mustafa for review
9. If no PAUSE within 2 hours, sprint begins automatically

### Safeguards
- **Max 3 consecutive sprint chains** without human approval
- **Budget cap**: $10/sprint (tracked in BUDGET.json)
- **Quality gate**: test pass rate must be > 70% to continue
- **SPRINT_PAUSE file**: if exists in project root, halt all sprints
- **Drift check**: compare sprint output vs ROADMAP alignment
