# MODUS Changelog

> "Each thing strives to persevere in its being" — Spinoza, Ethics III

Versioning follows Spinoza's philosophical evolution. Each release is a new mode of understanding.

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
