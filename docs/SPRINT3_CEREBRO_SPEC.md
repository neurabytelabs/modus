# MODUS v0.4.0 — Sprint 3: Cerebro
## Technical Specification

> "The mind's power of thinking is equal to, and simultaneous with, the body's power of acting."  
> — Spinoza, Ethics III, Proposition 28

**Version:** v0.4.0 Cerebro  
**Date:** 2026-02-16  
**Author:** RUNE-enhanced (Grok-4 reasoning + Spinoza validation)  
**Hardware:** Mac Mini M4 16GB — target <20% CPU avg  
**Prerequisites:** v0.3.0 Affectus (Conatus + Affect + Memory + Reasoning)

---

## 1. Architecture Overview

```
mind_engine.ex (existing orchestrator)
  ├── conatus.ex ✅ (v0.2.0)
  ├── affect.ex ✅ (v0.2.0)
  ├── affect_memory.ex ✅ (v0.3.0)
  ├── reasoning_engine.ex ✅ (v0.3.0)
  └── cerebro/ (NEW — v0.4.0)
      ├── social_network.ex      — ETS relationship graph
      ├── agent_conversation.ex  — LLM agent-to-agent dialogue
      ├── spatial_memory.ex      — Joy-biased movement
      └── mind_view.ex           — LiveView affect visualization
```

**Data Flow per Tick:**
```
Agent.tick → MindEngine.process_tick
  → Conatus.update_energy (existing)
  → Affect.transition (existing)
  → SocialNetwork.decay_relationships (NEW, every 100 ticks)
  → SpatialMemory.bias_movement (NEW, modifies explore_target)
  → AgentConversation.maybe_converse (NEW, async Task)
  → AffectMemory.form_memory (existing)
  → MindView broadcasts (NEW, PubSub)
```

---

## 2. Feature Specifications

### 2.1 Social Network — `Modus.Mind.Cerebro.SocialNetwork`

**Purpose:** Track and evolve relationships between agents. Relationship strength gates conversation quality and affects conatus exchange.

**ETS Table:** `:social_network` (type: `:set`)
- Key: `{min(id1, id2), max(id1, id2)}` — canonical pair ordering
- Value: `%{strength: float, type: atom, last_interaction: integer, convo_count: integer}`

**Public API:**
```elixir
defmodule Modus.Mind.Cerebro.SocialNetwork do
  @moduledoc "Agent relationship graph stored in ETS"

  def init() :: :ok
  def get_relationship(id1, id2) :: map() | nil
  def update_relationship(id1, id2, event_type) :: :ok
  def get_friends(agent_id, min_strength \\ 0.3) :: [binary()]
  def decay_all(amount \\ 0.002) :: :ok
end
```

**Relationship Evolution:**
| Event | Delta | Condition |
|-------|-------|-----------|
| Conversation (joy) | +0.08 | Both agents joyful |
| Conversation (neutral) | +0.04 | Standard talk |
| Conversation (sad) | +0.06 | Empathy bonus |
| Shared danger (fear) | +0.10 | Both feared same tick |
| Natural decay | -0.002 | Every 100 ticks |

**Type Progression:** `stranger (0.0) → acquaintance (0.2) → friend (0.5) → close_friend (0.8)`

**Integration:**
- `SocialNetwork.init()` called in `Application.start/2`
- `update_relationship/3` called after conversations
- `get_friends/2` used by DecisionEngine for `:find_friend` target selection

**Tests:**
```elixir
test "relationship strengthens on conversation"
test "relationship decays over time"
test "type progresses with strength"
test "get_friends filters by min_strength"
test "canonical key ordering"
```

**Tick Cost:** 0.1ms (ETS read/write)

---

### 2.2 Agent-to-Agent Conversations — `Modus.Mind.Cerebro.AgentConversation`

**Purpose:** When two agents are nearby and one has `:talk` action, generate LLM dialogue that reflects both agents' affect states, personalities, and relationship history.

**Public API:**
```elixir
defmodule Modus.Mind.Cerebro.AgentConversation do
  @moduledoc "LLM-powered agent-to-agent conversations"

  def maybe_converse(agent, nearby_agents, tick) :: :ok | :skipped
  def build_conversation_prompt(agent1, agent2, relationship) :: String.t()
  def process_response(response, agent1_id, agent2_id, tick) :: :ok
end
```

**Trigger Conditions (ALL must be true):**
1. Agent action is `:talk` or `:find_friend`
2. At least one nearby agent within 3 tiles
3. Partner's conatus > 0.3 (not about to die)
4. No conversation between this pair in last 50 ticks (cooldown)
5. Global conversation limit: max 2 concurrent LLM conversations

**Prompt Template (Turkish):**
```
Sen {agent1.name} ({agent1.occupation}). {personality_desc1}
Şu an {affect1} hissediyorsun (conatus: {energy1}).
{agent2.name} ile karşılaştın. O bir {agent2.occupation}.
{relationship_context}
{memory_context}

Kısa ve doğal bir diyalog yaz (2-4 satır, Türkçe):
{agent1.name}: ...
{agent2.name}: ...
```

**Conversation Effects:**
- Both agents: social need -15.0 (significant social satisfaction)
- Conatus boost: +0.05 base, +0.03 if relationship > 0.5
- Affect transition: if both sad → chance of sadness→joy (the "Magic Moment")
- Relationship: +0.04 to +0.10 based on affect alignment
- Memory formation: episodic memory with conversation summary

**Async Execution:** `Task.start/1` to avoid blocking agent tick

**Tests:**
```elixir
test "conversation triggers for nearby talking agents"
test "cooldown prevents spam (50 tick minimum)"
test "conversation affects both agents' conatus and social needs"
test "sad+sad conversation can trigger joy transition"
test "prompt includes affect state and relationship context"
test "global limit of 2 concurrent conversations"
test "fallback dialogue when LLM unavailable"
```

**Tick Cost:** 0ms sync (Task.start), ~200ms async LLM (doesn't block tick)

---

### 2.3 Memory-Influenced Spatial Behavior — `Modus.Mind.Cerebro.SpatialMemory`

**Purpose:** Agents remember locations associated with positive/negative experiences and bias their movement accordingly. Joy-associated locations attract; fear-associated repel.

**Public API:**
```elixir
defmodule Modus.Mind.Cerebro.SpatialMemory do
  @moduledoc "Spatial memory biases agent movement toward joy locations"

  def bias_explore_target(agent_id, current_pos, default_target) :: {integer, integer}
  def record_location_affect(agent_id, position, affect_state, tick) :: :ok
  def get_joy_locations(agent_id, limit \\ 5) :: [{pos, joy_score}]
  def get_fear_locations(agent_id, limit \\ 3) :: [{pos, fear_score}]
end
```

**Uses existing `AffectMemory` ETS** — no new table needed. Queries memories by affect_to field.

**Algorithm:**
```
1. Query AffectMemory for agent's joy memories (salience > 0.3)
2. Query AffectMemory for agent's fear memories (salience > 0.5)
3. If joy_locations exist and random(0,1) < 0.4:
   - Pick weighted random joy location (weight = salience)
   - Return that as explore_target (30% pull, 70% original)
4. If fear_locations exist and distance < 5 tiles:
   - Repel: return target away from fear location
5. Else: return default_target unchanged
```

**Integration:** Called in `Agent.tick/2` after DecisionEngine decides `:explore`
```elixir
# In agent.ex, after explore_target selection:
{action, params, agent} = case action do
  :explore ->
    target = SpatialMemory.bias_explore_target(agent.id, agent.position, params.target)
    {action, %{params | target: target}, agent}
  ...
end
```

**Tests:**
```elixir
test "agent biases toward joy memory location"
test "agent avoids fear memory location"
test "no bias when no memories exist"
test "salience threshold filters weak memories"
test "40% chance of joy bias (probabilistic)"
```

**Tick Cost:** 0.3ms (ETS scan + vector math)

---

### 2.4 Cerebro Mind View — LiveView + Renderer Enhancement

**Purpose:** Visual display of agent mental states — affect colors already exist, add: relationship lines, conversation bubbles, mind state tooltip.

**No new Elixir module** — extends existing `universe_live.ex` and `renderer.js`

**UI Additions:**

1. **Relationship Lines (renderer.js)**
   - Draw faint lines between agents with relationship > 0.3
   - Line color: white (acquaintance), green (friend), gold (close_friend)
   - Line opacity = relationship strength
   - Only render for visible agents (camera viewport culling)

2. **Conversation Bubbles (renderer.js)**
   - When conversation event occurs, show speech bubble emoji (💬) above both agents
   - Fade after 3 seconds
   - Show mini text snippet if zoomed in enough

3. **Mind State Panel Enhancement (universe_live.ex)**
   - Add "Relationships" section to agent detail (list friends + strength bars)
   - Add "Joy Locations" mini-map (dots on small map showing remembered joy spots)
   - Add "Recent Conversations" list with dialogue snippets

4. **Global Mind View Toggle (new panel)**
   - Button in top bar: "🧠 Mind View"
   - Overlay mode: dims terrain, brightens agent connections
   - Shows affect flow: animated particles along relationship lines
   - Color = average affect between connected agents

**Channel Data Extensions:**
```elixir
# In world_channel.ex get_agent_list:
%{
  ...existing fields...,
  friends: SocialNetwork.get_friends(state.id) |> Enum.take(5),
  conversing_with: state.conversing_with  # nil or agent_id
}

# New channel event for conversations:
push(socket, "conversation", %{
  agents: [id1, id2],
  dialogue: [...],
  tick: tick
})
```

**Tests:**
```elixir
test "relationship lines rendered for friends"
test "conversation bubble appears on event"
test "mind view toggle dims terrain"
test "agent detail shows relationships"
```

**Tick Cost:** ~1ms extra per delta (serializing friend list), renderer: 2-3ms (line drawing)

---

## 3. Implementation Plan

### Phase A: Foundation (est. 1 session)
1. `SocialNetwork` module + ETS init + tests
2. Wire into `Application.start/2`
3. `update_relationship` called from existing `world_channel.ex` fallback conversations

### Phase B: Conversations (est. 1 session)
1. `AgentConversation` module
2. Prompt template with affect/personality/memory context
3. Wire into `MindEngine.process_tick` or `Agent.tick`
4. Cooldown tracking, global limit
5. Effects: social need, conatus boost, affect transition, memory formation

### Phase C: Spatial Memory (est. 30 min)
1. `SpatialMemory` module using existing AffectMemory
2. Integrate into `Agent.tick` explore_target selection

### Phase D: Mind View (est. 1 session)
1. Relationship lines in renderer.js
2. Conversation bubbles
3. Agent detail panel extensions
4. Global mind view toggle

### Phase E: Integration + Polish (est. 30 min)
1. Wire all modules into MindEngine
2. Performance measurement (Telemetry)
3. Tune thresholds
4. Test the Magic Moment scenario

---

## 4. Performance Budget

| Component | Per Tick/Agent | Notes |
|-----------|---------------|-------|
| SocialNetwork ETS | 0.1ms | Read/write |
| SpatialMemory | 0.3ms | ETS scan + math |
| AgentConversation check | 0.1ms | Eligibility only |
| AgentConversation LLM | 0ms sync | Async Task (~200ms) |
| MindView broadcast | 0.2ms | PubSub |
| **Total new overhead** | **~0.7ms/agent** | Within 5ms budget |

**LLM Budget:** Max 2 concurrent conversations = max 2 Antigravity calls at a time. At ~200ms each, this is negligible on M4.

---

## 5. Magic Moment Scenario

```
Tick N:   Agent "Emre" (sadness, conatus 0.4) wanders near Agent "Selin" (sadness, conatus 0.35)
Tick N+1: AgentConversation triggers — both sad, nearby, talk action
          LLM prompt includes: both sad, low conatus, shared memories of hardship
Tick N+2: LLM response: 
          Emre: "Selin, bu köy zor ama birlikte daha güçlüyüz."
          Selin: "Haklısın Emre, işbirliği gücümüzü artırır."
Tick N+3: Effects applied:
          - Both social need: -15
          - Conatus boost: +0.08 (base +0.05, empathy +0.03)
          - Affect: sadness → joy (empathetic conversation trigger)
          - Colors: blue → gold (renderer)
          - Memory: "Emre ile konuştuk, umut döndü" (episodic)
          - Relationship: stranger → acquaintance (+0.06)
Tick N+4: MindView shows gold particles flowing between Emre and Selin
          Event log: "Emre ve Selin'in konuşması umut getirdi 💛"
```

---

## 6. File Changes Summary

| File | Change |
|------|--------|
| `lib/modus/mind/cerebro/social_network.ex` | NEW |
| `lib/modus/mind/cerebro/agent_conversation.ex` | NEW |
| `lib/modus/mind/cerebro/spatial_memory.ex` | NEW |
| `lib/modus/mind/mind_engine.ex` | Add cerebro hooks |
| `lib/modus/simulation/agent.ex` | Add spatial bias, conversation state |
| `lib/modus_web/channels/world_channel.ex` | Add friends, conversation events |
| `lib/modus_web/live/universe_live.ex` | Relationships panel, mind view |
| `assets/js/renderer.js` | Relationship lines, convo bubbles |
| `lib/modus/application.ex` | SocialNetwork.init() |
| `test/mind/cerebro/` | NEW test files |

---

*Generated with RUNE v4.3 + Grok-4 Reasoning + Spinoza Validation*  
*"Conatus is not merely survival — it is the striving to increase one's power of acting."*
