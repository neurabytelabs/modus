# MODUS v1.5.0 — Deus

> *"Deus sive Natura"* — God, or Nature — Spinoza

**MODUS** is an AI-powered universe simulation platform built on Elixir/BEAM. Autonomous agents with emotions, memory, relationships, and free will live in a procedurally generated world — powered by Spinoza's philosophy of *conatus* (the drive to persist in being).

## ✨ Features

### 🧠 Mind Engine (Spinoza-inspired)
- **Conatus Engine** — Each agent has a drive to persist, with energy that fluctuates based on experiences
- **Affect System** — Joy, sadness, desire, fear — emotions that influence decision-making
- **Affect Memory** — Agents remember emotional transitions and learn from them
- **Perception** — Spatial awareness of nearby agents, resources, and terrain
- **Reasoning Engine** — LLM-powered decision making with personality context

### 💬 Social Systems
- **Agent Conversations** — Natural language dialogue between agents via LLM
- **Social Network** — Friendship bonds with strength levels (acquaintance → close friend)
- **Group Dynamics** — Agents form groups with leaders and collective behavior
- **Social Insight** — Agents develop understanding of each other's personalities

### 🌍 World Simulation
- **Dynamic Environment** — Day/night cycles, biomes (forest, mountain, water, desert)
- **Resource System** — Renewable resources that deplete and regrow
- **Economy** — Basic trading/bartering between agents
- **Lifecycle** — Birth (happy agents reproduce) and death, population balance
- **World Seed** — Deterministic world generation from seeds

### 📚 Agent Intelligence
- **Behavior Trees** — Structured decision-making with fallback behaviors
- **Learning System** — Skills (farming, building, social, exploration) that improve with practice
- **Culture Transfer** — Newborn agents inherit skills from parents
- **Long-term Memory** — SQLite-backed persistent memories across save/load

### 📜 Storytelling
- **Story Engine** — Automatic narrative generation from significant events
- **Timeline View** — Chronological world history with emoji markers
- **Chronicle Export** — Export world history as markdown
- **Population Stats** — Visual population graphs and economy metrics
- **Toast Notifications** — Real-time event alerts

### 👁️ God Mode (v1.5.0 Deus)
- **God Mode Toggle** — See all agent internals: conatus, affects, memory, relationships at once
- **Cinematic Camera** — Auto-follows interesting events (conversations, high affect changes, groups)
- **Screenshot Export** — One-click PNG download of the current canvas state
- **Landing Page** — Beautiful info page with feature overview before entering simulation

### 🎮 Interface
- **Pixi.js 2D Renderer** — Smooth 60fps with sprite pooling and chunk-based rendering
- **Mini-map** — Overview of the entire world with viewport indicator
- **Tooltips** — Hover over agents for quick info
- **Agent Detail Panel** — Click any agent to inspect their full mental state
- **Chat with Agents** — Direct LLM-powered conversation with any agent
- **Keyboard Shortcuts** — Space, 1/5/0, G, C, P, M, B, Esc
- **Event Injection** — Trigger disasters, migrants, resource bonuses
- **Save/Load** — Persist and restore world states via SQLite
- **LLM Settings** — Switch between Ollama (local) and Antigravity gateway (multi-model)

## 🏗️ Architecture

```
28+ Elixir modules across:
├── Mind        — Conatus, Affect, Perception, Reasoning, Learning
├── Intelligence — LLM providers (Ollama, Antigravity, Gemini)
├── Simulation  — World, Agent, Ticker, Economy, Lifecycle, Environment
├── Protocol    — Intent parsing, Command execution, Bridge
├── Persistence — SQLite-backed world and memory storage
├── Cerebro     — Social Network, Groups, Spatial Memory
└── Web         — Phoenix LiveView + Pixi.js renderer
```

## 🚀 Quick Start

### Prerequisites
- Docker & Docker Compose

### Run
```bash
docker compose up -d
# Open http://localhost:4000
```

### With Antigravity Gateway (multi-LLM)
```bash
# Set your Antigravity API key
export ANTIGRAVITY_API_KEY=sk-your-key
docker compose up -d
```

### Development
```bash
cd src
mix deps.get
mix ecto.migrate
mix phx.server
# Open http://localhost:4000
```

## 🧪 Tests
```bash
cd src
mix test          # 130+ tests
```

## 📖 Version History

| Version | Name | Theme |
|---------|------|-------|
| v0.5.0 | Genesis | Initial simulation |
| v0.6.0 | Imperium | Multi-step commands |
| v0.7.0 | Societas | Group dynamics |
| v0.8.0 | Memoria | Persistent memory |
| v0.9.0 | Natura | Dynamic environment |
| v1.0.0 | Substantia | Economy + lifecycle |
| v1.1.0 | Harmonia | UI/UX + performance |
| v1.2.0 | Infinitas | Large worlds + biomes |
| v1.3.0 | Sapientia | Learning + culture |
| v1.4.0 | Potentia | Storytelling + timeline |
| **v1.5.0** | **Deus** | **God Mode, Cinematic Camera, Final Polish** |

## 🔬 Philosophy

MODUS is built on Baruch Spinoza's *Ethics*:

- **Conatus** — Every being strives to persist in its own existence
- **Affects** — Emotions are transitions between states of power
- **Substance** — Everything is one interconnected system
- **Deus sive Natura** — The simulation IS the reality for its inhabitants

## 📄 License

MIT — NeuraByte Labs 2026
