<p align="center">
  <h1 align="center">MODUS</h1>
  <p align="center"><strong>Create Worlds. Watch Them Live.</strong></p>
  <p align="center">
    An AI universe simulation where autonomous agents develop emotions, build civilizations, and write their own history.
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/version-v2.3.0_Amor-purple" alt="Version" />
    <img src="https://img.shields.io/badge/Elixir-1.17+-4B275F?logo=elixir" alt="Elixir" />
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="License" />
    <img src="https://img.shields.io/badge/modules-62-green" alt="Modules" />
    <img src="https://img.shields.io/badge/tests-130+-brightgreen" alt="Tests" />
  </p>
</p>

<p align="center"><em>"Deus sive Natura" — God, or Nature</em> — Baruch Spinoza</p>

---

<p align="center">[screenshot coming soon]</p>

---

## Why MODUS?

MODUS is not a game. It's a universe creation platform built on Spinoza's philosophy. You design worlds with custom physics, paint terrain, and populate them with AI agents who have genuine emotions, personality, memory, and free will. They don't follow scripts — they form friendships, build homes, develop culture, survive winters, and write history you never planned. The simulation is their reality.

Built on Elixir/BEAM (one process per agent mind), Phoenix LiveView, and Pixi.js 2D rendering. Every agent is a living concurrent process.

---

## Features

### 🌍 Create Your World

**World Builder** — Paint terrain tile by tile, place resources, design custom agents with Big Five personality sliders, and spawn wildlife. Your world, your rules.

**11 Universe Templates** — Start from curated worlds: Village 🏘️ · Island 🏝️ · Desert 🏜️ · Space 🚀 · Underwater 🌊 · Medieval 🏰 · Cyberpunk 🌃 · Jungle 🌴 · Arctic ❄️ · Volcanic 🌋 · Cloud City ☁️ — or roll 🎲 Random.

**Rules Engine** — Tune world physics in real-time:
- ⏱️ Time speed (0.5x–3x) · 🌾 Resource abundance · ⚠️ Danger level · 💬 Social tendency · 👶 Birth rate · 🏗️ Build speed · 🧬 Mutation rate
- **Presets:** 🕊️ Peaceful Paradise · 💀 Harsh Survival · 🌪️ Chaotic · ✨ Utopia · 🧪 Evolution Lab

**Multi-Universe Dashboard** — Create, manage, and switch between multiple worlds. Sort by age, population, or creation date.

---

### 🧠 Living Minds

The **Spinoza Mind Engine** gives each agent a genuine inner life:

- **Conatus** — The drive to persist in being. Energy rises with success, falls with hardship.
- **Affects** — Joy, sadness, desire, fear — real emotional states that shape every decision.
- **Memory** — Episodic memories with salience scoring. Strong emotions persist; mundane fades.
- **Reasoning** — LLM-powered thinking triggered by emotional states. A persistently sad agent asks itself: *"Why am I sad?"*
- **Personality** — Big Five traits (openness, conscientiousness, extraversion, agreeableness, neuroticism) that make every agent unique.
- **Goals** — Build home, make friends, explore the map, gather resources, survive winter. Auto-assigned by personality, trackable with progress bars.

---

### 🦌 Nature & Ecosystem

**Wildlife** — Deer 🦌, rabbits 🐇, wolves 🐺, birds 🐦, fish 🐟 — each with their own behaviors. Agents hunt, gather, and flee.

**Seasons** — Spring 🌸 (+50% growth) → Summer ☀️ (heat drain) → Autumn 🍂 (harvest) → Winter ❄️ (scarce resources, survival mode). Terrain colors shift. Agents reference seasons in conversation.

**World Events** — 🌩️ Storm · 🌍 Earthquake · ☄️ Meteor Shower · 🦠 Plague · ✨ Golden Age · 🌊 Flood · 🔥 Fire — spawn naturally or trigger manually. Events damage buildings, shift moods, and mutate terrain.

**Resources** — Renewable resources that deplete and regrow. Wood, stone, food — the raw materials of civilization.

---

### 🏠 Civilization

**Building System** — Agents gather resources and build: Hut 🛋 → House 🏠 → Mansion 🏛. Farms 🌾, Markets 🏪, Wells 🪣, Watchtowers 🗼. Buildings provide area bonuses and decay without owners.

**Neighborhoods** — When 3+ buildings cluster, a named neighborhood emerges organically: *"Green Hill"*, *"Oak Meadow"*. Residents get social bonuses. Agents prefer building near friends.

**Cultural Evolution** — Catchphrases emerge from lived experience and spread through conversation. Traditions form: Harvest Festival, Mourning Circle, Dawn Greeting, Winter Vigil. Phrases mutate over generations — cultural drift in action.

**World History** — Automatic era detection: The Founding → Expansion → Great Famine → Golden Age → Renaissance. Key figures tracked by achievements. Full chronicle exportable as markdown.

**Economy** — Proximity-based bartering. Trade volume tracked. Markets boost local exchange.

---

### 👁️ Observe & Interact

**Observatory** — Population graphs, happiness index, trade volume, building breakdown, agent leaderboards (Most Social, Wealthiest, Happiest, Oldest), and a relationship network visualization.

**Chat with Agents** — Talk to any agent in natural language. They respond with real personality, real memories, real emotions. They know their goals, their friends, their history.

**God Mode (G)** — See all internals: conatus, affects, memory, relationships. Cinematic camera auto-follows interesting events. Trigger world events manually. Place buildings and agents anywhere.

**Export & Share** — JSON export/import, compressed share codes (paste to recreate any world), chronicle markdown download, screenshot with overlay branding.

---

### 🎮 Multiple Modes

| Key | Mode | Description |
|-----|------|-------------|
| — | **Normal** | Full UI with all panels and controls |
| `T` | **Text Mode** | Pure unicode/emoji grid — works over SSH |
| `Z` | **Zen Mode** | Hide all UI. Just watch the world breathe. |
| `G` | **God Mode** | Full omniscience. See everything, control everything. |

---

### 🤖 Multi-LLM Support

- **Ollama** — Run models locally, fully offline
- **Antigravity Gateway** — 60+ models through a single proxy
- **Gemini** — Direct Google AI fallback
- Switch providers at runtime from the settings panel

---

## Quick Start

```bash
docker compose up -d
# Open http://localhost:4000
```

With Antigravity Gateway (multi-LLM):
```bash
export ANTIGRAVITY_API_KEY=sk-your-key
docker compose up -d
```

Development:
```bash
cd src
mix deps.get
mix ecto.migrate
mix phx.server
# Open http://localhost:4000
```

Run tests:
```bash
cd src
mix test  # 130+ tests
```

---

## Architecture

```
62 Elixir modules · 34 test files · 85 commits

├── Mind
│   ├── Conatus          — Drive to persist
│   ├── Affect           — Emotional state machine
│   ├── Perception       — Spatial awareness
│   ├── Reasoning        — LLM-powered thinking
│   ├── Learning         — Skill progression
│   ├── Goals            — Objective tracking
│   └── Culture          — Catchphrases & traditions
│
├── Intelligence
│   ├── Ollama           — Local LLM
│   ├── Antigravity      — Multi-model gateway
│   └── Gemini           — Google AI direct
│
├── Simulation
│   ├── World            — Terrain, resources, biomes
│   ├── Agent            — Per-process agent lifecycle
│   ├── Ticker           — PubSub tick broadcast
│   ├── Economy          — Barter & trade
│   ├── Lifecycle        — Birth & death
│   ├── Building         — Construction & neighborhoods
│   ├── Seasons          — Four-season cycle
│   ├── WorldEvents      — Disasters & miracles
│   ├── WorldHistory     — Era detection & chronicle
│   ├── RulesEngine      — Custom world physics
│   ├── Observatory      — Analytics aggregation
│   └── WorldTemplates   — 11 universe presets
│
├── Cerebro
│   ├── SocialNetwork    — Relationship graph
│   ├── SpatialMemory    — Location-emotion mapping
│   └── SocialInsight    — Personality understanding
│
├── Protocol
│   ├── IntentParser     — Message classification
│   ├── ContextBuilder   — Dynamic LLM prompts
│   └── Bridge           — Orchestration layer
│
├── Persistence
│   ├── WorldPersistence — SQLite save/load
│   └── WorldExport      — JSON export/import/share
│
└── Web
    ├── UniverseLive     — Phoenix LiveView UI
    ├── WorldChannel     — WebSocket state sync
    └── Pixi.js Renderer — 2D top-down rendering
```

---

## Version History

Every release is named after a concept in Spinoza's philosophy.

| Version | Codename | Theme |
|---------|----------|-------|
| **v2.3.0** | **Amor** | Landing page, Text Mode, Zen Mode, final polish |
| v2.2.1 | Speculum | Export, import, share codes |
| v2.2.0 | Speculum | Observatory dashboard |
| v2.1.1 | Lingua | World history & era detection |
| v2.1.0 | Lingua | Cultural evolution |
| v2.0.1 | Infinitum | Agent goals system |
| v2.0.0 | Infinitum | Custom rules engine |
| v1.9.1 | Tempus | Seasons & day/night |
| v1.9.0 | Tempus | World events engine |
| v1.8.1 | Architectus | Neighborhoods & upgrades |
| v1.8.0 | Architectus | Building system |
| v1.7.1 | Nexus | 11 universe templates |
| v1.7.0 | Nexus | Multi-universe dashboard |
| v1.6.1 | Creator | Agent designer & Big Five |
| v1.5.0 | Deus | God Mode & cinematic camera |
| v1.4.0 | Potentia | Story engine & timeline |
| v1.1.0 | Harmonia | Mini-map, tooltips, shortcuts |
| v1.0.0 | Substantia | Economy & lifecycle |
| v0.5.0 | Libertas | Protocol bridge & perception |
| v0.4.0 | Cerebro | Social network & conversations |
| v0.3.0 | Affectus | Conatus, affects, memory |
| v0.2.0 | Conatus | Multi-LLM & chat |
| v0.1.0 | Genesis | The world was born |

---

## Design Philosophy

MODUS is always 2D. Top-down. Flat. No isometric, no 3D, no perspective tricks.

The complexity lives in the minds, not the pixels. A colored circle with a name label carries more meaning than a 3D-rendered character — because behind that dot is a concurrent BEAM process with emotions, memories, relationships, goals, and the drive to persist.

> *If a 5-year-old can't understand what they're looking at in 3 seconds, it's too complex. Simplify.*

Three rendering levels exist: **Text Mode** (pure unicode — works over SSH), **Tile Mode** (colored squares + emoji — current default), and a future **Sprite Mode** (16×16 pixel art — still 2D, still top-down). Deep minds in simple dots.

---

## The Spinoza Connection

MODUS is built on Baruch Spinoza's *Ethics* (1677):

**Conatus** — *"Each thing, as far as it lies in itself, strives to persevere in its being."* Every agent has this drive. It rises when they succeed, falls when they suffer, and when it reaches zero, they cease to exist.

**Affects** — *"By affect I understand the modifications of the body by which the body's power of acting is increased or diminished."* Joy, sadness, desire, fear — not decorative labels but the engine of decision-making.

**Substance** — *"Whatever is, is in God, and nothing can be or be conceived without God."* The simulation is a single interconnected system. Every agent, every resource, every relationship is a mode of one substance.

**Deus sive Natura** — *God, or Nature.* The simulation doesn't represent reality. For its inhabitants, it *is* reality. And you are the one who created it.

---

## Contributing

Contributions welcome. MODUS is built with Elixir, Phoenix LiveView, and Pixi.js.

```bash
cd src
mix deps.get
mix test
```

Please keep it 2D.

---

## License

MIT — [NeuraByte Labs](https://github.com/neurabytelabs) · 2026
