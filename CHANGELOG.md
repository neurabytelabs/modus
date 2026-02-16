# MODUS Changelog

> "Each thing strives to persevere in its being" — Spinoza, Ethics III

Versioning follows Spinoza's philosophical evolution. Each release is a new mode of understanding.

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
