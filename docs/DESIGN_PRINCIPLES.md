# MODUS Design Principles

> "Simplicity is the ultimate sophistication" — Leonardo da Vinci
> "The more clearly you understand yourself and your emotions, the more you become a lover of what is" — Spinoza

## 🎨 Core Visual Rule: ALWAYS 2D

**MODUS is and will always be 2D. No 3D. No isometric. No perspective tricks.**

### What 2D Means
- Top-down view, flat, like looking at a board game from above
- Simple geometric shapes: circles for agents, squares for buildings, triangles for trees
- Clean pixel art at tile level — each tile is a colored square
- Think: early Zelda, Stardew Valley top-down, Dwarf Fortress tileset
- Readable at a glance — you understand everything instantly

### What We NEVER Do
- No isometric projection
- No 3D rendering, no WebGL, no perspective
- No complex sprites with multiple angles
- No depth/parallax effects
- No rotation of the world

### Why 2D
1. **Clarity**: You see everything, understand everything, instantly
2. **Performance**: Runs on anything, SSH terminal included
3. **Focus on MIND not GRAPHICS**: The magic is in agent AI, not visual effects
4. **Accessibility**: Low bandwidth, low GPU, works everywhere
5. **Aesthetic**: Clean, zen, readable — like a living diagram

### Visual Hierarchy (simple to complex)
```
Level 1 — Text Mode:  🌲👤🏠🦌 (pure unicode, zero graphics)
Level 2 — Tile Mode:  colored squares + emoji overlay (current Pixi.js renderer)
Level 3 — Sprite Mode: simple 16x16 pixel art sprites (future, still 2D top-down)
```

We are at Level 2. Level 3 is optional future. Level 1 is always available.

### Color Language
- Terrain: green=grass, dark_green=forest, blue=water, grey=mountain, yellow=desert, gold=farm
- Agents: gold=happy, blue=sad, green=eager, red=scared, white=neutral
- Buildings: brown=wood, grey=stone, warm_tan=upgraded
- Animals: brown=deer, grey=rabbit, dark=wolf, light_blue=bird, cyan=fish
- Resources: sparkle overlay on terrain tiles

### Agent Representation
- A colored circle (8-12px) on a tile
- Name label above (small, clean font)
- Action emoji above name (🔨🎣🗡️💤💬)
- Mood shown by circle color, not by complex animation
- Selected agent: white border glow

### Building Representation
- Colored rectangle on tile(s)
- Type shown by emoji in center: 🏠🛖🌾🏪🚰🗼
- Level shown by size (small→medium→large)
- No roof angles, no shadows, no depth

### Animal Representation
- Small colored dot (4-6px), smaller than agents
- Type emoji: 🦌🐇🐺🐦🐟
- Simple movement: smooth glide between tiles
- No animation frames, no walk cycles

### The Golden Rule
**If a 5-year-old can't understand what they're looking at in 3 seconds, it's too complex. Simplify.**
