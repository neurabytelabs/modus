# MODUS Changelog

> "Each thing strives to persevere in its being" — Spinoza, Ethics III

Versioning follows Spinoza's philosophical evolution. Each release is a new mode of understanding.

---

## v2.0.0 · **Infinitum** — _Custom World Rules Engine_
_17 Şubat 2026_

### ✨ Features
- **Custom World Rules Engine** — 🎛️ ETS-backed configurable world parameters that affect simulation behavior in real-time
  - ⏱️ **Time Speed** (0.5x–3.0x) — Controls tick interval; higher = faster simulation
  - 🌾 **Resource Abundance** (Scarce/Normal/Abundant) — Affects resource availability
  - ⚠️ **Danger Level** (Peaceful/Moderate/Harsh/Extreme) — World hostility
  - 💬 **Social Tendency** (0.0–1.0) — How social agents are
  - 👶 **Birth Rate** (0.0–2.0x) — Population growth multiplier
  - 🏗️ **Building Speed** (0.5–3.0x) — Construction rate multiplier
  - 🧬 **Mutation Rate** (0.0–1.0) — Personality variance on birth (children inherit + mutate parent traits)
- **5 Presets** — Quick configuration bundles:
  - 🕊️ Peaceful Paradise — Abundant resources, high birth rate, fast building
  - 💀 Harsh Survival — Scarce resources, extreme danger, low birth rate
  - 🌪️ Chaotic — Fast time, high mutation, harsh environment
  - ✨ Utopia — Abundant, peaceful, highly social, zero mutation
  - 🧪 Evolution Lab — Max speed, high birth & mutation rates
- **Rules Panel** — Modal with sliders/dropdowns, accessible via 🎛️ top bar button
- **Preset Display** — Active preset name shown in top bar (amber badge)
- **Instant Apply** — All rule changes take effect immediately, no restart needed
- **Save with World** — Rules state included in world save/load via WorldChannel

### 🏗️ Architecture
- New module: `Modus.Simulation.RulesEngine` — ETS table `:modus_rules_engine`, PubSub broadcast on change
- `Ticker` — `schedule_tick/1` applies `time_speed` multiplier to tick interval
- `Lifecycle` — Birth check interval scaled by `birth_rate`; children inherit parent personality with `mutation_rate` variance via `Agent.new_custom/5`
- `WorldChannel` — `get_rules`, `update_rules`, `apply_preset` handlers; rules in full_state + delta; PubSub subscription for `modus:rules`
- `UniverseLive` — Rules modal UI, preset buttons, slider controls, top bar preset badge
- `Application` — `RulesEngine.init()` called at startup

### 🧪 Tests
- 7 new tests: init defaults, update, apply_preset, unknown preset, accessors, serialize, preset_names

---

## v1.9.1 · **Tempus** — _Seasons & Day/Night_
_17 Şubat 2026_

### ✨ Features
- **Four Seasons Cycle** — Spring→Summer→Autumn→Winter, ~1000 ticks each (full year = 4000 ticks)
  - 🌸 Spring: +50% growth, green tint, joy boost
  - ☀️ Summer: agents tire faster (+30% hunger/rest drain), gold tint
  - 🍂 Autumn: harvest season, orange tint, slight melancholy
  - ❄️ Winter: scarce resources (+50% hunger drain), blue-white tint, survival mode
- **Season Indicator** — Top bar shows current season emoji + name + year counter (Y1, Y2...)
- **Terrain Color Shifts** — Flat tile colors change per season (grass goes green→green→gold→frosty white, etc.)
- **Season Tint Overlay** — Subtle flat 2D color overlay per season (no 3D effects)
- **Day/Night Ambient Phases** — 5 phases: dawn (amber), day (bright), dusk (purple), night (dark blue), pre-dawn
  - Server-driven ambient color + alpha for smooth transitions
- **Season Change Toast** — "🌸 Spring has arrived!" notification on season transitions
- **Season Story Events** — Timeline narrative entries with Spinoza-flavored prose for each season change
- **Agents Reference Seasons** — LLM context builder injects current season + time of day into agent prompts

### 🏗️ Architecture
- `Seasons` — New GenServer: season lifecycle, PubSub broadcast, serialization for client
- `Environment` — Enhanced with 5 day phases + server-computed ambient color/alpha
- `ContextBuilder` — `season_context/0` injects season + time info into agent chat prompts
- `StoryEngine` — `:season_change` narrative generation
- `WorldChannel` — Season data in delta + full_state, season_change push event
- `Renderer` — Season tint overlay layer, terrain_shift color map, ambient color from server
- `WorldSocket` — `onSeasonChange` callback for live season transitions

---

## v1.9.0 · **Tempus** — _World Events Engine_
_17 Şubat 2026_

### ✨ Features
- **World Events Engine** — 7 event types: 🌩️ Storm, 🌍 Earthquake, ☄️ Meteor Shower, 🦠 Plague, ✨ Golden Age, 🌊 Flood, 🔥 Fire
- **Event Properties** — Each event has duration (ticks), severity (1-3), affected area (radius), and unique effects
- **Random Triggers** — 1% chance per 100 ticks for a random world event to spawn naturally
- **God Mode: Trigger Event** — 7-button grid in God Mode panel to manually trigger any world event
- **Event Effects** — Terrain changes (fire→desert, flood→water), building damage, agent mood/need shifts
- **Ongoing Effects** — Active events continue affecting agents each 10 ticks (plague drains hunger, fire drains rest, golden age heals)
- **2D Color Overlays** — Flat circle overlays on the map: red=fire, blue=flood, grey=storm, gold=golden age, etc.
- **Overlay Fade** — Overlays pulse/fade as event duration expires
- **Toast Notifications** — World events trigger toast popups with severity level ("Minor/Severe/Catastrophic")
- **StoryEngine Integration** — All world events generate narrative timeline entries with Spinoza-flavored prose
- **Building Damage** — Destructive events (earthquake, fire, flood, storm, meteor) damage buildings in radius; buildings destroyed at 0 HP

### 🏗️ Architecture
- `WorldEvents` — New GenServer: event lifecycle, random triggers, effect application, terrain mutation, building damage
- `Building.damage/2` — New function for direct HP reduction with auto-removal at 0
- `Ticker` — Calls `WorldEvents.tick/1` each tick
- `StoryEngine` — `:world_event` narrative generation with severity-based prose
- `WorldChannel` — `trigger_world_event`, `get_world_events` handlers; world_events in delta + full_state; PubSub subscription for live event/expiry push
- `WorldSocket` — `triggerWorldEvent()`, `onWorldEvent`/`onWorldEventEnded` callbacks
- `Renderer` — `updateWorldEvents()` flat 2D circle overlays, `removeWorldEvent()` cleanup, `worldEventsLayer` between buildings and agents
- `UniverseLive` — `trigger_world_event` event handler, `world_event_toast` for client-pushed toasts, 7-button God Mode grid

---

## v1.8.1 · **Architectus** — _Neighborhoods_
_17 Şubat 2026_

### ✨ Features
- **Building Upgrades** — Hut (L1) → House (L2) → Mansion (L3). Requires owner + conatus > 0.7 + 500 ticks age. Visual: size scales (1x/1.3x/1.6x), color shifts (brown→tan→gold), level badge on map
- **Mansion Type** — New top-tier home: 🏛 gold, 22x22px, rest+25/shelter+20/social+5 bonuses
- **Neighborhoods** — 3+ buildings within 5 tiles auto-cluster into named neighborhoods (deterministic name from position: "Green Hill", "Oak Meadow", etc.)
- **Neighborhood Labels** — 🏘️ labels rendered on map at cluster center (flat 2D text, drop shadow)
- **Neighborhood Social Bonus** — Residents get +0.02 social/tick passive bonus
- **Build Near Friends** — Agents prefer building 1-2 tiles from a friend's home (SocialNetwork check)
- **Home Benefit** — Agents with rest > 60 and a home return to it (go_home behavior)
- **Upgrade Behavior** — BehaviorTree evaluates upgrade opportunity (30% chance per tick when eligible)
- **Story Events** — Narrative entries for building upgrades (⬆️) and neighborhood formation (🏘️)
- **Level Multiplier** — Area bonuses scale with building level: L2=1.5x, L3=2x

### 🏗️ Architecture
- `Building` — Upgrade system (can_upgrade?/upgrade/upgrade_cost), neighborhood detection (greedy clustering), serialize_neighborhoods, friend_build_position, :mansion type + costs/bonuses/emoji/colors/sizes
- `Building` — New ETS table :neighborhoods for cluster storage
- `BehaviorTree` — Added :upgrade_home action with conatus/tick/inventory checks
- `DecisionEngine` — :upgrade_home resolver
- `Agent` — :upgrade_home apply_action, apply_neighborhood_bonus/1, build-near-friends in :build action
- `Ticker` — Neighborhood detection every 100 ticks, fires :neighborhood_formed events for new clusters
- `WorldChannel` — Neighborhoods in full_state and delta broadcasts
- `StoryEngine` — Narratives + emojis for :building_upgrade and :neighborhood_formed
- `Renderer` — Level-aware building rendering (re-render on upgrade), neighborhood label layer

---

## v1.8.0 · **Architectus** — _Building System_
_17 Şubat 2026_

### ✨ Features
- **Building System** — 6 building types: Hut 🛋, House 🏠, Farm 🌾, Market 🏪, Well 🪣, Watchtower 🗼
- **Resource Costs** — Buildings require gathered wood/stone (Hut: 5 wood, House: 10 wood + 5 stone, etc.)
- **Agent Build Behavior** — Agents with conatus > 0.6, no home, and sufficient resources auto-build
- **Area Bonuses** — Buildings provide passive need bonuses to nearby agents (rest, shelter, hunger, social)
- **Building Decay** — Unowned buildings lose 0.5 health per 100 ticks, destroyed at 0
- **God Mode Placement** — Place any building type via World Builder palette
- **2D Flat Rendering** — Colored rectangles with emoji overlays, health bars (FLAT 2D, no 3D)
- **Building Broadcast** — Buildings included in full_state and delta channel pushes

### 🏗️ Architecture
- New module: `Modus.Simulation.Building` — ETS-backed building storage, cost/bonus system
- `BehaviorTree` — Added `:build` and `:go_home` actions with conatus/inventory checks
- `DecisionEngine` — Resolves build (at position) and go_home (move to home building)
- `Agent` — `apply_action(:build)` deducts resources, places building, logs event
- `Agent` — `apply_building_bonuses/1` applies area bonuses each tick
- `Ticker` — Decays unowned buildings every 100 ticks
- `WorldChannel` — Buildings in full_state/delta, God Mode `place_building` handler
- `Renderer` — New building layer with colored rects + emoji + health bars
- `WorldSocket` — `placeBuilding()` client method
- `UniverseLive` — Building brush palette in World Builder

---

## v1.7.1 · **Nexus** — _Universe Templates Gallery_
_17 Şubat 2026_

### ✨ Features
- **11 World Templates** — Expanded from 4 to 11: Village 🏘️, Island 🏝️, Desert 🏜️, Space 🚀, Underwater 🌊, Medieval 🏰, Cyberpunk 🌃, Jungle 🌴, Arctic ❄️, Volcanic 🌋, Cloud City ☁️
- **Data-Driven Templates** — New `WorldTemplates` module defines terrain distribution, resource density, danger level, default occupations, wildlife types, and difficulty per template
- **8×8 Terrain Preview** — Each template card shows a hand-crafted 8×8 color grid thumbnail (upgraded from 5×5)
- **Difficulty Badge** — Easy/Medium/Hard/Extreme label with color coding on each card
- **Scrollable Gallery** — 3-column responsive grid with scroll for 11+ templates
- **Template API** — `WorldTemplates.all/0`, `get/1`, `get!/1`, `thumb_color/2`, `difficulty_badge/1`

### 🧠 Architecture
- New `Modus.Simulation.WorldTemplates` module — single source of truth for all template data
- Removed hardcoded `@templates` and `terrain_thumb_color/2` from LiveView
- Dashboard thumbnails upgraded to 8×8 grid using `WorldTemplates.thumb_color/2`
- Template cards now show preview grid + emoji + name + description + difficulty

### 🧪 Files Modified
- `world_templates.ex` — NEW: data-driven template definitions (11 templates)
- `universe_live.ex` — Refactored to use WorldTemplates module, 8×8 previews, scrollable gallery

---

## v1.7.0 · **Nexus** — _Multi-Universe Dashboard_
_17 Şubat 2026_

### ✨ Features
- **Universe Gallery** — 🌍 dashboard as the new landing page when saved worlds exist
- **World Cards** — Each saved universe shows: name, 5×5 flat terrain color grid thumbnail, population count, tick age, save date
- **Create New Universe** — Prominent ➕ card flows into existing onboarding wizard
- **Click to Load** — ▶ Play button on any card loads the universe and enters simulation
- **Delete with Confirmation** — 🗑️ button triggers inline confirmation overlay before deletion
- **Sort Controls** — Sort by newest, oldest, or most populated
- **🌍 Top Bar Button** — Return to Universe Gallery from active simulation
- **Back to Gallery** — Onboarding wizard includes "← Back to Universe Gallery" link

### 🧠 Architecture
- New `:dashboard` phase added before `:onboarding` — shown when saved worlds exist
- `dashboard_worlds`, `dashboard_sort`, `dashboard_delete_confirm` assigns in LiveView state
- `sort_worlds/2` helper for client-side sorting by date or population
- `terrain_thumb_color/2` generates deterministic 5×5 2D flat color grids per template type (village/island/desert/space)
- Reuses existing `WorldPersistence.list/0`, `load/1`, `delete/1` — zero new persistence code
- Seamless phase transitions: dashboard → onboarding → simulation → dashboard

### 🧪 Files Modified
- `universe_live.ex` — Dashboard phase, gallery UI, sort/delete/load handlers, terrain thumbnail helpers

---

## v1.6.1 · **Creator** — _Agent Designer_
_17 Şubat 2026_

### ✨ Features
- **Agent Designer Panel** — ➕🧑 button in top bar opens left-panel designer
- **Custom Agent Creation** — Name, occupation (10 types), personality (Big Five sliders 0-100), starting mood (happy/calm/anxious/eager)
- **Click-to-Place** — Design agent → click "Place on Map" → click map tile to spawn
- **Animal Spawning** — Switch to Animal mode to place deer 🦌, rabbit 🐇, or wolf 🐺
- **Agent.new_custom/5** — New constructor accepting custom personality map and mood
- **WorldChannel handlers** — `spawn_custom_agent` and `spawn_animal` with full validation
- **WorldSocket.spawnCustomAgent/spawnAnimal** — JS client methods for channel communication
- **Live placement mode** — Crosshair cursor, click intercept, auto-reset after placement

### 🧠 Architecture
- Agent Designer state managed in LiveView (designer_name, designer_o/c/e/a/n sliders, etc.)
- `designer_place_mode` push_event triggers JS click intercept on renderer
- Custom agents join simulation immediately with specified Big Five traits mapped to 0.0-1.0
- Mood mapping: happy→joy, calm→neutral, anxious→fear, eager→desire
- Animals spawn as agents with animal-appropriate personality profiles

### 🧪 Files Modified
- `universe_live.ex` — Designer UI panel, state, event handlers
- `world_channel.ex` — spawn_custom_agent, spawn_animal handlers
- `agent.ex` — new_custom/5 constructor
- `world_socket.js` — spawnCustomAgent, spawnAnimal methods
- `app.js` — Designer place mode click intercept

---

## v1.4.0 · **Potentia** — _"By reality and perfection I mean the same thing"_
_17 Şubat 2026_

### ✨ Features
- **StoryEngine** (`simulation/story_engine.ex`) — Automatic narrative generation from simulation events
- **Timeline View** — Left panel timeline showing notable world events with Spinoza-flavored prose
- **Toast Notifications** — Real-time event notifications that slide in from the right
- **Chronicle Export** — Export the world's full history as beautifully formatted markdown
- **Population Stats Dashboard** — Bar graph visualization of population over time + summary stats
- **Population Tracking** — Ticker records population snapshots every 10 ticks

### 🧠 Architecture
- StoryEngine subscribes to EventLog PubSub for automatic event processing
- Notable events (birth, death, disaster, migration, conflict, trade) trigger toast notifications
- Chronicle maintains up to 500 entries, population history up to 1000 data points
- Story PubSub topic (`"story"`) for real-time toast delivery to LiveView

### 🧪 Tests
- 6 new tests: chronicle, timeline, population history, markdown export, narrative generation, event filtering

---

## v1.1.0 · **Harmonia** — _"All things are in God, and everything happens solely through the laws of the infinite nature of God"_
_16 Şubat 2026_

UI/UX polish + performance optimizations — balance and harmony in the interface.

### New Features
- **Mini-map** (top-right corner) — Real-time overview of world with agent dots and viewport rectangle. Toggle with `M` key
- **Tooltips** — Hover over any agent to see name, current action, friend count, and group info
- **Keyboard shortcuts** — `Space`=pause/play, `1/5/0`=speed, `M`=minimap, `B`=mind view, `Esc`=deselect agent
- **Shortcut hints** — Bottom-left help text shows all available keyboard shortcuts

### Performance
- **Minimap rendering** — Throttled to every 3 frames to maintain 60fps with 50 agents
- **Terrain caching** — Minimap terrain drawn once and cached, only agent dots update per frame
- **Sprite data caching** — Agent data map optimized for O(1) lookups during relationship line drawing

### Improvements
- Version bump to v1.1.0 Harmonia in top bar
- Tooltip auto-positions to stay within screen bounds
- Minimap viewport rectangle tracks camera pan/zoom in real-time

---

## v1.0.0 · **Substantia** — _"God is the immanent, not the transitive, cause of all things"_
_16 Şubat 2026_

Economy, lifecycle, and population balance — the simulation becomes self-sustaining.

### New Modules
- **Economy** (`simulation/economy.ex`) — Proximity-based barter system: resource transfer between agents, auto-trade for hungry agents near traders/farmers
- **Lifecycle** (`simulation/lifecycle.ex`) — Birth/death dynamics: two joyful agents (joy + conatus > 0.7) nearby spawn new agent; population balanced at 8-15
- **WorldSystems** (`simulation/world_systems.ex`) — Tick coordinator for economy and lifecycle systems

### Improvements
- **Top bar economy indicators** — Trades 🤝, Births 👶, Deaths 💀 counters in navigation bar
- **Death tracking** — Agent deaths now recorded in lifecycle stats via ETS
- **Population balance** — Birth only when pop < 15, forced birth when pop < 8, natural death via conatus

### Architecture
- ETS-based stats (no GenServer blocking for reads)
- Economy tick every 10 ticks, lifecycle check every 50 ticks
- WorldSystems GenServer subscribes to simulation PubSub

### Tests
- 6 new tests (Economy + Lifecycle)

---

## v0.5.0 · **Libertas** — _"Freedom is the recognition of necessity"_
_16 Şubat 2026_

Agent Protocol Bridge — agents now perceive, understand, and act with real context.

### New Modules
- **Perception Engine** (`mind/perception.ex`) — Real-time agent perception snapshots (position, terrain, nearby agents with relationship data, needs, affect)
- **Social Insight** (`mind/cerebro/social_insight.ex`) — Converts ETS social network into human-readable Turkish text for LLM context
- **Intent Parser** (`protocol/intent_parser.ex`) — Keyword-based user message classification: chat, queries (location/status/relationships), commands (move/stop)
- **Context Builder** (`mind/context_builder.ex`) — Dynamic LLM system prompt enrichment with real agent state, perception, social context
- **Protocol Bridge** (`protocol/bridge.ex`) — Orchestrator: routes user messages through intent parsing → context enrichment → LLM/direct response

### Improvements
- **Chat now uses Protocol Bridge** — WorldChannel routes through Bridge.process/2 instead of direct LLM calls
- **Location queries return real data** — "Neredesin?" returns actual coordinates and terrain
- **Status queries return real state** — "Nasılsın?" returns real conatus energy and affect
- **Movement commands work** — "Kuzeye git" actually moves the agent
- **Enriched LLM prompts** — Agents know their real position, nearby agents, relationships, and terrain

### Tests
- 12 new tests (IntentParser, Perception, SocialInsight)
- 128 total tests

---

## v0.4.0 · **Cerebro** — _"The mind is the idea of the body"_
_16 Şubat 2026_

Social intelligence: agents form relationships, converse, and remember spatial experiences.

---

## v0.3.0 · **Affectus** — _"The body's power of action is increased or diminished"_
_16 Şubat 2026_

The agents gained an inner world. They feel, remember, and reason.

### 🧠 Mind Engine (Phase 2)
- **Conatus Energy** — each agent has a will-to-persist (0.0→1.0), affected by success/failure
- **Affect State Machine** — 5 emotional states (😊 joy, 😢 sadness, 🔥 desire, 😨 fear, 😐 neutral)
- **Affect Memory** — ETS-based episodic memory, agents remember emotional experiences
- **Memory Decay** — old memories fade (entropy), strong emotions persist longer
- **LLM Reasoning Cycle** — persistently sad agents trigger LLM reasoning: "Why am I sad?"
- **Spatial Memory** — agents recall emotions tied to locations, influencing movement

### 🎨 Visual
- Agent colors shift by affect state (gold/blue/green/red/grey)
- Conatus energy bar under each agent
- 💭 emoji on agents currently reasoning
- Memory timeline in detail panel with salience scores

### 📊 Stats
- 28+ modules · 100+ tests · 6 architecture layers
- Spinoza Validation: Conatus 0.92 / Ratio 0.88 / Overall 0.89 (Grade A)

---

## v0.2.0 · **Conatus** — _"Each thing strives to persevere in its being"_
_16 Şubat 2026 (earlier)_

Multi-LLM intelligence and demo-ready polish.

### 🚀 Features
- **Multi-LLM Provider** — runtime switching between Ollama (local) and Antigravity (60+ models)
- **Settings UI** — provider/model selector, test connection, save
- **Chat System** — talk to agents via LLM, personality-aware responses
- **World Save/Load** — SQLite persistence via Ecto
- **Active Agents** — BehaviorTree with lowered thresholds, <5% idle rate
- **Agent Detail Panel** — needs bars, personality radar, relationships, event history
- **Action Emojis** — 🧭🌾💬😴🍖 on agent sprites

### 🔧 Infrastructure
- Antigravity gateway auto-detection on startup
- Finch connection pool (10×3=30)
- Docker compose with host.docker.internal bridge

---

## v0.1.0 · **Genesis** — _"In the beginning was Substance"_
_15-16 Şubat 2026_

The world was born. 8 overnight iterations created the foundation.

### 🌍 Core
- **Agent GenServer** — BEAM process per agent, Big Five personality model
- **BehaviorTree** — need-driven + personality-driven decisions
- **Ticker** — PubSub broadcast, agents self-tick
- **World** — 50×50 tile grid with terrain (grass/water/forest/mountain)
- **Pixi.js 2D Renderer** — camera controls, agent sprites, terrain rendering
- **Phoenix LiveView** — onboarding wizard, real-time dashboard
- **WebSocket Channel** — full-duplex world state streaming

### 🏗️ Architecture
- Docker isolation (modus-app + modus-llm)
- Registry metadata for fast position lookups (no GenServer deadlocks)
- Agent self-tick via PubSub (decoupled from WorldChannel)
- EventLog with PubSub subscription

---

_MODUS — Create worlds. Watch them live._
_NeuraByte Labs · 2026_

## v0.4.0 — Cerebro (2026-02-16)
> "The mind's power of thinking is equal to, and simultaneous with, the body's power of acting."
> — Ethics III, Proposition 28

### Added
- **SocialNetwork** — ETS relationship graph with strength-based type progression (stranger→acquaintance→friend→close_friend)
- **AgentConversation** — Async LLM agent-to-agent dialogue with cooldown, concurrent limit, affect-influenced Turkish prompts
- **SpatialMemory** — Joy-biased exploration (40% pull toward happy memories), fear repulsion
- **MindView** — Relationship lines between agents, conversation bubbles (💬), 🧠 Mind View toggle
- **Enhanced detail panel** — İlişkiler (relationships) section, Son Konuşmalar (recent conversations)
- **LlmProvider persistent_term** — Non-blocking config reads via `:persistent_term`

### Fixed
- Agent survival rebalance — hunger auto-recovery at 70 (was 85), conatus drain reduced
- LlmProvider.get_config() no longer blocks on batch_decide
- Struct access in world_channel (Access protocol → Map.get)
