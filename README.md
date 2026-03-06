<div align="center">

```
███╗   ███╗ ██████╗ ██████╗ ██╗   ██╗███████╗
████╗ ████║██╔═══██╗██╔══██╗██║   ██║██╔════╝
██╔████╔██║██║   ██║██║  ██║██║   ██║███████╗
██║╚██╔╝██║██║   ██║██║  ██║██║   ██║╚════██║
██║ ╚═╝ ██║╚██████╔╝██████╔╝╚██████╔╝███████║
╚═╝     ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚══════╝
```

# Create Worlds. Watch Them Live.

**AI agents with emotions, memory, and free will — building civilizations in worlds you design.**

[![Version](https://img.shields.io/badge/version-v9.1.0_Anima-blueviolet)](CHANGELOG.md)
[![Elixir](https://img.shields.io/badge/Elixir-1.17+-4B275F?logo=elixir)](https://elixir-lang.org/)
[![Phoenix](https://img.shields.io/badge/Phoenix-1.7+-orange?logo=phoenix-framework)](https://phoenixframework.org/)
[![Tests](https://img.shields.io/badge/tests-867-brightgreen)](test/)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

*"Each thing, as far as it lies in itself, strives to persevere in its being."*  
— Baruch Spinoza, *Ethics* III

[Demo](#-quick-start) · [Features](#-what-makes-modus-different) · [Architecture](#-architecture) · [Docs](docs/) · [Changelog](CHANGELOG.md)

</div>

---

## 🌍 What is MODUS?

**MODUS** is a universe simulation platform where every AI agent is a concurrent BEAM process with its own mind — emotions, episodic memories, relationships, goals, and the drive to survive. You design the world's physics and watch emergent civilizations unfold.

Not a game. Not a chatbot playground. **A living system built on Spinoza's philosophy.**

- 🧠 **Mind Engine** — Agents feel joy, sadness, fear, desire. They plan multi-step goals, form clans, tell stories, and pray when desperate.
- 🌐 **World Builder** — Paint terrain, set physics (time speed, danger, birth rate), spawn ruins, trigger disasters.
- 🎭 **Culture Engine** — Catchphrases emerge from lived experience and mutate across generations. Traditions form organically.
- 📊 **Observatory** — SVG dashboards track population, happiness, trade volume, ecosystem balance, and relationship networks.
- 🌍 **Multi-Language** — Worlds are born in one of 6 languages (EN, TR, DE, FR, ES, JA). Agents think and speak natively.
- 💾 **Persistence** — Auto-save, 5 save slots, world seeds, crash recovery, JSON export/import with share codes.

### Why MODUS?

**Simile AI** ($100M, enterprise) builds workforce simulations for corporations. **MODUS** is the B2C creator platform — indie devs, educators, storytellers, and philosophers building living worlds for exploration, narrative, and research.

**Spinoza's *modus*** means "mode of being." Every simulation is a *modus* — an individual expression of existence within the infinite.

---

## ⚡ Quick Start

### Docker (Recommended)

```bash
git clone https://github.com/neurabytelabs/modus.git
cd modus
docker compose up -d
open http://localhost:4000
```

Choose a world template (Village, Island, Medieval, Space...), set population, pick a language, and watch agents build their civilization.

### Local Development

**Requirements:** Elixir 1.17+, PostgreSQL 16+, Node.js 18+

```bash
mix deps.get
mix ecto.setup
cd assets && npm install && cd ..
mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000)

### Environment Variables

```bash
# LLM Providers (at least one required)
export ANTIGRAVITY_GATEWAY_URL=http://localhost:8080  # 60+ models
export GEMINI_API_KEY=your_key_here                   # Gemini Direct API
export OPENAI_API_KEY=your_key_here                   # OpenAI models

# Database
export DATABASE_URL=ecto://postgres:postgres@localhost/modus_dev

# Optional
export PHX_HOST=localhost
export PORT=4000
export SECRET_KEY_BASE=$(mix phx.gen.secret)
```

---

## 🧠 The Spinoza Mind Engine

Every agent has a **mind** — not a behavior tree, a *mind*.

| Layer | Spinoza Concept | Implementation |
|-------|----------------|----------------|
| **Conatus** | Drive to persist | Energy (0.0–1.0) that rises with success, falls with hardship. Zero = death. |
| **Affects** | Emotional states | Joy, sadness, desire, fear, curiosity — shapes every decision and memory. |
| **Episodic Memory** | Lived experience | SQLite-backed memories with decay. Emotional events persist longer. |
| **Planner** | Goal decomposition | "Build house" → gather wood → gather stone → construct. Re-plans when blocked. |
| **Creativity** | Invention & story | Agents name places, invent recipes, tell stories that mutate over generations. |
| **Social Network** | Relationships | Friendship, rivalry, trust. Strangers → acquaintances → friends → close friends. |
| **Personality** | Big Five traits | Openness, conscientiousness, extraversion, agreeableness, neuroticism. |
| **Prayer System** | Divine communication | Desperate agents pray to the player (God) based on emotional state. |

### How It Works

1. **Perception** — Agent sees nearby terrain, resources, agents, relationships, and buildings.
2. **Reasoning** — LLM generates context-aware decisions based on needs, personality, and memory.
3. **Action** — Move, gather, build, trade, converse, pray, sleep, craft.
4. **Memory** — Emotional events (births, deaths, friendships, conflicts) stored with salience scores.
5. **Affect Update** — Success/failure modulates conatus and emotional state.

The mind runs on **multi-LLM architecture** with automatic fallback:

```
Antigravity Gateway (60+ models)
    ↓ timeout/error
Gemini Direct API
    ↓ timeout/error
Ollama (local models)
    ↓ timeout/error
Hardcoded personality-based responses
```

**LLM optimizations:**
- Call batching (multiple agents per prompt)
- ETS-backed response cache (TTL = 100 ticks)
- Behavior trees for simple decisions (no LLM needed)
- Budget tracking (max N calls per tick with priority queue)

---

## 🌍 World Systems

### Terrain & Biomes
- **7 biomes** — Deep water, shallow water, sand, grass, forest, mountain, snow
- **Perlin noise generation** — Procedural terrain from world seeds
- **Terrain painter** — Draw tile-by-tile, place resources manually
- **11 world templates** — Village, Island, Desert, Space, Underwater, Medieval, Cyberpunk, Jungle, Arctic, Volcanic, Cloud City

### Wildlife & Ecology
- 🦌 Deer · 🐇 Rabbits · 🐺 Wolves · 🐦 Birds · 🐟 Fish
- **Breeding** with population caps and seasonal variation
- **Food chains** — Wolves hunt deer, agents hunt rabbits, overhunting causes famine
- **Seasonal migration** — Animals move with weather patterns

### Buildings & Neighborhoods
- **6 building types** — Hut 🛋, House 🏠, Farm 🌾, Market 🏪, Well 🪣, Watchtower 🗼
- **Upgrades** — Hut (L1) → House (L2) → Mansion (L3)
- **Neighborhoods** — 3+ buildings within 5 tiles form named clusters ("Green Hill", "Oak Meadow")
- **Area bonuses** — Buildings provide rest, shelter, hunger, and social boosts
- **Building decay** — Abandoned buildings lose health over time, become ruins

### Ruins & Archaeology
- 🏛️ Temples · 🏰 Castles · 🏚️ Villages · 🗿 Monuments
- Agents excavate ruins, discover **artifacts** (tools, scrolls, treasures, relics)
- **Museums** display artifacts for culture bonuses
- Dead civilizations leave traces

### Seasons & Weather
- **4 seasons** — 🌸 Spring (+50% growth) → ☀️ Summer (heat drain) → 🍂 Autumn (harvest) → ❄️ Winter (survival)
- **Weather effects** — ☁️ Clear · 🌧️ Rain · ⛈️ Storm · 🌫️ Fog · ❄️ Snow
- **Day/night cycle** — Dawn, day, dusk, night, pre-dawn with ambient color shifts
- **Seasonal tint overlays** — Flat 2D color layers (green → gold → frosty white)

### Dynamic Events
- **Natural disasters** — 🌩️ Storm · 🌍 Earthquake · ☄️ Meteor · 🌊 Flood · 🔥 Fire
- **Complex event chains** — Drought → famine → migration → conflict
- **Social events** — 🎉 Festivals · 🏛️ Discoveries · 🚶 Migration waves
- **God Mode triggers** — Player-triggered events (plague, treasure, golden age)

---

## 🎛️ World Rules Engine

Tune world physics in real-time:

| Rule | Range | Effect |
|------|-------|--------|
| ⏱️ **Time Speed** | 0.5x–3.0x | Simulation tick interval |
| 🌾 **Resource Abundance** | Scarce/Normal/Abundant | Resource availability |
| ⚠️ **Danger Level** | Peaceful/Moderate/Harsh/Extreme | World hostility |
| 💬 **Social Tendency** | 0.0–1.0 | Agent sociability |
| 👶 **Birth Rate** | 0.0–2.0x | Population growth |
| 🏗️ **Building Speed** | 0.5–3.0x | Construction rate |
| 🧬 **Mutation Rate** | 0.0–1.0 | Personality variance on birth |

### 5 Presets
- 🕊️ **Peaceful Paradise** — Abundant resources, high birth rate, fast building
- 💀 **Harsh Survival** — Scarce resources, extreme danger, low birth rate
- 🌪️ **Chaotic** — Fast time, high mutation, harsh environment
- ✨ **Utopia** — Abundant, peaceful, highly social, zero mutation
- 🧪 **Evolution Lab** — Max speed, high birth & mutation rates

All changes take effect **instantly** — no restart needed.

---

## 👥 Society & Culture

### Clans & Leadership
- Nearby agents with positive relationships form **tribes**
- Highest social influence becomes **leader** (decides resource allocation, movement)
- **Alliances and rivalries** between groups
- LLM-generated group names

### Communication
- **Structured dialogue** — Trade proposals, alliance offers, gossip, warnings
- **Persuasion system** — Skill-based influence with success/resist outcomes
- **Rumor spreading** — Information degrades as it passes through social networks
- **Secrets** — Only shared with trusted agents

### Trade & Economy
- **Agent-to-agent barter** — Personality-driven value assessment
- **Supply and demand** — Abundant resources lose value
- **Markets** provide trade bonuses
- Full trade history tracking

### Crafting & Skills
- **Recipe-based** — Sword = iron + wood, bread = wheat + water, medicine = herb + water
- **Skill levels** — Novice → Apprentice → Expert → Master
- **XP from repetition** — Practice improves quality
- **Teaching** — Masters train apprentices

### Cultural Evolution
- **Catchphrases** emerge from lived experience and spread through conversation
- **Traditions** — Harvest Festival, Mourning Circle, Dawn Greeting, Winter Vigil, Spring Awakening, Stargazing Rite
- **Cultural drift** — Phrases mutate over generations (telephone game effect)
- **Stories** — Agents create oral histories that transform as they're retold

---

## 🌐 Multi-Language Worlds

Worlds are **born in a language**:

🇬🇧 English · 🇹🇷 Türkçe · 🇩🇪 Deutsch · 🇫🇷 Français · 🇪🇸 Español · 🇯🇵 日本語

Agents think, speak, name themselves, and create culture **entirely in that language**. A Turkish world has agents named Ayşe and Mehmet saying *"Damlaya damlaya göl olur"*.

---

## 📊 Observatory Dashboard

Pure SVG analytics, no JavaScript libraries:

- 📈 **Population graph** — Last 100 ticks, birth/death trends
- 📊 **Resource distribution** — Wood, stone, food, water over time
- 🕸️ **Relationship network** — Circle-layout graph (color-coded by strength)
- 😊 **Mood distribution** — Happiness index across the population
- 💰 **Trade volume** — Cumulative transaction activity
- 🦌 **Ecosystem balance** — Predator/prey ratios

Toggle with `D` key. Auto-refresh every 50 ticks.

---

## 🎮 Controls & UI Modes

| Key | Mode | Description |
|-----|------|-------------|
| — | **Normal** | Full UI with all panels |
| `T` | **Text** | Pure unicode/emoji grid — works over SSH |
| `Z` | **Zen** | Hide all UI. Just watch. |
| `G` | **God** | Omniscience. See and control everything. |
| `D` | **Dashboard** | SVG analytics overlay |
| `M` | **Metrics** | LLM performance monitor |
| `P` | **Performance** | System health panel |
| `B` | **Mind View** | Relationship lines & conversation bubbles |
| `Space` | **Pause/Play** | Toggle simulation |
| `1/5/0` | **Speed** | 1x / 5x / 10x time |
| `Cmd+K` | **Command Palette** | Unified control interface |
| `Esc` | **Deselect** | Close all panels |

---

## 💾 Persistence & Sharing

- **Auto-save** — Configurable interval (default: every 200 ticks)
- **5 save slots** — Named saves with timestamps
- **World seeds** — Same seed = same world, always reproducible
- **Crash recovery** — Loads last auto-save on restart
- **JSON export/import** — Portable world format with gzip compression
- **Share codes** — Base64+zlib compressed string for instant world sharing (no file needed)
- **Chronicle export** — Full world history as markdown

---

## 🏗️ Architecture

```
238 Elixir modules · 867 tests · 44K+ LOC · 264 commits

Mind                          Simulation
├── Conatus (energy/drive)    ├── World (terrain, biomes)
├── Affect (emotions)         ├── Agent (per-process lifecycle)
├── EpisodicMemory            ├── Wildlife (breeding, food chains)
├── Planner (goal decomp)     ├── Building (construction, decay)
├── Creativity (stories)      ├── TradeSystem (barter, supply/demand)
├── SocialEngine (clans)      ├── CraftingSystem (recipes, skills)
├── Culture (traditions)      ├── Seasons (4-season cycle)
├── Perception (awareness)    ├── Weather (rain, snow, fog, storms)
├── Reasoning (LLM thinking)  ├── WorldEvents (disasters, chains)
├── Learning (skill XP)       ├── Archaeology (ruins, artifacts)
└── PrayerSystem              ├── RulesEngine (custom physics)
                              ├── Observatory (analytics)
Intelligence                  ├── TerrainGenerator (Perlin noise)
├── AntigravityClient         └── WorldTemplates (11 presets)
├── GeminiClient
├── OllamaClient              Persistence
├── OpenAIClient              ├── WorldPersistence (SQLite)
├── LlmScheduler              ├── WorldExport (JSON, gzip)
├── ResponseCache             ├── SaveManager (5 slots)
└── BehaviorTree              └── AutoSave (crash recovery)

Protocol                      Performance
├── IntentParser              ├── SpatialIndex (O(1) queries)
├── ContextBuilder            ├── StateSnapshots (delta compression)
├── Perception                ├── EventLog (ETS, TTL pruning)
└── Bridge (orchestration)    ├── MemoryAudit (per-agent limits)
                              └── Benchmark (50-500 agents)
Web
├── UniverseLive (Phoenix LiveView)
├── WorldChannel (WebSocket sync)
├── DemoLive (public `/demo` mode)
└── Pixi.js Renderer (2D top-down)
```

### Why Elixir + BEAM?

- **Concurrency** — Every agent is a lightweight process. 1 million agents = 1 million processes.
- **Fault tolerance** — Agent crashes don't crash the simulation. Supervisors auto-restart.
- **Actor model** — Natural fit for autonomous agents with independent state.
- **No GenServer bottlenecks** — ETS for O(1) reads, PubSub for event broadcast, Registry for position lookups.

---

## ⚡ Performance

Benchmarked on **Mac Mini M4 (16GB)**:

| Agents | Avg Tick | P95 | P99 | Target |
|--------|----------|-----|-----|--------|
| 50 | 0.65ms | 0.69ms | 0.72ms | < 100ms |
| 100 | 1.44ms | 1.49ms | 1.55ms | < 100ms |
| 200 | 3.62ms | 3.71ms | 3.85ms | < 100ms |
| 500 | 14.04ms | 15.40ms | 16.2ms | < 100ms |

**Target:** 200 agents under 100ms/tick → **achieved at 3.62ms** (27x headroom)

**Optimizations:**
- ETS spatial indexing (dirty flag skip when no movement)
- Delta compression for state snapshots
- Batched PubSub broadcasts (every 10 ticks for non-critical updates)
- LLM call batching + response caching

---

## 📜 Versioning Philosophy

Every release is named after a concept in **Baruch Spinoza's *Ethics*** (1677).

| Version | Codename | Theme | Highlights |
|---------|----------|-------|------------|
| **v9.0.0** | **Anima** | Soul & Spirit | Tutorial system, settings panel, revenue model, tech radar |
| v8.1.0 | Imperium | Command | Command palette (Cmd+K), unified control interface |
| v7.9.0 | Divinus | Divine | Delta snapshots, event TTL, PubSub batching, death tracking |
| v5.6.6 | Divinus | Divine | PubSub consolidation, ETS everywhere, ticker health |
| v5.4.0 | Harmonia | Harmony | Sprint v4 final integration |
| v4.9.0 | Imperium | Command | Divine intervention UI |
| v4.7.0 | Ruina | Ruins | Archaeology system |
| v3.8.5 | Lingua Mundi | World Language | 6-language support |
| v3.7.0 | Persistentia | Persistence | Auto-save, crash recovery |
| v3.6.0 | Speculum | Mirror | SVG dashboard |
| v3.0.0 | Societas | Society | Clans, leadership |
| v2.0.0 | Infinitum | Infinite | Custom rules engine |
| v1.0.0 | Substantia | Substance | Economy & lifecycle |
| v0.5.0 | Libertas | Freedom | Protocol bridge |
| v0.3.0 | Affectus | Affects | Emotions & memory |
| v0.1.0 | Genesis | The Beginning | The world was born |

[Full changelog](CHANGELOG.md)

---

## 🗺️ Roadmap

### Completed (v9.0 Anima)
- ✅ Spinoza Mind Engine (conatus, affects, episodic memory)
- ✅ Multi-LLM architecture (Antigravity, Gemini, Ollama, OpenAI)
- ✅ World builder with 11 templates
- ✅ Seasons, weather, day/night cycles
- ✅ Buildings, neighborhoods, ruins, archaeology
- ✅ Clans, leadership, alliances
- ✅ Trade, crafting, skills
- ✅ Cultural evolution, traditions
- ✅ Multi-language support (6 languages)
- ✅ Observatory dashboard
- ✅ Auto-save, world seeds, share codes
- ✅ Command palette, tutorial system

### Next (v9.1)
- [ ] Mobile-responsive UI (touch controls)
- [ ] WebGL renderer (performance boost for 500+ agents)
- [ ] Advanced AI orchestration (multi-agent LLM planning)
- [ ] Community world gallery (public share codes)

### Future (v10.0+)
- [ ] Multiplayer (collaborative world building)
- [ ] Modding API (custom agent behaviors, terrain types, events)
- [ ] Time-travel debugging (rewind simulation to any tick)
- [ ] AI-generated world art (DALL·E/Stable Diffusion integration)

---

## 🤝 Contributing

MODUS is currently in **private beta**. We're not yet accepting external contributions, but we'd love to hear your thoughts:

- 🐛 **Bug reports** — [Open an issue](https://github.com/neurabytelabs/modus/issues)
- 💡 **Feature requests** — [Start a discussion](https://github.com/neurabytelabs/modus/discussions)
- 📖 **Questions** — Join our [Discord](https://discord.gg/neurabyte) (coming soon)

We plan to open-source the **core engine** (Mind, World, Protocol layers) while keeping premium features (hosted simulations, advanced LLM orchestration) in a commercial tier.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

**Exception:** The Spinoza Mind Engine module (`lib/modus/mind/`) may be relicensed under a commercial license in future versions. Current open-source usage is grandfathered.

---

## 🙏 Credits

**Built by [NeuraByte Labs](https://neurabytelabs.com)** · *Where Spinoza Meets Silicon*

- **Philosophy** — Baruch Spinoza (1632–1677), *Ethics*
- **Inspiration** — Simile AI, Conway's Game of Life, Dwarf Fortress, The Sims
- **Tech Stack** — Elixir/BEAM, Phoenix LiveView, Pixi.js, SQLite, Docker
- **LLM Providers** — Antigravity Gateway, Gemini, Ollama, OpenAI

Special thanks to the Elixir community for building the most elegant concurrency platform in existence.

---

<div align="center">

**"By reality and perfection I mean the same thing."**  
— Spinoza, *Ethics* II, Definition VI

[⬆ Back to top](#)

</div>
