# 🌌 MODUS

**Universe Simulation Platform — Every universe is a modus.**

Create AI-powered universe simulations where agents think, evolve, and interact.
Built with Elixir/BEAM for massive concurrency, Ollama for local AI.

> *"Deus sive Natura" — Each simulation is a modus, an individual expression of infinite substance.*

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
| `make test` | Run tests |
| `make logs` | Follow app logs |
| `make shell` | Shell into app container |
| `make llm-pull` | Download LLM model |
| `make clean` | Remove everything (fresh start) |
| `make status` | Check container & model status |

## Architecture

```
Browser (Pixi.js 2D) ←WebSocket→ Phoenix LiveView
                                      ↓
                              Elixir/OTP Engine
                          ┌─────────┬──────────┐
                          │ World   │ Agent    │
                          │ Ticker  │ Registry │
                          └────┬────┴────┬─────┘
                               │         │
                          ┌────┴────┐ ┌──┴───┐
                          │Decision │ │Ollama│
                          │ Engine  │ │(LLM) │
                          └─────────┘ └──────┘
```

## Requirements

- Docker Desktop
- That's it. Everything runs in containers.

## License

Private — NeuraByte Labs © 2026
