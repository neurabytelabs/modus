# MODUS Tech Radar

> v9.0.0 Anima — February 2026

## Overview

Technology assessment for MODUS platform development, categorized by adoption confidence.

---

## 🟢 Adopt — Production Ready

### Ollama (Local LLM)
- **Status**: Core infrastructure, fully integrated
- **Why**: Zero-cost inference, privacy-first, no API dependency
- **Models**: llama3.2:3b-instruct-q4_K_M (default), mistral, phi-3
- **Risk**: Low — mature project, active community

### ETS Caching
- **Status**: Used across all modules (settings, tutorial, notifications, cache)
- **Why**: In-memory, zero-latency, built into BEAM VM
- **Risk**: None — Erlang standard

### Phoenix LiveView
- **Status**: Primary UI framework
- **Why**: Real-time updates without JS complexity, server-rendered
- **Risk**: Low — Elixir ecosystem standard

### Phoenix Channels (WebSocket)
- **Status**: World state streaming, chat, events
- **Why**: Bi-directional real-time, built-in presence
- **Risk**: Low

### Tailwind CSS
- **Status**: All UI styling
- **Why**: Utility-first, fast iteration, small bundle
- **Risk**: None

---

## 🟡 Trial — Active Experimentation

### WebGPU Renderer (Pixi.js v8)
- **Status**: Evaluating for canvas-based world rendering
- **Why**: Hardware-accelerated 2D, 60fps with 200+ agents
- **Timeline**: v10 Nexus (Q2 2026)
- **Risk**: Medium — WebGPU browser support still maturing
- **Fallback**: Canvas 2D API (current)

### Edge AI (WebLLM)
- **Status**: Prototype phase
- **Why**: Run small models directly in browser, zero server cost
- **Timeline**: Q3 2026
- **Risk**: Medium — model size limits, browser memory constraints
- **Models**: Phi-3-mini, TinyLlama (quantized)

### Cloud LLM Integration (Gemini/GPT)
- **Status**: Gemini integrated, GPT planned
- **Why**: Higher quality responses for Pro/Studio tiers
- **Risk**: Low-Medium — API cost management needed

---

## 🔵 Assess — Research & Evaluation

### WASM Agents
- **Description**: Compile agent logic to WebAssembly for client-side execution
- **Why**: Reduce server load, enable offline simulation
- **Timeline**: Q3-Q4 2026
- **Risk**: High — complex compilation pipeline
- **Blocker**: Need stable agent behavior API first

### Multiplayer (Phoenix Presence)
- **Description**: Shared worlds with multiple users observing/interacting
- **Why**: Social features, classroom use, collaborative worldbuilding
- **Timeline**: v10 Nexus (Q2 2026)
- **Risk**: Medium — state synchronization complexity
- **Approach**: CRDT-based conflict resolution

### Voice Integration (TTS/STT)
- **Description**: Agents speak aloud, users give voice commands
- **Why**: Immersion, accessibility, education
- **Timeline**: Q4 2026
- **Risk**: Medium — latency, cost for cloud TTS
- **Options**: ElevenLabs (quality), Piper (local/free), Web Speech API

### Vector Database (Agent Memory)
- **Description**: Long-term agent memory via embeddings
- **Why**: Agents remember past interactions across sessions
- **Timeline**: v10+
- **Options**: Pgvector, Qdrant, in-memory HNSW

---

## 🔴 Hold — Not Now

### Mobile Native App (iOS/Android)
- **Reason**: Web-first strategy, LiveView works on mobile browsers
- **Revisit**: When user base exceeds 50K and mobile traffic > 40%
- **Alternative**: PWA with offline support

### Blockchain Integration
- **Reason**: No clear user value, adds complexity, regulatory risk
- **Revisit**: Only if marketplace requires decentralized ownership
- **Alternative**: Traditional payment + creator accounts

### Kubernetes Deployment
- **Reason**: Docker Compose sufficient for current scale
- **Revisit**: When needing auto-scaling beyond single server

### GraphQL API
- **Reason**: REST + WebSocket covers all current needs
- **Revisit**: When third-party integrations demand flexible querying

---

## Timeline: Q1–Q4 2026

| Quarter | Focus | Key Deliverables |
|---------|-------|-------------------|
| Q1 | Foundation | v9 Anima: Tutorial, Settings, Error Recovery, Docs |
| Q2 | Expansion | v10 Nexus: Multiplayer, WebGPU renderer, Marketplace beta |
| Q3 | Intelligence | Edge AI, WASM agents prototype, Voice TTS |
| Q4 | Scale | Education pilot, Enterprise features, Mobile PWA |

---

## 3-Sprint Plan

### 🌊 v9 Anima (Current — Q1 2026)
*"Breathing life into the system"*
- Interactive tutorial system
- Settings panel with persistence
- Error recovery UI
- Revenue model & tech radar documentation
- Stability & polish

### 🔗 v10 Nexus (Q2 2026)
*"Connecting worlds together"*
- Multiplayer shared worlds (Phoenix Presence)
- WebGPU-accelerated renderer
- Marketplace v1 (template sharing)
- Cloud LLM tier (Pro/Studio)
- API v1 for Studio tier

### 🌌 v11 Cosmos (Q3-Q4 2026)
*"The universe expands"*
- Marketplace with payments (Stripe)
- Education dashboard
- Voice integration
- Edge AI (WebLLM)
- Enterprise features
- Localization (EN, TR, DE, ES, FR, JP)
