# 🌌 MODUS

**Universe Simulation Platform — Every universe is a modus.**

Create AI-powered universe simulations where agents think, evolve, and interact.
Built with Elixir/BEAM for massive concurrency, Ollama for local AI decisions.

> *"Deus sive Natura" — Each simulation is a modus, an individual expression of infinite substance.*

## ✨ Features

- **World Generation** — Procedural terrain (grass, water, forest, mountain) with resource nodes
- **Autonomous Agents** — GenServer-based agents with needs (hunger, social, rest, shelter), personality traits, memory, and relationships
- **Decision Engine** — Behavior trees + Ollama LLM batch decisions with caching
- **Conatus Score** — Spinoza-inspired persistence metric for each agent
- **2D Renderer** — Pixi.js v8 with terrain tiles, agent sprites, camera controls, and minimap
- **Real-time UI** — Phoenix LiveView + WebSocket channels, event log, agent detail panel, chat system
- **Agent Conversations** — Agents talk to each other based on proximity and social needs
- **Onboarding** — World creation wizard with templates (Village, Wilderness, Island, Metropolis)
- **Performance** — 50 agents tick in <200ms, ETS-backed grid, OTP supervision trees

## Quick Start

```bash
git clone git@github.com:neurabytelabs/modus.git
cd modus
chmod +x scripts/setup.sh
./scripts/setup.sh
```

Then visit: **http://localhost:4000**

## Commands

| Command | Description |
|---------|-------------|
| `make up` | Start all containers |
| `make down` | Stop all containers |
| `make test` | Run tests (61 tests) |
| `make logs` | Follow app logs |
| `make shell` | Shell into app container |
| `make llm-pull` | Download LLM model |
| `make clean` | Remove everything (fresh start) |
| `make status` | Check container & model status |

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   Browser                        │
│  ┌──────────────┐  ┌────────────┐  ┌──────────┐│
│  │ Pixi.js v8   │  │ Event Log  │  │  Chat    ││
│  │ 2D Renderer  │  │ + Filters  │  │  Panel   ││
│  └──────┬───────┘  └─────┬──────┘  └────┬─────┘│
│         └────────────┬───┘───────────────┘      │
└──────────────────────┼──────────────────────────┘
                WebSocket (Phoenix Channels)
┌──────────────────────┼──────────────────────────┐
│               Phoenix LiveView                   │
│  ┌─────────────┐  ┌──────────┐  ┌────────────┐ │
│  │ UniverseLive│  │ WorldCh. │  │ UserSocket │ │
│  └──────┬──────┘  └────┬─────┘  └────────────┘ │
│         └──────────┬───┘                        │
│  ┌─────────────────┼────────────────────────┐   │
│  │          Simulation Engine                │   │
│  │ ┌───────┐ ┌────────┐ ┌───────────────┐  │   │
│  │ │ World │ │ Ticker  │ │ AgentSuperv.  │  │   │
│  │ │ (ETS) │ │ (50ms)  │ │ (DynamicSup)  │  │   │
│  │ └───────┘ └────────┘ └───────┬───────┘  │   │
│  │                              │           │   │
│  │ ┌──────────┐ ┌───────────┐ ┌┴────────┐  │   │
│  │ │ Decision │ │ Behavior  │ │  Agent   │  │   │
│  │ │ Engine   │ │   Tree    │ │(GenSrv.) │  │   │
│  │ └─────┬────┘ └───────────┘ └─────────┘  │   │
│  │       │                                  │   │
│  │ ┌─────┴────┐ ┌───────────┐              │   │
│  │ │  Ollama  │ │ Decision  │              │   │
│  │ │  Client  │ │   Cache   │              │   │
│  │ └──────────┘ └───────────┘              │   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
         Docker Compose (modus-app + modus-llm)
```

## Tech Stack

- **Backend:** Elixir 1.17 + Phoenix 1.7 + OTP/BEAM
- **AI:** Ollama (local LLM, tinyllama)
- **Frontend:** Phoenix LiveView + Pixi.js v8 + Tailwind CSS
- **Storage:** ETS (grid), PostgreSQL (persistence), DecisionCache (ETS)
- **Infra:** Docker Compose (2 containers)

## Project Structure

```
src/
├── lib/
│   ├── modus/
│   │   ├── simulation/     # World, Agent, Ticker, DecisionEngine, EventLog
│   │   ├── intelligence/   # BehaviorTree, OllamaClient, DecisionCache, LLMScheduler
│   │   └── application.ex  # OTP app + supervision tree
│   └── modus_web/
│       ├── live/            # UniverseLive (main UI)
│       └── channels/        # WorldChannel (WebSocket)
├── assets/js/
│   ├── renderer.js          # Pixi.js 2D renderer
│   ├── world_socket.js      # WebSocket client
│   └── app.js               # Entry point
└── test/                    # 61 tests (unit + integration)
```

## Requirements

- Docker Desktop
- That's it. Everything runs in containers.

## License

Private — NeuraByte Labs © 2026
