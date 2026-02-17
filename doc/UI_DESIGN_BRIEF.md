# MODUS — UI/UX Design Brief

> **For**: World-class UI/UX Designer
> **Product**: MODUS — A Living Universe Simulation Platform
> **Philosophy**: Spinoza's "Deus sive Natura" (God, or Nature)
> **Version**: v2.5.0 "Memoria"
> **Renderer**: 2D top-down (Pixi.js), Phoenix LiveView shell
> **Target**: Desktop-first web application (1440p+, responsive down to 1024px)

---

## 1. What Is This Product?

MODUS is a universe simulation platform where users create worlds, define physics rules, and populate them with AI-powered agents that have **genuine inner lives** — emotions, memories, personality, relationships, goals, and culture. These agents are not scripted characters; they are autonomous minds that form friendships, build homes, develop traditions, survive seasons, and write their own history.

The user is the **creator-observer**. They paint terrain, set rules, spawn agents, and then **watch emergence happen**. They can intervene as a god, chat with individual agents, or simply watch civilizations unfold in real-time.

**Core metaphor**: You are looking down at a living terrarium. Each tiny dot is a mind. The beauty is in what emerges.

---

## 2. Design Philosophy & Feeling

### The Mood
- **Contemplative, not gamified.** This is not a city builder or a strategy game. It's closer to watching a living painting.
- **Dense but serene.** Lots of information available, but the default state is calm observation.
- **Scientific elegance.** Think: observatory control room meets nature documentary meets philosophy journal.
- **Dark mode dominant.** The world map is the centerpiece — UI chrome should recede, not compete.

### Design Principles
1. **The World is the Hero** — UI panels are secondary. The 2D map with its colored dots, buildings, terrain, and weather effects should dominate the viewport.
2. **Progressive Disclosure** — Surface-level: beautiful, minimal. One click deeper: rich data. Two clicks: god-level omniscience.
3. **Information Density without Clutter** — This product has enormous data depth per agent (5 emotions, 5 personality traits, 4 needs, 100 memories, N relationships, goals, catchphrases, inventory). Design must make this explorable, not overwhelming.
4. **Living Interface** — UI itself should feel alive. Subtle animations, breathing elements, real-time data streams. Nothing should feel static.
5. **Spinoza Aesthetic** — Named versions after philosophical concepts. Typography and visual language should echo: 17th-century rationalism meets modern minimalism. Serifs for headers, monospace for data, sans-serif for body.

---

## 3. Screens & Views

### 3.1 Landing Page
**Purpose**: First impression. Explain the product, invite creation.

**Elements**:
- Hero section with animated world preview (Pixi.js embed showing a living simulation)
- Product tagline: "Design worlds. Seed minds. Watch civilizations emerge."
- CTA: "Create Your Universe" / "Explore a Random World"
- Feature highlights (3-4 cards)
- Philosophy blurb (Spinoza quote)

---

### 3.2 Multi-Universe Dashboard
**Purpose**: Manage all created worlds.

**Elements**:
- **World Cards** (grid or list layout):
  - World name (editable)
  - Template icon/badge (Village, Island, Desert, Space, Underwater, Medieval, Cyberpunk, Jungle, Arctic, Volcanic, Cloud City)
  - Population count (live)
  - World age (Year X, Season Y)
  - Current season indicator (Spring 🌸 / Summer ☀️ / Autumn 🍂 / Winter ❄️)
  - Happiness percentage (color-coded)
  - Thumbnail preview (minimap render)
  - Last active timestamp
- **Sort controls**: by age, population, creation date, happiness
- **Actions**: Create New, Import (JSON/share code), Delete
- **Create New World** button (prominent, leads to World Builder)
- **Quick Start**: "Random World" one-click generation

---

### 3.3 World Builder (Pre-Simulation Setup)
**Purpose**: Design terrain, choose template, set initial rules.

**Elements**:
- **Canvas** (100×100 grid): paintable terrain map
- **Terrain Palette** (sidebar or bottom bar):
  - Grass (🟩 green)
  - Water (🟦 blue)
  - Forest (🌲 dark green)
  - Mountain (⛰️ grey)
  - Desert (🏜️ sand/yellow)
  - Farm (🌾 golden)
  - Flowers (🌸 pink)
- **Brush Tools**: single tile, 3×3 area, fill, eraser
- **Template Selector**: 11 presets with preview thumbnails
  - Each template pre-fills terrain + rules + starting agents
- **Rules Panel** (collapsible sidebar):
  - Time Speed slider (0.5x – 3.0x)
  - Resource Abundance: Scarce / Normal / Abundant
  - Danger Level: Peaceful / Moderate / Harsh / Extreme
  - Social Tendency slider (0.0 – 1.0)
  - Birth Rate slider (0.0 – 2.0x)
  - Building Speed slider (0.5 – 3.0x)
  - Mutation Rate slider (0.0 – 1.0)
  - 5 Rule Presets: Peaceful Paradise, Harsh Survival, Chaotic, Utopia, Evolution Lab
- **Agent Placement**: drag-and-drop agent spawners onto map
- **Start Simulation** button (prominent)

---

### 3.4 Main Simulation View (The Core Experience)
**Purpose**: The primary screen. Watch the world live.

This is the most important screen. It's where users spend 95% of their time.

#### Layout Zones

```
┌─────────────────────────────────────────────────────────┐
│ [Top Bar]                                               │
├────────┬────────────────────────────────────┬───────────┤
│        │                                    │           │
│ [Left  │        [WORLD MAP]                 │  [Right   │
│ Panel] │        (Pixi.js Canvas)            │  Panel]   │
│        │                                    │           │
│        │                                    │           │
│        │                                    │           │
├────────┴────────────────────────────────────┴───────────┤
│ [Bottom Bar / Story Feed]                               │
└─────────────────────────────────────────────────────────┘
```

#### 3.4.1 Top Bar
- World name
- **Time controls**: Play ▶ / Pause ⏸ / Speed (0.5x, 1x, 2x, 3x)
- **Clock display**: Year X, Season (with icon), Day/Night phase indicator
- **Population counter** (live)
- **Happiness index** (small bar or percentage)
- **Mode switcher**: Normal / Text (T) / Zen (Z) / God (G)
- **Settings gear** → LLM provider picker, sound toggle, etc.
- **Export/Share** button

#### 3.4.2 World Map (Center — Pixi.js Canvas)
- **Terrain tiles**: colored squares on a grid
  - Grass: soft green
  - Water: blue with subtle animation
  - Forest: dark green with tree icons
  - Mountain: grey with height shading
  - Desert: warm sand
  - Farm: golden-green
  - Flowers: pink accents
- **Agents**: small colored dots (4-6px radius)
  - Color indicates current affect state:
    - Joy: warm yellow/gold
    - Sadness: cool blue
    - Desire: vibrant green
    - Fear: red/orange
    - Neutral: white/light grey
  - Movement: smooth interpolation between tiles
  - Subtle glow/pulse when affect changes
  - Name label on hover
  - Click to select → opens Agent Detail Panel
- **Buildings**: icons or small sprites
  - Hut: small brown square
  - House: medium structure
  - Mansion: larger ornate structure
  - Farm: crop pattern
  - Market: stall icon
  - Well: circle
  - Watchtower: tall thin structure
  - Health indicator (opacity or crack overlay)
- **Wildlife**: tiny colored dots (smaller than agents)
  - Deer, rabbits, wolves, birds, fish
- **Neighborhoods**: subtle boundary highlights or name labels over clusters
- **World Events overlay**:
  - Storm: dark swirling overlay
  - Earthquake: shaking screen effect
  - Meteor Shower: sparkle particles
  - Plague: green mist
  - Golden Age: warm glow
  - Flood: water level rise
  - Fire: red/orange particles
- **Day/Night cycle**: ambient color overlay
  - Dawn: warm amber
  - Day: bright, natural
  - Dusk: purple/magenta
  - Night: deep dark blue (agents glow slightly)
  - Pre-dawn: subtle lightening
- **Season visual overlay**:
  - Spring: green tint, occasional floating particles
  - Summer: golden tint, heat shimmer
  - Autumn: orange tint, falling leaf particles
  - Winter: blue-white tint, snow particles
- **Camera**: pan (drag), zoom (scroll), follow agent (double-click)
- **Mini-map**: small overview in corner (toggleable)

#### 3.4.3 Left Panel — Agent List & Quick Info
- **Collapsible** (toggle with hotkey or click)
- **Agent list**: scrollable, searchable
  - Each entry: agent name, affect icon, conatus bar (tiny), current action
  - Sort by: name, age, happiness, conatus
  - Filter by: affect state, alive/dead, occupation
- **Selected Agent Quick Card** (when an agent is clicked):
  - Name + age
  - Affect state (icon + label)
  - Conatus energy bar (visual, 0-100%)
  - Current action label
  - "View Details" button → opens full Agent Detail

#### 3.4.4 Right Panel — Context-Sensitive
**Changes based on what's selected or what mode is active.**

**Default (nothing selected)**: World Stats
- Population (current / all-time)
- Buildings count by type
- Current season + year
- Active world events
- Average happiness
- Trade volume (today)
- Recent births / deaths

**Agent Selected**: Agent Detail Panel (see Section 3.5)

**Building Selected**: Building Detail
- Type + level
- Owner (link to agent)
- Health bar
- Area bonuses it provides
- Nearby residents

**God Mode Active**: God Controls (see Section 3.7)

#### 3.4.5 Bottom Bar — Story Feed & Timeline
- **Scrolling narrative feed** (real-time):
  - "[Agent Name] built a hut near the river."
  - "[Agent A] and [Agent B] became friends."
  - "A storm struck the eastern mountains."
  - "Winter has arrived. Year 3 begins."
  - "[Agent Name] said: 'Fortune favors the persistent!'"
  - "[Agent Name] died. Conatus extinguished."
- Each entry: timestamp (tick/year), icon by event type, brief text
- Clickable agent names → select that agent
- Filter by: event type (social, building, disaster, birth/death, cultural)
- **Timeline scrubber** (optional): visual indicator of world age with event markers

---

### 3.5 Agent Detail Panel (Deep Dive)
**Purpose**: Full agent inspection. The mind viewer.

**This is where the product's depth shines. Design this to feel like looking into a soul.**

#### Section: Identity
- **Name** (large, prominent)
- **Age** (in ticks and equivalent years)
- **Occupation**: Explorer / Trader / Farmer / etc.
- **Portrait area**: abstract generative avatar based on personality traits (geometric, not a face)
- **Alive status** indicator

#### Section: Emotional State (Affects)
- **Current affect**: large icon + label (Joy / Sadness / Desire / Fear / Neutral)
- **Affect history graph**: timeline showing emotional transitions over last N ticks
  - X-axis: time (ticks)
  - Y-axis: affect states (color-coded)
  - Hoverable points show trigger event

#### Section: Conatus (Life Force)
- **Energy bar**: 0.0 – 1.0, color gradient (red → yellow → green)
- **Score**: -10 to +10 (cumulative measure)
- **Conatus history graph**: line chart over time
- **Trend indicator**: rising / falling / stable

#### Section: Personality (Big Five Radar)
- **Radar/spider chart** with 5 axes:
  - Openness
  - Conscientiousness
  - Extraversion
  - Agreeableness
  - Neuroticism
- Each 0.0 – 1.0
- Static (set at birth, rarely changes)

#### Section: Needs
- **4 horizontal bars**:
  - Hunger (0–100) — icon: food
  - Rest (0–100) — icon: moon/bed
  - Social (0–100) — icon: people
  - Shelter (0–100) — icon: house
- Color-coded: green (satisfied) → yellow (moderate) → red (critical)
- Subtle animation when a need is critically low (pulsing red)

#### Section: Relationships
- **List of known agents** with:
  - Agent name (clickable → switch to that agent)
  - Relationship type: Stranger / Acquaintance / Friend / Close Friend
  - Strength bar (0.0 – 1.0)
  - Last interaction info
- **Mini relationship graph** (optional): small network visualization of this agent's connections

#### Section: Goals
- **Active goals** list (max ~5):
  - Goal name: Build Home / Make Friends / Explore Map / Gather Resources / Survive Winter
  - Progress bar (0% – 100%)
  - Status icon: in-progress / completed
- Completed goals greyed out or in separate "achieved" section

#### Section: Memory (Episodic)
- **Memory list** (scrollable, newest first):
  - Type badge: 🎯 Event / 👥 Social / 📍 Spatial / 💭 Emotional
  - Content text (one-liner description)
  - Age (how many ticks ago)
  - Weight/salience bar (fading = decaying memory)
  - Related agent name if applicable
- Memory count: "47 / 100 memories"
- Optional: **Memory map** — spatial visualization of where memories were formed on the world grid

#### Section: Culture
- **Catchphrases** (list):
  - Quote text in italics
  - Context tag (hunger, success, social, fear, etc.)
  - Strength indicator
  - Origin: "learned from [Agent]" or "original"
- **Traditions participated in**:
  - Tradition name
  - Last performed

#### Section: Inventory
- Simple grid/list:
  - Wood: N
  - Stone: N
  - Food: N
- Home owned: [Building type] at (x, y) — or "Homeless"

#### Section: Reasoning (LLM Thoughts)
- **Last reasoning** output (quoted block):
  - "I have been sad for many days. Perhaps I should seek company..."
- Trigger info: "Triggered after 50 ticks of sadness"
- This section gives the uncanny feeling of reading a mind

#### Section: Chat
- **Integrated chat input** at the bottom of the panel
- User types message → agent responds in character
- Chat history (scrollable)
- Agent's responses reflect personality, memories, current emotional state
- Message types: free chat, location query, status query, relationships query, commands

---

### 3.6 Observatory Dashboard
**Purpose**: Analytics and metrics for the whole world.

**Opens as an overlay or separate panel (modal/drawer).**

#### Charts & Visualizations:
1. **Population Over Time** — line chart (sampled, up to 50 points)
2. **Happiness Index** — color-coded bar chart (green/amber/red per snapshot)
3. **Trade Volume** — area chart showing economic activity
4. **Building Breakdown** — horizontal bar chart by type (Hut, House, Mansion, Farm, Market, Well, Watchtower)
5. **Relationship Network** — SVG graph visualization
   - Agents as nodes (positioned in a circle)
   - Edges colored by relationship strength (weak=grey, strong=gold)
   - Max ~50 edges displayed
   - Hoverable nodes show agent name + connections
6. **Leaderboards** (Top 5 each):
   - Most Social (most relationships)
   - Wealthiest (most inventory)
   - Happiest (highest conatus)
   - Oldest (most ticks alive)

#### Summary Stats:
- Current population / Peak population
- Total buildings / by type
- Average happiness %
- Average conatus %
- Total trades
- Total births / deaths
- Current era name (The Founding / Expansion / Great Famine / Golden Age / Renaissance / Age of Conflict)

#### Auto-refresh: every 50 ticks when open

---

### 3.7 God Mode Interface
**Purpose**: Full omniscience and world control.

**Activated by pressing G or clicking God Mode button.**

**Visual change**: UI gets a subtle golden border/glow. "GOD MODE" indicator visible.

#### God Powers Panel:
- **Event Triggers** — 7 buttons in a grid:
  - ⛈️ Storm
  - 🌋 Earthquake
  - ☄️ Meteor Shower
  - 🦠 Plague
  - ✨ Golden Age
  - 🌊 Flood
  - 🔥 Fire
  - Each with severity selector (1-3)
- **Place Building** — select type, click on map to place
- **Spawn Agent** — click on map to spawn a new agent
- **Terrain Painter** — same palette as World Builder, paint in real-time
- **Cinematic Camera** — auto-follows interesting events (toggle)
- **Agent Omniscience**: clicking any agent shows ALL internals:
  - Full memory dump
  - Full relationship map
  - Decision tree state
  - LLM reasoning history
  - Raw conatus/affect numbers

---

### 3.8 Text Mode (T)
**Purpose**: Pure text/unicode representation. Works in constrained environments.

- Entire world rendered as a unicode grid:
  - 🟩 Grass, 🟦 Water, 🌲 Forest, ⛰️ Mountain, 🏜️ Desert, 🌾 Farm, 🌸 Flowers
  - Agents: colored emoji dots
  - Buildings: 🛖 🏠 🏛️ 🌾 🏪 🪣 🗼
- Story feed as scrolling text below
- Agent info as text panels
- Keyboard-only navigation

### 3.9 Zen Mode (Z)
**Purpose**: Pure observation. Hide all UI.

- All panels hidden
- Only the world map visible (full viewport)
- Subtle story text overlay at bottom (fades in/out)
- Click anywhere to exit Zen Mode
- Optional ambient music indicator

---

### 3.10 World History & Chronicle
**Purpose**: Review the world's story.

#### Elements:
- **Era Timeline**: horizontal visual showing eras with transitions
  - Each era: name, duration, key events
  - Era icons/colors: Founding (blue), Expansion (green), Famine (red), Golden Age (gold), Renaissance (purple), Conflict (dark red)
- **Key Figures**: notable agents with achievements
  - Title: "The Great Merchant", "The Elder", "The Builder"
  - Achievements list
- **Event Log**: filterable scrolling list of all major events
- **Export**: "Download Chronicle" → markdown file

---

### 3.11 Settings Panel
**Purpose**: Configuration.

#### Sections:
- **LLM Provider**: Ollama (local) / Antigravity / Gemini
  - Model selection per provider
  - Connection status indicator
- **Simulation**: time speed, tick interval
- **Display**: dark/light mode, particle effects toggle, UI scale
- **Audio**: ambient sounds toggle, volume (if applicable)
- **Keyboard shortcuts** reference

---

### 3.12 Export & Share Modal
**Purpose**: Share worlds with others.

#### Elements:
- **Export as JSON**: download full world state
- **Generate Share Code**: compressed base64 string (copy to clipboard)
- **Import**: file upload or paste share code
- **Download Chronicle**: markdown narrative export
- **Screenshot**: capture current view with branding overlay

---

## 4. UI Component Inventory

### Atoms (Smallest Elements)
| Component | Description | States |
|-----------|-------------|--------|
| AffectBadge | Colored icon for emotional state | joy (gold), sadness (blue), desire (green), fear (red), neutral (grey) |
| ConatusBar | Horizontal energy bar | 0-100%, gradient red→yellow→green |
| NeedBar | Horizontal need indicator | 0-100, green→yellow→red, pulsing when critical |
| SeasonIcon | Current season indicator | 🌸 spring, ☀️ summer, 🍂 autumn, ❄️ winter |
| DayPhaseIndicator | Ambient time of day | dawn, day, dusk, night, pre-dawn (color dot) |
| RelationshipStrength | Small bar showing bond level | 0.0-1.0, with type label |
| GoalProgress | Mini progress bar | 0-100%, with goal icon |
| MemoryWeightDot | Decaying salience indicator | full → fading opacity |
| EventTypeIcon | Icon per event category | storm, earthquake, meteor, plague, golden, flood, fire |
| TraitAxis | Single personality trait display | label + 0.0-1.0 bar |
| BuildingIcon | Small building representation | by type + health opacity |
| TickCounter | Live simulation tick display | incrementing number |
| AgentDot | The agent on the map | colored by affect, sized by conatus, glowing on change |

### Molecules (Composed Elements)
| Component | Composed Of | Usage |
|-----------|-------------|-------|
| AgentCard | AffectBadge + ConatusBar + name + action label | Agent list item, quick selection |
| AgentMiniProfile | AgentCard + personality radar thumbnail | Hover tooltip on map |
| NeedsPanel | 4× NeedBar (hunger, rest, social, shelter) | Agent detail section |
| PersonalityRadar | 5× TraitAxis arranged as spider/radar chart | Agent detail section |
| MemoryEntry | MemoryWeightDot + type badge + content + age | Memory list item |
| RelationshipRow | Agent name + RelationshipStrength + type label | Relationships list item |
| GoalRow | Goal name + GoalProgress + status icon | Goals list item |
| CatchphraseCard | Quote text + context tag + strength + origin | Culture section item |
| BuildingDetail | BuildingIcon + type + level + health bar + owner | Building selection panel |
| WorldStatsBlock | Label + value + trend arrow | Dashboard stat display |
| EventTriggerButton | EventTypeIcon + severity selector | God Mode event grid |
| WorldCard | Thumbnail + name + pop + season + happiness + age | Dashboard world list |
| TimeControls | Play/Pause + speed buttons + clock display | Top bar |
| StoryFeedEntry | Timestamp + EventTypeIcon + narrative text | Bottom feed |
| ChatBubble | Agent avatar + message text + timestamp | Chat interface |
| LeaderboardRow | Rank + agent name + metric value | Observatory leaderboard |

### Organisms (Complex Sections)
| Component | Contains | Screen |
|-----------|----------|--------|
| TopBar | TimeControls + world name + mode switcher + population + happiness + settings + export | Main View |
| AgentListPanel | Search + sort/filter + scrollable AgentCard list | Left Panel |
| AgentDetailPanel | All agent sections (identity through chat) | Right Panel |
| WorldStatsPanel | Multiple WorldStatsBlock + event indicators | Right Panel (default) |
| StoryFeed | Scrollable StoryFeedEntry list + filters | Bottom Bar |
| ObservatoryDashboard | 6 charts + summary stats + leaderboards | Overlay/Modal |
| GodControlsPanel | Event grid + building placer + agent spawner + terrain painter | Right Panel (God Mode) |
| WorldBuilder | Canvas + terrain palette + brush tools + template selector + rules panel | Setup Screen |
| RelationshipGraph | SVG node-link diagram | Observatory |
| MiniMap | Scaled-down world view with viewport indicator | Map overlay corner |
| ChatInterface | Chat history + input field + send button | Agent Detail sub-section |
| RulesEditor | 7 sliders/selectors + 5 preset buttons | World Builder sidebar |
| TerrainPalette | 7 terrain type buttons + brush tools | World Builder toolbar |
| ChronicleView | Era timeline + key figures + event log | History overlay |
| SettingsModal | LLM config + display + audio + shortcuts | Modal overlay |
| ExportShareModal | Export/import/share/screenshot options | Modal overlay |

---

## 5. Interaction Patterns

### Map Interactions
| Action | Result |
|--------|--------|
| Click agent dot | Select agent → show detail panel |
| Double-click agent | Camera follows agent |
| Hover agent | Show mini profile tooltip |
| Click building | Show building detail |
| Click empty terrain | Deselect (show world stats) |
| Drag | Pan camera |
| Scroll | Zoom in/out |
| Right-click (God Mode) | Context menu (place building, spawn agent, change terrain) |

### Keyboard Shortcuts
| Key | Action |
|-----|--------|
| `Space` | Play / Pause simulation |
| `T` | Toggle Text Mode |
| `Z` | Toggle Zen Mode |
| `G` | Toggle God Mode |
| `M` | Toggle Mini-map |
| `O` | Open Observatory |
| `H` | Open World History |
| `Esc` | Close panel / Deselect / Exit mode |
| `1-5` | Set simulation speed (0.5x to 3x) |
| `Tab` | Cycle through agents |
| `/` | Focus story feed search/filter |

### Real-Time Updates
- **Everything is live.** No page refreshes.
- Agent positions update via WebSocket (Phoenix Channel) every tick (100ms default).
- Charts in Observatory auto-refresh every 50 ticks when visible.
- Story feed streams events as they happen.
- Season/day-night transitions are smooth CSS/shader animations.

---

## 6. Data Density Reference

To help size panels and plan information architecture:

| Entity | Data Points Per Instance |
|--------|------------------------|
| Agent | ~25 primary fields + 100 memories + N relationships + 5 goals + N catchphrases + inventory + chat history |
| Building | 7 fields (type, position, owner, health, level, tick, bonuses) |
| World Event | 6 fields (type, duration, severity, radius, position, effects) |
| World | 100×100 terrain grid + rules (7 params) + season state + history + population metrics |
| Relationship | 4 fields per edge (agents, type, strength, last_interaction) |
| Memory | 10 fields (type, content, position, tick, weight, emotion, intensity, tags, related_agent, id) |
| Catchphrase | 5 fields (text, origin, tick, strength, context) |
| Tradition | 7 fields (name, type, season, description, participants, strength, last_performed) |

**Typical world at maturity**: 20-50 agents × 25 fields each, 100-500 memories total, 50-200 relationships, 10-30 buildings, 5-20 active catchphrases, 1-6 traditions.

---

## 7. Color System Suggestion

### Affect Colors (Agent Emotional States)
| Affect | Color | Hex Suggestion |
|--------|-------|----------------|
| Joy | Warm Gold | `#F5C542` |
| Sadness | Cool Blue | `#5B8DEF` |
| Desire | Vibrant Green | `#4ADE80` |
| Fear | Alert Red | `#EF4444` |
| Neutral | Soft Grey | `#9CA3AF` |

### Season Palette
| Season | Tint | Hex Suggestion |
|--------|------|----------------|
| Spring | Fresh Green | `#86EFAC` |
| Summer | Warm Gold | `#FCD34D` |
| Autumn | Deep Orange | `#FB923C` |
| Winter | Ice Blue | `#BAE6FD` |

### Terrain Colors
| Terrain | Color | Hex Suggestion |
|---------|-------|----------------|
| Grass | Soft Green | `#4ADE80` |
| Water | Deep Blue | `#3B82F6` |
| Forest | Dark Green | `#166534` |
| Mountain | Stone Grey | `#6B7280` |
| Desert | Sand | `#D4A574` |
| Farm | Golden | `#CA8A04` |
| Flowers | Pink | `#F472B6` |

### UI Chrome
| Element | Color | Hex Suggestion |
|---------|-------|----------------|
| Background | Near Black | `#0F0F14` |
| Panel BG | Dark Grey | `#1A1A24` |
| Panel Border | Subtle Grey | `#2A2A3A` |
| Text Primary | Off White | `#E5E5E5` |
| Text Secondary | Muted | `#9CA3AF` |
| Accent | Spinoza Gold | `#C9A84C` |
| Success | Green | `#22C55E` |
| Warning | Amber | `#F59E0B` |
| Danger | Red | `#EF4444` |

---

## 8. Typography Suggestion

| Usage | Style | Rationale |
|-------|-------|-----------|
| World name, era names, headlines | Serif (e.g., Playfair Display, Cormorant) | Philosophical gravitas, 17th-century echo |
| Agent names, section headers | Semi-bold sans-serif (e.g., Inter, DM Sans) | Clean readability |
| Body text, descriptions | Regular sans-serif | Neutral, readable at small sizes |
| Data values, tick counts, coordinates | Monospace (e.g., JetBrains Mono, Fira Code) | Precision, technical feel |
| Catchphrases, agent speech | Italic serif | Distinct from UI text, feels like a quote |
| Story feed | Regular sans-serif, slightly smaller | Dense but scannable |

---

## 9. Animation & Motion

| Element | Animation | Duration |
|---------|-----------|----------|
| Agent movement | Smooth position interpolation | ~100ms per tick |
| Affect change | Color transition + subtle pulse | 300ms ease |
| Day/Night cycle | Ambient overlay color shift | 2-3s smooth transition |
| Season change | Tint transition + particle system change | 1-2s |
| World event overlay | Fade in → sustain → fade out | 500ms in, event duration, 500ms out |
| Panel open/close | Slide + fade | 200ms ease-out |
| Story feed new entry | Slide up + fade in | 150ms |
| Agent selection | Ring/glow appear around dot | 200ms |
| Building construction | Placeholder → solid sprite | 300ms |
| Agent death | Dot shrinks + fades | 500ms |
| Agent birth | Dot appears + pulse outward | 400ms |
| Conatus bar change | Width transition | 200ms ease |
| Need bar critical | Pulsing glow animation | 1s loop |
| Memory decay | Opacity reduction over time | Continuous |

---

## 10. Responsive Considerations

| Breakpoint | Layout Adaptation |
|------------|-------------------|
| 1440px+ | Full layout: left panel + map + right panel + bottom bar |
| 1024-1439px | Collapsible panels, map takes priority, bottom bar condensed |
| 768-1023px | Tabbed panels (left/right become tabs), map full-width |
| <768px | Not primary target, but: map full-screen, panels as overlays/drawers |

---

## 11. Accessibility Notes

- All affect states should be distinguishable beyond color (icons + labels)
- Need bars should have text values alongside visual bars
- Keyboard navigation for all panels and controls
- Screen reader labels for all interactive elements
- High contrast mode option for map terrain
- Story feed should be accessible as a live region

---

## 12. Visual References & Inspiration

The aesthetic sits at the intersection of:
- **Dwarf Fortress** — depth of simulation, ASCII heritage
- **Figma / Linear** — clean, modern, dark-mode panel UI
- **Observable / D3** — data visualization elegance
- **Stellaris** — space-opera UI with dense stats
- **The Matrix** — living data streams, green-on-dark
- **17th-century engravings** — Spinoza's era, geometric precision
- **Nature documentaries** — the calm of observing life unfold

---

## 13. Deliverables Expected

1. **Design System**: Color, typography, spacing, component library
2. **Screen Designs**: All screens listed in Section 3 (3.1 – 3.12)
3. **Component Library**: All components from Section 4
4. **Interaction Spec**: Hover/click/drag states for all interactive elements
5. **Animation Spec**: Timing and easing for all animations in Section 9
6. **Responsive Variants**: At minimum 1440px and 1024px breakpoints
7. **Prototype**: Interactive prototype for main simulation flow (3.4 + 3.5)

---

*"In Nature there is nothing contingent, but all things have been determined from the necessity of the divine nature to exist and produce an effect in a certain way."*
— Baruch Spinoza, Ethics, Part I, Proposition 29
