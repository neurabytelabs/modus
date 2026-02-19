<p align="center">
  <h1 align="center">MODUS_</h1>
  <p align="center"><strong>Create Worlds. Watch Them Live.</strong></p>
  <p align="center">
    AI agents with emotions, memory, and free will — building civilizations in worlds you design.
  </p>
  <p align="center">
    <img src="https://img.shields.io/badge/version-v5.4.0_Harmonia-purple" alt="Version" />
    <img src="https://img.shields.io/badge/Elixir-1.17+-4B275F?logo=elixir" alt="Elixir" />
    <img src="https://img.shields.io/badge/modules-100+-green" alt="Modules" />
    <img src="https://img.shields.io/badge/tests-686-brightgreen" alt="Tests" />
    <img src="https://img.shields.io/badge/LOC-31K+-blue" alt="Lines of Code" />
    <img src="https://img.shields.io/badge/license-MIT-blue" alt="License" />
  </p>
</p>

<p align="center"><em>"Each thing, as far as it lies in itself, strives to persevere in its being."</em> — Spinoza, Ethics III</p>

---

MODUS is a universe simulation platform where every AI agent is a concurrent BEAM process with its own emotions, memories, goals, and will to survive. You design the world — terrain, rules, wildlife, language — and the agents write their own history. They form clans, craft tools, trade resources, tell stories, and build civilizations you never planned.

Not a game. Not a chatbot demo. A living system built on philosophy.

---

## ⚡ Quick Start

```bash
docker compose up -d
open http://localhost:4000
```

Choose a template (or paint your own), set population, pick a language, and watch.

---

## 🧠 The Spinoza Mind Engine

Every agent has a mind. Not a behavior tree — a mind.

| Layer | Concept | What It Does |
|-------|---------|-------------|
| **Conatus** | Drive to persist | Energy that rises with success, falls with hardship. Zero = death. |
| **Affects** | Emotional states | Joy, sadness, desire, fear, curiosity — shapes every decision |
| **Episodic Memory** | Lived experience | Memories decay over time. Emotional ones persist. Agents recall and reference the past. |
| **Planner** | Strategic thinking | Goal decomposition: "build house" → gather wood → gather stone → build. Re-plans when blocked. |
| **Creativity** | Story & invention | Agents name places, tell stories, invent recipes, create oral traditions that mutate over generations |
| **Personality** | Big Five traits | Openness, conscientiousness, extraversion, agreeableness, neuroticism — unique per agent |

The mind engine runs on LLM reasoning: a sad agent asks itself *"Why am I sad?"* and changes behavior based on the answer.

---

## 🌍 World Systems

### Terrain & Biomes
- **Perlin noise generation** — 7 procedural biomes (deep water, shallow water, sand, grass, forest, mountain, snow)
- **Terrain painter** — Draw terrain tile by tile, place resources manually
- **World seeds** — Same seed = same world, always

### Wildlife & Ecology
- 🦌 Deer · 🐇 Rabbits · 🐺 Wolves · 🐦 Birds · 🐟 Fish
- **Breeding** with population caps — food chains emerge naturally
- **Seasonal migration** — animals move with the weather
- **Ecosystem balance** — overhunting causes famine

### Weather & Seasons
- 🌸 Spring (+50% growth) → ☀️ Summer (heat drain) → 🍂 Autumn (harvest) → ❄️ Winter (survival mode)
- ☁️ Clear · 🌧️ Rain · ⛈️ Storm · 🌫️ Fog · ❄️ Snow — affects agent behavior and terrain

### Buildings & Neighborhoods
- Agents gather resources and build: **Hut → House → Mansion**
- Farms 🌾 · Markets 🏪 · Wells 🪣 · Watchtowers 🗼
- **Neighborhoods** form organically when 3+ buildings cluster — named automatically, social bonuses
- Abandoned buildings decay into **ruins** — discoverable archaeological sites

### Ruins & Archaeology
- 🏛️ Temples · 🏰 Castles · 🏚️ Villages · 🗿 Monuments
- Agents excavate ruins, discover **artifacts** (tools, scrolls, treasures, relics)
- **Museums** display artifacts for culture bonuses

---

## 👥 Society & Culture

### Clans & Leadership
- Nearby agents with positive relationships form **tribes**
- Highest social influence = **leader** (decides resource allocation, movement)
- **Alliances and rivalries** between groups
- Group names generated via LLM

### Communication
- **Structured dialogue** — trade proposals, alliance offers, gossip, warnings
- **Persuasion** — skill-based influence
- **Rumors** — information spreads through social networks but degrades (telephone game)
- **Secrets** — only shared with trusted agents

### Trade & Economy
- Agent-to-agent **barter** — personality-driven value assessment
- **Supply and demand** — abundant resources lose value
- Markets provide trade bonuses
- Full trade history tracking

### Crafting & Skills
- **Recipe-based** — sword = iron + wood, bread = wheat + water, medicine = herb + water
- **Skill levels** — novice → apprentice → expert → master
- XP from repetition, mastery unlocks better quality
- **Teaching** — masters train apprentices

### Cultural Evolution
- Catchphrases emerge from experience and spread through conversation
- **Traditions** form: Harvest Festival, Mourning Circle, Dawn Greeting, Winter Vigil
- Phrases mutate over generations — cultural drift in action
- **Stories** — agents create oral histories that transform as they're retold

---

## 🌐 World Language System

Worlds are **born in a language**. When you create a world, you choose:

🇬🇧 English · 🇹🇷 Türkçe · 🇩🇪 Deutsch · 🇫🇷 Français · 🇪🇸 Español · 🇯🇵 日本語

Agents think, speak, name themselves, and create culture **entirely in that language**. A Turkish world has agents named Ayşe and Mehmet saying *"Damlaya damlaya göl olur"*.

---

## 🎛️ World Builder

### 11 Templates
Village 🏘️ · Island 🏝️ · Desert 🏜️ · Space 🚀 · Underwater 🌊 · Medieval 🏰 · Cyberpunk 🌃 · Jungle 🌴 · Arctic ❄️ · Volcanic 🌋 · Cloud City ☁️ · or 🎲 Random

### Rules Engine
Tune world physics in real-time:
- ⏱️ Time speed · 🌾 Resource abundance · ⚠️ Danger level · 💬 Social tendency · 👶 Birth rate · 🏗️ Build speed · 🧬 Mutation rate
- **Presets:** Peaceful Paradise · Harsh Survival · Chaotic · Utopia · Evolution Lab

### Dynamic Events
| Trigger | Events |
|---------|--------|
| **Natural** | 🌩️ Storm · 🌍 Earthquake · ☄️ Meteor · 🌊 Flood · 🔥 Fire |
| **Complex Chains** | Drought → Famine → Migration → Conflict |
| **Social** | 🎉 Festival · 🏛️ Discovery · 🚶 Migration Wave |
| **God Mode** | Trigger any event manually |

Events chain together: a drought causes famine, famine causes migration, migration causes conflict with existing settlements.

---

## 📊 Observatory Dashboard

Pure SVG charts, no JavaScript libraries:
- 📈 Population graph (last 100 ticks)
- 📊 Resource distribution over time
- 🕸️ Relationship network visualization
- 😊 Mood distribution
- 💰 Trade volume
- 🦌 Ecosystem balance (predator/prey ratio)

Toggle with `D` key.

---

## 💾 Persistence

- **Auto-save** every N ticks (configurable)
- **5 named save slots** per world
- **World seeds** for reproducible worlds
- **Crash recovery** — loads last auto-save on restart
- **JSON export/import** — portable world format
- **Gzip compression** for save files

---

## 🎮 Controls

| Key | Mode | Description |
|-----|------|-------------|
| — | **Normal** | Full UI with all panels |
| `T` | **Text** | Pure unicode/emoji grid — works over SSH |
| `Z` | **Zen** | Hide all UI. Just watch. |
| `G` | **God** | Omniscience. See and control everything. |
| `D` | **Dashboard** | SVG analytics overlay |
| `M` | **Metrics** | LLM performance monitor |
| `P` | **Performance** | System health panel |

---

## 🤖 Multi-LLM Architecture

Three providers, automatic fallback:

```
Antigravity Gateway (60+ models)
    ↓ timeout/error
Gemini Direct API
    ↓ timeout/error
Hardcoded personality-based responses
```

- **LLM call batching** — multiple agents per API call
- **Response caching** — ETS-backed, TTL=100 ticks
- **Behavior trees** for simple decisions (no LLM needed)
- **Budget tracking** — max N calls per tick with priority queue
- Switch providers at runtime from settings panel

---

## 🏗️ Architecture

```
100+ Elixir modules · 686 tests · 31K+ LOC · 120+ commits

Mind                          Simulation
├── Conatus (energy/drive)    ├── World (terrain, biomes)
├── Affect (emotions)         ├── Agent (per-process lifecycle)
├── EpisodicMemory            ├── Wildlife (breeding, food chains)
├── Planner (goal decomp)     ├── Building (construction, decay)
├── Creativity (stories)      ├── TradeSystem (barter, supply/demand)
├── SocialEngine (clans)      ├── CraftingSystem (recipes, skills)
├── Culture (traditions)      ├── Seasons (4-season cycle)
├── Perception (awareness)    ├── Weather (rain, snow, fog)
├── Reasoning (LLM thinking)  ├── WorldEvents (disasters, chains)
└── Learning (skill XP)       ├── Archaeology (ruins, artifacts)
                              ├── RulesEngine (custom physics)
Intelligence                  ├── Observatory (analytics)
├── AntigravityClient         ├── TerrainGenerator (Perlin noise)
├── GeminiClient              └── WorldTemplates (11 presets)
├── OllamaClient
├── LlmScheduler              Persistence
├── ResponseCache              ├── WorldPersistence (SQLite)
└── BehaviorTree               ├── WorldExport (JSON, gzip)
                               └── AutoSave (crash recovery)
Protocol
├── IntentParser               Performance
├── ContextBuilder             ├── SpatialIndex (O(n) queries)
└── Bridge (orchestration)     ├── MemoryAudit (per-agent limits)
                               └── Benchmark (50-500 agents)
Web
├── UniverseLive (Phoenix LiveView)
├── WorldChannel (WebSocket sync)
└── Pixi.js Renderer (2D top-down)
```

Every agent is a **concurrent BEAM process**. The ticker broadcasts via PubSub. State lives in ETS for O(1) reads. No GenServer bottlenecks for reads.

---

## ⚡ Performance

Benchmarked on Mac Mini M4 (16GB):

| Agents | Avg Tick | P95 | P99 |
|--------|----------|-----|-----|
| 50 | 0.65ms | 0.69ms | 0.72ms |
| 100 | 1.44ms | 1.49ms | 1.55ms |
| 200 | 3.62ms | 3.71ms | 3.85ms |
| 500 | 14.04ms | 15.40ms | 16.2ms |

Target: 200 agents under 100ms/tick → **achieved at 3.62ms** (27x headroom).

---

## 📜 Version History

Every release is named after a concept in Spinoza's philosophy.

<details>
<summary>Full version history (v0.1.0 → v5.4.0)</summary>

| Version | Codename | Theme |
|---------|----------|-------|
| **v5.4.0** | **Harmonia** | Integration, polish, Sprint Genesis |
| v5.3.0 | Velocitas | Performance benchmarks (50-500 agents) |
| v5.2.0 | Probatio | Quality pass — 0 warnings, formatted code |
| v5.1.0 | Sensus | Agent aging & appearance |
| v5.0.0 | Forma | UI design overhaul |
| v4.9.0 | Imperium | Divine intervention UI |
| v4.8.0 | Conspectus | Map zoom levels |
| v4.7.0 | Ruina | Ruins & archaeology system |
| v4.6.0 | Somnus | Sleep cycles & daily routines |
| v4.5.0 | Renascentia | Resource respawn & balance |
| v4.4.0 | Caelum | Weather system |
| v4.3.0 | Via | Road & path system |
| v4.2.0 | Aqua | Water flow simulation |
| v4.1.0 | Territorium | Perlin noise terrain (7 biomes) |
| v4.0.1 | Emendatio | Compile warning fixes |
| v3.8.5 | Lingua Mundi | World language system (6 languages) |
| v3.8.0 | Harmonia | Sprint v3 integration & polish |
| v3.7.0 | Persistentia | Auto-save, slots, seeds, crash recovery |
| v3.6.0 | Speculum | SVG data dashboard (6 charts) |
| v3.5.0 | Eventus | Dynamic events v2 (chains, festivals) |
| v3.4.0 | Nexus | Communication v2 (persuasion, rumors) |
| v3.3.0 | Optimum | Performance optimization, spatial indexing |
| v3.2.0 | Ratio | LLM optimization (batching, caching) |
| v3.1.0 | Fabrica | Crafting system, skill trees |
| v3.0.0 | Societas | Clans, leadership, alliances |
| v2.9.0 | Natura | Ecology (breeding, food chains) |
| v2.8.0 | Ars | Agent creativity (stories, inventions) |
| v2.7.0 | Mercatura | Trade & barter economy |
| v2.6.0 | Consilium | Agent planning & goal decomposition |
| v2.5.0 | Memoria | Episodic memory with decay |
| v2.4.0 | Veritas | Test stabilization (0 failures) |
| v2.3.0 | Amor | Landing page, Text/Zen modes |
| v2.2.0 | Speculum | Observatory & export |
| v2.1.0 | Lingua | Cultural evolution |
| v2.0.0 | Infinitum | Custom rules engine |
| v1.9.0 | Tempus | Seasons, world events |
| v1.8.0 | Architectus | Building system |
| v1.7.0 | Nexus | Multi-universe dashboard |
| v1.6.0 | Creator | World builder & agent designer |
| v1.5.0 | Deus | God Mode & cinematic camera |
| v1.4.0 | Potentia | Story engine & timeline |
| v1.0.0 | Substantia | Economy & lifecycle |
| v0.5.0 | Libertas | Protocol bridge |
| v0.4.0 | Cerebro | Social network |
| v0.3.0 | Affectus | Conatus & affects |
| v0.1.0 | Genesis | The world was born |

</details>

---

## Design Philosophy

> *If a 5-year-old can't understand what they're looking at in 3 seconds, it's too complex.*

MODUS is **always 2D**. Top-down. Flat. The complexity lives in the minds, not the pixels. A colored circle with a name carries more meaning than a 3D character — because behind that dot is a concurrent process with emotions, memories, relationships, and the drive to persist.

---

## The Spinoza Connection

MODUS is built on Baruch Spinoza's *Ethics* (1677):

**Conatus** — *"Each thing strives to persevere in its being."* Every agent has this drive. Zero = death.

**Affects** — *"The modifications of the body by which the body's power of acting is increased or diminished."* Joy and sadness aren't labels — they're the engine.

**Modus** — In Spinoza's metaphysics, a *modus* is an individual mode of existence within the one substance. Every agent, every world, every simulation is a modus.

**Deus sive Natura** — *God, or Nature.* The simulation doesn't represent reality. For its inhabitants, it *is* reality.

---

<p align="center">
  <strong>NeuraByte Labs</strong> · <em>"Where Spinoza Meets Silicon"</em> · 2026
</p>
