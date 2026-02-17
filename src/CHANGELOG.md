# MODUS Changelog

## v1.6.0 Creator (2026-02-17)

### World Builder / Terrain Painter
- 🔨 **Build Mode** toggle button in top bar
- 🎨 **Terrain Palette** (left sidebar): grass, forest, water, mountain, desert, sand, farm, flowers
- 🖌️ **Click-to-paint** and **drag-to-paint** terrain on map tiles
- Terrain changes broadcast in real-time to all connected clients

### Nature Resource System
- 🌲 Each terrain type has harvestable resources:
  - Forest → wood (building material)
  - Water → fish (food), fresh_water (drinking)
  - Farm → crops (food)
  - Mountain → stone (building material)
  - Flowers → herbs (trade goods)
  - Grass → wild berries (emergency food)
- 📦 **Resource Nodes**: placeable food_source, water_well, wood_pile, stone_quarry
- ♻️ Resources are **finite but renewable** — respawn after 200 ticks
- Resource nodes shown as emoji icons on terrain tiles

### Agent Inventory
- 🎒 Agents now have an **inventory** of gathered resources
- Gathering action maps to terrain type (forest→wood, water→fish, etc.)
- Inventory displayed in agent detail panel
- Food-like resources (fish, crops, berries) reduce hunger when gathered

### Technical
- New terrain types: desert, sand, farm, flowers
- WorldChannel handlers: paint_terrain, place_resource, gather_resource
- ResourceSystem regeneration rates for all new terrain types
- Resource.ex expanded with terrain→resource mapping and respawn logic

## v1.5.0 Deus (2026-02-16)
- God Mode, Cinematic Camera, Screenshot Export, Landing Page

## v1.4.0 Potentia (2026-02-16)
- Story Engine, Timeline, Chronicle Export, Population Stats

## v1.3.0 Sapientia (2026-02-16)
- Agent Learning & Skills System

## v1.2.0 Libertas (2026-02-16)
- Perception, Social Insight, Intent Parser, Protocol Bridge

## v1.1.0 Harmonia (2026-02-16)
- UI/UX polish, performance optimizations

## v1.0.0 Cerebro (2026-02-16)
- Spinoza Mind Engine, Conatus, Affects, Social Network
