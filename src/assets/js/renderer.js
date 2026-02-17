/**
 * MODUS 2D Renderer — Pixi.js v8
 * v1.1.0 Harmonia — UI/UX polish + performance optimizations
 *
 * Renders the 50x50 tile world with terrain, agents, camera controls.
 * Features: sprite pooling, mini-map, tooltips, keyboard shortcuts.
 */
import { Application, Container, Graphics, Text, TextStyle } from "pixi.js"

const TILE_SIZE = 16
const AGENT_RADIUS = 6
let GRID_W = 100
let GRID_H = 100

// Mini-map constants
const MINIMAP_SIZE = 140
const MINIMAP_MARGIN = 12
const MINIMAP_AGENT_SIZE = 3

const TERRAIN_COLORS = {
  grass:    0x4ade80,
  water:    0x60a5fa,
  forest:   0x166534,
  mountain: 0x78716c,
  desert:   0xd4a574,
  sand:     0xf5deb3,
  farm:     0x8b9a46,
  flowers:  0xe879a8,
}

const RESOURCE_NODE_ICONS = {
  food_source: "🍖",
  water_well: "💧",
  wood_pile: "🪵",
  stone_quarry: "⛏️",
}

const AGENT_COLORS = [
  0xf472b6, 0xa78bfa, 0x38bdf8, 0xfbbf24, 0x34d399,
  0xfb7185, 0x818cf8, 0x22d3ee, 0xf59e0b, 0x10b981,
]

const AFFECT_COLORS = {
  joy: 0xfbbf24,
  sadness: 0x60a5fa,
  desire: 0x4ade80,
  fear: 0xef4444,
}

export default class Renderer {
  constructor(container) {
    this.container = container
    this.app = null
    this.worldContainer = null
    this.terrainLayer = null
    this.agentLayer = null
    this.relationshipLayer = null
    this.relationshipGfx = null
    this.agentSprites = new Map() // id -> {gfx, label, targetX, targetY}

    // Agent data cache (for relationship lines)
    this.agentDataMap = new Map() // id -> {friends, conversing_with, ...}

    // Sprite pool for recycling
    this.spritePool = []

    // Agent click callback
    this.onAgentClick = null
    this.selectedAgentId = null

    // Mind View toggle
    this.mindViewActive = false

    // Mini-map
    this.minimapContainer = null
    this.minimapBg = null
    this.minimapAgents = null
    this.minimapViewport = null
    this.minimapVisible = true
    this.minimapTerrainCache = null

    // Tooltip
    this.tooltipContainer = null
    this.tooltipBg = null
    this.tooltipText = null
    this.hoveredAgentId = null

    // Terrain grid cache for minimap
    this.terrainGrid = null

    // Build Mode
    this.buildMode = false
    this.buildBrush = "grass" // current terrain or resource node type
    this.buildType = "terrain" // "terrain", "resource", or "building"
    this.onPaintTerrain = null // callback(x, y, terrain)
    this.onPlaceResource = null // callback(x, y, nodeType)
    this.onPlaceBuilding = null // callback(x, y, buildingType)
    this.resourceNodeLayer = null
    this.resourceNodeSprites = new Map() // "x,y" -> container
    this.buildingLayer = null
    this.buildingSprites = new Map() // id -> {gfx, label}

    // Camera state
    this.dragging = false
    this.didDrag = false
    this.dragStart = { x: 0, y: 0 }
    this.camStart = { x: 0, y: 0 }
    this.scale = 1.0
  }

  setGridSize(w, h) {
    GRID_W = w || GRID_W
    GRID_H = h || GRID_H
  }

  async init() {
    console.log("[MODUS] Renderer.init() starting, container:", this.container?.clientWidth, "x", this.container?.clientHeight)
    this.app = new Application()
    await this.app.init({
      background: 0x0f172a,
      resizeTo: this.container,
      antialias: true,
      autoDensity: true,
      resolution: window.devicePixelRatio || 1,
    })
    console.log("[MODUS] Pixi app.init() done, canvas:", this.app.canvas?.tagName, this.app.canvas?.width, "x", this.app.canvas?.height)
    this.container.appendChild(this.app.canvas)
    console.log("[MODUS] Canvas appended to container")

    // World container (camera target)
    this.worldContainer = new Container()
    this.app.stage.addChild(this.worldContainer)

    // Layers
    this.terrainLayer = new Container()
    this.nightOverlay = null // created after terrain render
    this.relationshipLayer = new Container()
    this.agentLayer = new Container()
    this.resourceNodeLayer = new Container()
    this.buildingLayer = new Container()
    this.worldContainer.addChild(this.terrainLayer)
    this.worldContainer.addChild(this.resourceNodeLayer)
    this.worldContainer.addChild(this.buildingLayer)
    this.worldContainer.addChild(this.relationshipLayer)
    this.worldContainer.addChild(this.agentLayer)

    // Environment state
    this.cycleProgress = 0
    this.timeOfDay = "day"

    // Single Graphics object for relationship lines (cleared each frame)
    this.relationshipGfx = new Graphics()
    this.relationshipLayer.addChild(this.relationshipGfx)

    // Center camera
    const totalW = GRID_W * TILE_SIZE
    const totalH = GRID_H * TILE_SIZE
    this.worldContainer.x = (this.app.screen.width - totalW) / 2
    this.worldContainer.y = (this.app.screen.height - totalH) / 2

    this._setupCamera()
    this._setupMinimap()
    this._setupTooltip()
    this._startAnimLoop()

    // Hide loading skeleton
    const skeleton = document.getElementById("canvas-skeleton")
    if (skeleton) skeleton.style.display = "none"
  }

  // ── Terrain ──────────────────────────────────────────────

  renderTerrain(grid) {
    this.terrainGrid = grid // cache for minimap
    // Build a lookup map for chunk rendering
    this._terrainMap = new Map()
    for (const cell of grid) {
      this._terrainMap.set(`${cell.x},${cell.y}`, cell.terrain)
    }
    this._renderVisibleChunks()

    // Create night overlay (dark blue tint above terrain, below agents)
    if (!this.nightOverlay) {
      this.nightOverlay = new Graphics()
      // Insert between terrain and relationship layers
      const idx = this.worldContainer.getChildIndex(this.relationshipLayer)
      this.worldContainer.addChildAt(this.nightOverlay, idx)
    }
    this.nightOverlay.clear()
    this.nightOverlay.rect(0, 0, GRID_W * TILE_SIZE, GRID_H * TILE_SIZE)
    this.nightOverlay.fill({ color: 0x0a1030, alpha: 0 })

    // Render resource nodes from grid data
    for (const cell of grid) {
      if (cell.resource_nodes) {
        for (const nodeType of cell.resource_nodes) {
          this.addResourceNode(cell.x, cell.y, nodeType)
        }
      }
    }

    // Update minimap terrain
    this._drawMinimapTerrain()
  }

  // Chunk-based rendering: only draw tiles visible in the camera viewport
  _renderVisibleChunks() {
    if (!this._terrainMap || !this.app) return
    this.terrainLayer.removeChildren()
    const gfx = new Graphics()

    // Calculate visible tile range from camera
    const margin = 2 // extra tiles around edges
    const camX = -this.worldContainer.x / this.scale
    const camY = -this.worldContainer.y / this.scale
    const vpW = this.app.screen.width / this.scale
    const vpH = this.app.screen.height / this.scale

    const minTX = Math.max(0, Math.floor(camX / TILE_SIZE) - margin)
    const minTY = Math.max(0, Math.floor(camY / TILE_SIZE) - margin)
    const maxTX = Math.min(GRID_W - 1, Math.ceil((camX + vpW) / TILE_SIZE) + margin)
    const maxTY = Math.min(GRID_H - 1, Math.ceil((camY + vpH) / TILE_SIZE) + margin)

    for (let x = minTX; x <= maxTX; x++) {
      for (let y = minTY; y <= maxTY; y++) {
        const terrain = this._terrainMap.get(`${x},${y}`) || "grass"
        const color = TERRAIN_COLORS[terrain] || 0x333333
        gfx.rect(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
        gfx.fill(color)
      }
    }

    // Grid lines only for visible area
    if (this.scale > 0.5) {
      gfx.setStrokeStyle({ width: 0.5, color: 0xffffff, alpha: 0.04 })
      for (let x = minTX; x <= maxTX + 1; x++) {
        gfx.moveTo(x * TILE_SIZE, minTY * TILE_SIZE)
        gfx.lineTo(x * TILE_SIZE, (maxTY + 1) * TILE_SIZE)
        gfx.stroke()
      }
      for (let y = minTY; y <= maxTY + 1; y++) {
        gfx.moveTo(minTX * TILE_SIZE, y * TILE_SIZE)
        gfx.lineTo((maxTX + 1) * TILE_SIZE, y * TILE_SIZE)
        gfx.stroke()
      }
    }

    this.terrainLayer.addChild(gfx)
    this._lastChunkBounds = { minTX, minTY, maxTX, maxTY }
  }

  // ── Agents ───────────────────────────────────────────────

  updateAgents(agents) {
    const seen = new Set()

    for (const agent of agents) {
      seen.add(agent.id)
      // Cache agent data for relationship lines
      this.agentDataMap.set(agent.id, {
        friends: agent.friends || [],
        conversing_with: agent.conversing_with,
        group: agent.group || null,
      })
      const px = agent.x * TILE_SIZE + TILE_SIZE / 2
      const py = agent.y * TILE_SIZE + TILE_SIZE / 2

      if (this.agentSprites.has(agent.id)) {
        // Update target for lerp
        const sprite = this.agentSprites.get(agent.id)
        sprite.targetX = px
        sprite.targetY = py
        sprite.action = agent.action || "idle"
        sprite.reasoning = agent.reasoning || false

        // Update conversation bubble
        if (agent.conversing_with) {
          if (!sprite.convoBubble) {
            sprite.convoBubble = new Text({ text: "💬", style: new TextStyle({ fontSize: 12, align: "center" }) })
            sprite.convoBubble.anchor.set(0.5, 1)
            sprite.convoBubble.y = -AGENT_RADIUS - 14
            sprite.container.addChild(sprite.convoBubble)
          }
          sprite.convoBubble.visible = true
        } else if (sprite.convoBubble) {
          sprite.convoBubble.visible = false
        }
        // Update affect color
        const affect = agent.affect || "neutral"
        const affectColor = AFFECT_COLORS[affect]
        if (affectColor && affectColor !== sprite.currentColor) {
          sprite.gfx.clear()
          sprite.gfx.circle(0, 0, AGENT_RADIUS)
          sprite.gfx.fill(affectColor)
          sprite.gfx.circle(0, 0, AGENT_RADIUS)
          sprite.gfx.stroke({ width: 1.5, color: 0xffffff, alpha: 0.3 })
          sprite.currentColor = affectColor
        } else if (!affectColor && sprite.currentColor !== sprite.baseColor) {
          sprite.gfx.clear()
          sprite.gfx.circle(0, 0, AGENT_RADIUS)
          sprite.gfx.fill(sprite.baseColor)
          sprite.gfx.circle(0, 0, AGENT_RADIUS)
          sprite.gfx.stroke({ width: 1.5, color: 0xffffff, alpha: 0.3 })
          sprite.currentColor = sprite.baseColor
        }
        // Update conatus bar
        if (sprite.conatusBar && agent.conatus_energy != null) {
          const e = Math.max(0, Math.min(1, agent.conatus_energy))
          const barW = AGENT_RADIUS * 2
          sprite.conatusBar.clear()
          // bg
          sprite.conatusBar.rect(-barW / 2, 0, barW, 2)
          sprite.conatusBar.fill({ color: 0x333333, alpha: 0.5 })
          // fill
          const barColor = e > 0.6 ? 0x4ade80 : e > 0.3 ? 0xfbbf24 : 0xef4444
          sprite.conatusBar.rect(-barW / 2, 0, barW * e, 2)
          sprite.conatusBar.fill(barColor)
        }
        // Update alive status
        if (!agent.alive) {
          sprite.gfx.alpha = 0.3
        }
      } else {
        // Create new agent sprite
        const colorIdx = this._hashCode(agent.id) % AGENT_COLORS.length
        const color = AGENT_COLORS[colorIdx]

        const agentContainer = new Container()
        agentContainer.x = px
        agentContainer.y = py

        const gfx = new Graphics()
        gfx.circle(0, 0, AGENT_RADIUS)
        gfx.fill(color)
        gfx.circle(0, 0, AGENT_RADIUS)
        gfx.stroke({ width: 1.5, color: 0xffffff, alpha: 0.3 })
        agentContainer.addChild(gfx)

        const label = new Text({
          text: agent.name || "?",
          style: new TextStyle({
            fontFamily: "monospace",
            fontSize: 8,
            fill: 0xffffff,
            align: "center",
          }),
        })
        label.anchor.set(0.5, 0)
        label.y = AGENT_RADIUS + 2
        agentContainer.addChild(label)

        // Conatus energy bar
        const conatusBar = new Graphics()
        conatusBar.y = AGENT_RADIUS + 12
        agentContainer.addChild(conatusBar)

        this.agentLayer.addChild(agentContainer)
        // Action emoji indicator
        const actionEmoji = new Text({
          text: "",
          style: new TextStyle({
            fontSize: 10,
            align: "center",
          }),
        })
        actionEmoji.anchor.set(0.5, 1)
        actionEmoji.y = -AGENT_RADIUS - 2
        agentContainer.addChild(actionEmoji)

        this.agentSprites.set(agent.id, {
          container: agentContainer,
          gfx,
          label,
          actionEmoji,
          conatusBar,
          baseColor: color,
          currentColor: color,
          action: agent.action || "idle",
          reasoning: agent.reasoning || false,
          targetX: px,
          targetY: py,
        })
      }
    }

    // Remove dead/removed agents
    for (const [id, sprite] of this.agentSprites) {
      if (!seen.has(id)) {
        this.agentLayer.removeChild(sprite.container)
        sprite.container.destroy({ children: true })
        this.agentSprites.delete(id)
        this.agentDataMap.delete(id)
      }
    }
  }

  // ── Animation Loop (lerp) ───────────────────────────────

  selectAgent(agentId) {
    this.selectedAgentId = agentId
  }

  _startAnimLoop() {
    let glowPhase = 0
    const ACTION_EMOJIS = {
      explore: "🧭", exploring: "🧭",
      gather: "🌾", gathering: "🌾", find_food: "🍖",
      find_friend: "💬", talk: "💬", talking: "💬",
      go_home_sleep: "😴", sleep: "😴", sleeping: "😴",
      help_nearby: "🤝", flee: "🏃", fleeing: "🏃",
      build: "🔨", building: "🔨",
      go_home: "🏠",
      idle: "",
      reasoning: "💭",
    }
    this.app.ticker.add((ticker) => {
      const lerp = 0.15
      glowPhase += ticker.deltaTime * 0.08
      const glowAlpha = 0.3 + Math.sin(glowPhase) * 0.2
      const breathScale = 1.0 + Math.sin(glowPhase * 1.5) * 0.03
      const bounceY = Math.sin(glowPhase * 3) * 1.5

      // ── Cinematic Camera ──
      this._updateCinematic()

      // ── Chunk re-render on camera move ──
      if (this._chunksDirty && this._terrainMap) {
        this._chunksDirty = false
        this._renderVisibleChunks()
      }

      // ── Relationship Lines ──
      this._drawRelationshipLines()

      // ── Mini-map (every 3 frames for perf) ──
      if (Math.floor(glowPhase * 10) % 3 === 0) this._updateMinimap()

      for (const [id, sprite] of this.agentSprites) {
        const c = sprite.container
        c.x += (sprite.targetX - c.x) * lerp
        c.y += (sprite.targetY - c.y) * lerp

        // Action-based animation
        const action = sprite.action || "idle"
        if (action === "explore" || action === "exploring") {
          sprite.gfx.y = bounceY
        } else if (action === "idle") {
          sprite.gfx.scale.set(breathScale)
        } else {
          sprite.gfx.y = 0
          sprite.gfx.scale.set(1)
        }

        // Action emoji (reasoning overrides)
        if (sprite.actionEmoji) {
          const emoji = sprite.reasoning ? "💭" : (ACTION_EMOJIS[action] || "")
          if (sprite.actionEmoji.text !== emoji) {
            sprite.actionEmoji.text = emoji
          }
        }

        // Group halo — same color for all group members
        const agentData = this.agentDataMap.get(id)
        const group = agentData ? agentData.group : null
        if (group) {
          if (!sprite.groupHalo) {
            sprite.groupHalo = new Graphics()
            sprite.container.addChildAt(sprite.groupHalo, 0)
          }
          const gc = group.color || 0xA855F7
          sprite.groupHalo.clear()
          sprite.groupHalo.circle(0, 0, AGENT_RADIUS + 6)
          sprite.groupHalo.fill({ color: gc, alpha: 0.25 })
          // Leader gets a thicker ring
          if (group.is_leader) {
            sprite.groupHalo.circle(0, 0, AGENT_RADIUS + 7)
            sprite.groupHalo.stroke({ width: 2, color: gc, alpha: 0.6 })
          }
          sprite.groupHalo.visible = true
        } else if (sprite.groupHalo) {
          sprite.groupHalo.visible = false
        }

        // Selection glow
        if (id === this.selectedAgentId) {
          if (!sprite.glow) {
            sprite.glow = new Graphics()
            c.addChildAt(sprite.glow, 0)
          }
          sprite.glow.clear()
          sprite.glow.circle(0, 0, AGENT_RADIUS + 4)
          sprite.glow.fill({ color: 0xa855f7, alpha: glowAlpha })
          sprite.glow.visible = true
        } else if (sprite.glow) {
          sprite.glow.visible = false
        }
      }
    })
  }

  // ── Relationship Lines ──────────────────────────────────

  _drawRelationshipLines() {
    const gfx = this.relationshipGfx
    if (!gfx) return
    gfx.clear()

    const mindView = this.mindViewActive
    const drawn = new Set()

    for (const [id, data] of this.agentDataMap) {
      const sprite = this.agentSprites.get(id)
      if (!sprite || !data.friends) continue

      for (const friend of data.friends) {
        const strength = friend.strength || 0
        if (strength < 0.3) continue

        const otherId = friend.id
        const otherSprite = this.agentSprites.get(otherId)
        if (!otherSprite) continue

        // Avoid drawing duplicate lines
        const pairKey = id < otherId ? `${id}-${otherId}` : `${otherId}-${id}`
        if (drawn.has(pairKey)) continue
        drawn.add(pairKey)

        // Determine color and opacity by strength
        let color, alpha
        if (strength > 0.8) {
          color = 0xfbbf24 // gold
          alpha = mindView ? 0.9 : 0.6
        } else if (strength > 0.5) {
          color = 0x4ade80 // green
          alpha = mindView ? 0.7 : 0.4
        } else {
          color = 0xffffff // white
          alpha = mindView ? 0.4 : 0.2
        }

        gfx.setStrokeStyle({ width: mindView ? 2 : 1, color, alpha })
        gfx.moveTo(sprite.container.x, sprite.container.y)
        gfx.lineTo(otherSprite.container.x, otherSprite.container.y)
        gfx.stroke()
      }
    }
  }

  // ── Environment (Day/Night) ──────────────────────────────

  updateEnvironment(data) {
    if (data.cycle_progress != null) this.cycleProgress = data.cycle_progress
    if (data.time_of_day) this.timeOfDay = data.time_of_day

    // Update night overlay alpha
    if (this.nightOverlay) {
      const p = this.cycleProgress
      // 0-0.5 = day (alpha 0), 0.5-1.0 = night (ramp up to 0.5 then down)
      let nightAlpha = 0
      if (p >= 0.5) {
        const nightProgress = (p - 0.5) * 2 // 0 to 1 within night
        nightAlpha = nightProgress < 0.5
          ? nightProgress * 2 * 0.5   // ramp up to 0.5
          : (1 - nightProgress) * 2 * 0.5  // ramp down
        nightAlpha = Math.max(0, Math.min(0.5, nightAlpha))
      }
      this.nightOverlay.clear()
      this.nightOverlay.rect(0, 0, GRID_W * TILE_SIZE, GRID_H * TILE_SIZE)
      this.nightOverlay.fill({ color: 0x0a1030, alpha: nightAlpha })
    }
  }

  // ── Mind View Toggle ──────────────────────────────────────

  toggleMindView() {
    this.mindViewActive = !this.mindViewActive
    if (this.terrainLayer) {
      this.terrainLayer.alpha = this.mindViewActive ? 0.3 : 1.0
    }
    return this.mindViewActive
  }

  // ── Mini-map ─────────────────────────────────────────────

  _setupMinimap() {
    this.minimapContainer = new Container()
    this.minimapContainer.zIndex = 100
    this.app.stage.addChild(this.minimapContainer)
    this.app.stage.sortableChildren = true

    // Background
    this.minimapBg = new Graphics()
    this.minimapContainer.addChild(this.minimapBg)

    // Terrain layer (cached, only redrawn on terrain change)
    this.minimapTerrainCache = new Graphics()
    this.minimapContainer.addChild(this.minimapTerrainCache)

    // Agent dots
    this.minimapAgents = new Graphics()
    this.minimapContainer.addChild(this.minimapAgents)

    // Viewport rectangle
    this.minimapViewport = new Graphics()
    this.minimapContainer.addChild(this.minimapViewport)

    this._positionMinimap()
  }

  _positionMinimap() {
    if (!this.minimapContainer || !this.app) return
    this.minimapContainer.x = this.app.screen.width - MINIMAP_SIZE - MINIMAP_MARGIN
    this.minimapContainer.y = MINIMAP_MARGIN
  }

  _drawMinimapTerrain() {
    if (!this.minimapTerrainCache || !this.terrainGrid) return
    const gfx = this.minimapTerrainCache
    gfx.clear()
    const scale = MINIMAP_SIZE / (GRID_W * TILE_SIZE)
    for (const cell of this.terrainGrid) {
      const color = TERRAIN_COLORS[cell.terrain] || 0x333333
      gfx.rect(cell.x * TILE_SIZE * scale, cell.y * TILE_SIZE * scale, TILE_SIZE * scale, TILE_SIZE * scale)
      gfx.fill({ color, alpha: 0.7 })
    }
  }

  _updateMinimap() {
    if (!this.minimapVisible || !this.minimapContainer) {
      if (this.minimapContainer) this.minimapContainer.visible = false
      return
    }
    this.minimapContainer.visible = true
    this._positionMinimap()

    const scale = MINIMAP_SIZE / (GRID_W * TILE_SIZE)

    // Background
    const bg = this.minimapBg
    bg.clear()
    bg.rect(-2, -2, MINIMAP_SIZE + 4, MINIMAP_SIZE + 4)
    bg.fill({ color: 0x0A0A0F, alpha: 0.85 })
    bg.rect(-2, -2, MINIMAP_SIZE + 4, MINIMAP_SIZE + 4)
    bg.stroke({ width: 1, color: 0xffffff, alpha: 0.1 })

    // Agent dots
    const agfx = this.minimapAgents
    agfx.clear()
    for (const [id, sprite] of this.agentSprites) {
      const mx = sprite.targetX * scale
      const my = sprite.targetY * scale
      const color = id === this.selectedAgentId ? 0xa855f7 : sprite.baseColor
      agfx.circle(mx, my, MINIMAP_AGENT_SIZE)
      agfx.fill(color)
    }

    // Viewport rect
    const vp = this.minimapViewport
    vp.clear()
    const vpX = (-this.worldContainer.x / this.scale) * scale
    const vpY = (-this.worldContainer.y / this.scale) * scale
    const vpW = (this.app.screen.width / this.scale) * scale
    const vpH = (this.app.screen.height / this.scale) * scale
    vp.rect(vpX, vpY, vpW, vpH)
    vp.stroke({ width: 1.5, color: 0xa855f7, alpha: 0.8 })
  }

  toggleMinimap() {
    this.minimapVisible = !this.minimapVisible
    return this.minimapVisible
  }

  // ── Tooltip ──────────────────────────────────────────────

  _setupTooltip() {
    this.tooltipContainer = new Container()
    this.tooltipContainer.zIndex = 200
    this.tooltipContainer.visible = false
    this.app.stage.addChild(this.tooltipContainer)

    this.tooltipBg = new Graphics()
    this.tooltipContainer.addChild(this.tooltipBg)

    this.tooltipText = new Text({
      text: "",
      style: new TextStyle({
        fontFamily: "monospace",
        fontSize: 10,
        fill: 0xe2e8f0,
        wordWrap: true,
        wordWrapWidth: 160,
      }),
    })
    this.tooltipText.x = 8
    this.tooltipText.y = 6
    this.tooltipContainer.addChild(this.tooltipText)

    // Track mouse for hover detection
    const canvas = this.app.canvas
    canvas.addEventListener("pointermove", (e) => {
      if (this.dragging) {
        this.tooltipContainer.visible = false
        return
      }
      const rect = canvas.getBoundingClientRect()
      const mx = e.clientX - rect.left
      const my = e.clientY - rect.top
      const wx = (mx - this.worldContainer.x) / this.scale
      const wy = (my - this.worldContainer.y) / this.scale

      let closest = null
      let closestDist = TILE_SIZE * 1.5
      for (const [id, sprite] of this.agentSprites) {
        const dx = sprite.container.x - wx
        const dy = sprite.container.y - wy
        const dist = Math.sqrt(dx * dx + dy * dy)
        if (dist < closestDist) {
          closestDist = dist
          closest = id
        }
      }

      if (closest && closest !== this.hoveredAgentId) {
        this.hoveredAgentId = closest
        const data = this.agentDataMap.get(closest)
        const sprite = this.agentSprites.get(closest)
        const name = sprite?.label?.text || "?"
        const action = sprite?.action || "idle"
        const friends = data?.friends?.length || 0
        const group = data?.group ? `Group: ${data.group.name || "yes"}` : ""
        const lines = [`${name}`, `Action: ${action}`, `Friends: ${friends}`]
        if (group) lines.push(group)
        this.tooltipText.text = lines.join("\n")
        this.tooltipBg.clear()
        const tw = Math.max(this.tooltipText.width + 16, 100)
        const th = this.tooltipText.height + 12
        this.tooltipBg.roundRect(0, 0, tw, th, 4)
        this.tooltipBg.fill({ color: 0x1e1b2e, alpha: 0.92 })
        this.tooltipBg.roundRect(0, 0, tw, th, 4)
        this.tooltipBg.stroke({ width: 1, color: 0xa855f7, alpha: 0.4 })
        this.tooltipContainer.visible = true
      } else if (!closest) {
        this.hoveredAgentId = null
        this.tooltipContainer.visible = false
      }

      if (this.tooltipContainer.visible) {
        this.tooltipContainer.x = mx + 14
        this.tooltipContainer.y = my - 10
        // Keep within bounds
        if (this.tooltipContainer.x + 180 > this.app.screen.width) {
          this.tooltipContainer.x = mx - 180
        }
      }
    })
  }

  // ── Camera Controls ─────────────────────────────────────

  _setupCamera() {
    const canvas = this.app.canvas

    // Pan (drag) + click detection
    canvas.addEventListener("pointerdown", (e) => {
      this.dragging = true
      this.didDrag = false
      this.dragStart = { x: e.clientX, y: e.clientY }
      this.camStart = { x: this.worldContainer.x, y: this.worldContainer.y }
      canvas.style.cursor = "grabbing"
    })

    canvas.addEventListener("pointermove", (e) => {
      if (!this.dragging) return

      // Build mode: drag-paint
      if (this.buildMode) {
        const rect = canvas.getBoundingClientRect()
        const mx = e.clientX - rect.left
        const my = e.clientY - rect.top
        const wx = (mx - this.worldContainer.x) / this.scale
        const wy = (my - this.worldContainer.y) / this.scale
        const tileX = Math.floor(wx / TILE_SIZE)
        const tileY = Math.floor(wy / TILE_SIZE)
        if (tileX >= 0 && tileX < GRID_W && tileY >= 0 && tileY < GRID_H) {
          if (this.buildType === "building" && this.onPlaceBuilding) {
            this.onPlaceBuilding(tileX, tileY, this.buildBrush)
          } else if (this.buildType === "resource" && this.onPlaceResource) {
            this.onPlaceResource(tileX, tileY, this.buildBrush)
          } else if (this.onPaintTerrain) {
            this.onPaintTerrain(tileX, tileY, this.buildBrush)
          }
        }
        this.didDrag = true
        return
      }

      const dx = e.clientX - this.dragStart.x
      const dy = e.clientY - this.dragStart.y
      if (Math.abs(dx) > 3 || Math.abs(dy) > 3) this.didDrag = true
      this.worldContainer.x = this.camStart.x + dx
      this.worldContainer.y = this.camStart.y + dy
      this._chunksDirty = true
    })

    canvas.addEventListener("pointerup", (e) => {
      if (!this.didDrag) {
        // It was a click — check for agent hit
        this._handleClick(e)
      }
      this.dragging = false
      canvas.style.cursor = "grab"
    })

    canvas.addEventListener("pointerleave", () => {
      this.dragging = false
      canvas.style.cursor = "grab"
    })

    canvas.style.cursor = "grab"

    // Zoom (scroll) — trackpad-friendly with normalized delta
    canvas.addEventListener("wheel", (e) => {
      e.preventDefault()
      // Normalize: trackpad sends small deltaY (~1-10), mouse wheel sends large (~100)
      const raw = Math.abs(e.deltaY)
      const speed = raw > 50 ? 0.1 : raw * 0.002 // mouse: fixed step, trackpad: proportional
      const delta = e.deltaY > 0 ? (1 - speed) : (1 + speed)
      const newScale = Math.max(0.3, Math.min(5, this.scale * delta))

      // Zoom toward mouse position
      const rect = canvas.getBoundingClientRect()
      const mx = e.clientX - rect.left
      const my = e.clientY - rect.top

      const wx = (mx - this.worldContainer.x) / this.scale
      const wy = (my - this.worldContainer.y) / this.scale

      this.scale = newScale
      this.worldContainer.scale.set(this.scale)
      this.worldContainer.x = mx - wx * this.scale
      this.worldContainer.y = my - wy * this.scale
      this._chunksDirty = true
    }, { passive: false })
  }

  // ── God Mode ──────────────────────────────────────────────

  setGodMode(active) {
    this.godModeActive = active
    // In God Mode: show all labels, conatus bars, action emojis with full opacity
    for (const [_id, sprite] of this.agentSprites) {
      if (sprite.label) sprite.label.visible = true
      if (sprite.conatusBar) sprite.conatusBar.visible = true
      if (sprite.actionEmoji) sprite.actionEmoji.visible = true
      // Show affect halo in god mode
      if (active) {
        if (!sprite.godHalo) {
          sprite.godHalo = new Graphics()
          sprite.container.addChildAt(sprite.godHalo, 0)
        }
        sprite.godHalo.clear()
        sprite.godHalo.circle(0, 0, AGENT_RADIUS + 10)
        sprite.godHalo.fill({ color: sprite.currentColor || sprite.baseColor, alpha: 0.15 })
        sprite.godHalo.visible = true
      } else if (sprite.godHalo) {
        sprite.godHalo.visible = false
      }
    }
    // Make terrain semi-transparent in god mode
    if (this.terrainLayer) {
      this.terrainLayer.alpha = active ? 0.3 : 1.0
    }
  }

  // ── Cinematic Camera ─────────────────────────────────────

  setCinematicMode(active) {
    this.cinematicActive = active
    this._cinematicTarget = null
    this._cinematicCooldown = 0
  }

  _updateCinematic() {
    if (!this.cinematicActive || !this.app) return

    this._cinematicCooldown = (this._cinematicCooldown || 0) - 1
    if (this._cinematicCooldown > 0 && this._cinematicTarget) {
      // Smoothly pan to target
      const sprite = this.agentSprites.get(this._cinematicTarget)
      if (sprite) {
        const targetX = this.app.screen.width / 2 - sprite.container.x * this.scale
        const targetY = this.app.screen.height / 2 - sprite.container.y * this.scale
        this.worldContainer.x += (targetX - this.worldContainer.x) * 0.05
        this.worldContainer.y += (targetY - this.worldContainer.y) * 0.05
        this._chunksDirty = true
      }
      return
    }

    // Pick a new interesting target every ~180 frames
    if (this._cinematicCooldown <= 0) {
      this._cinematicCooldown = 180
      // Find agent with most interesting state (conversing, high affect, etc)
      let best = null
      let bestScore = -1
      for (const [id, data] of this.agentDataMap) {
        let score = 0
        if (data.conversing_with) score += 5
        if (data.friends && data.friends.length > 2) score += 2
        if (data.group) score += 3
        // Add randomness
        score += Math.random() * 3
        if (score > bestScore) {
          bestScore = score
          best = id
        }
      }
      this._cinematicTarget = best
    }
  }

  // ── Screenshot Export ────────────────────────────────────

  takeScreenshot() {
    if (!this.app || !this.app.canvas) return
    const canvas = this.app.canvas
    const link = document.createElement("a")
    link.download = `modus-screenshot-${Date.now()}.png`
    link.href = canvas.toDataURL("image/png")
    link.click()
  }

  // ── Helpers ─────────────────────────────────────────────

  _handleClick(e) {
    const rect = this.app.canvas.getBoundingClientRect()
    const mx = e.clientX - rect.left
    const my = e.clientY - rect.top
    const wx = (mx - this.worldContainer.x) / this.scale
    const wy = (my - this.worldContainer.y) / this.scale

    // Build Mode: paint terrain or place resource
    if (this.buildMode) {
      const tileX = Math.floor(wx / TILE_SIZE)
      const tileY = Math.floor(wy / TILE_SIZE)
      if (tileX >= 0 && tileX < GRID_W && tileY >= 0 && tileY < GRID_H) {
        if (this.buildType === "building" && this.onPlaceBuilding) {
          this.onPlaceBuilding(tileX, tileY, this.buildBrush)
        } else if (this.buildType === "resource" && this.onPlaceResource) {
          this.onPlaceResource(tileX, tileY, this.buildBrush)
        } else if (this.onPaintTerrain) {
          this.onPaintTerrain(tileX, tileY, this.buildBrush)
        }
      }
      return
    }

    // Normal mode: agent click
    if (!this.onAgentClick) return

    let closest = null
    let closestDist = TILE_SIZE * 2.5

    for (const [id, sprite] of this.agentSprites) {
      const dx1 = sprite.targetX - wx
      const dy1 = sprite.targetY - wy
      const dist1 = Math.sqrt(dx1 * dx1 + dy1 * dy1)
      const dx2 = sprite.container.x - wx
      const dy2 = sprite.container.y - wy
      const dist2 = Math.sqrt(dx2 * dx2 + dy2 * dy2)
      const dist = Math.min(dist1, dist2)
      if (dist < closestDist) {
        closestDist = dist
        closest = id
      }
    }

    if (closest) {
      this.onAgentClick(closest)
    }
  }

  // ── Build Mode ──────────────────────────────────────────

  setBuildMode(active) {
    this.buildMode = active
    if (this.app?.canvas) {
      this.app.canvas.style.cursor = active ? "crosshair" : "grab"
    }
  }

  setBuildBrush(brush, type = "terrain") {
    this.buildBrush = brush
    this.buildType = type
  }

  // Paint a single tile immediately (called after server confirms)
  paintTile(x, y, terrain) {
    if (this._terrainMap) {
      this._terrainMap.set(`${x},${y}`, terrain)
      this._chunksDirty = true
    }
  }

  // ── Buildings ──────────────────────────────────────────────

  updateBuildings(buildings) {
    if (!buildings) return
    const seen = new Set()

    for (const b of buildings) {
      seen.add(b.id)
      if (this.buildingSprites.has(b.id)) continue // already rendered

      const container = new Container()
      const px = b.x * TILE_SIZE + TILE_SIZE / 2
      const py = b.y * TILE_SIZE + TILE_SIZE / 2
      container.x = px
      container.y = py

      // Colored rectangle — FLAT 2D
      const w = b.w || 14
      const h = b.h || 14
      const gfx = new Graphics()
      gfx.rect(-w / 2, -h / 2, w, h)
      gfx.fill(b.color || 0x888888)
      gfx.rect(-w / 2, -h / 2, w, h)
      gfx.stroke({ width: 1, color: 0xffffff, alpha: 0.2 })
      container.addChild(gfx)

      // Emoji overlay
      const emoji = new Text({
        text: b.emoji || "🏗️",
        style: new TextStyle({ fontSize: 10, align: "center" }),
      })
      emoji.anchor.set(0.5, 0.5)
      container.addChild(emoji)

      // Health bar (small, below building)
      const healthBar = new Graphics()
      healthBar.y = h / 2 + 2
      const hp = Math.max(0, Math.min(1, (b.health || 100) / 100))
      const barW = w
      healthBar.rect(-barW / 2, 0, barW, 2)
      healthBar.fill({ color: 0x333333, alpha: 0.5 })
      healthBar.rect(-barW / 2, 0, barW * hp, 2)
      healthBar.fill(hp > 0.5 ? 0x4ade80 : hp > 0.25 ? 0xfbbf24 : 0xef4444)
      container.addChild(healthBar)

      this.buildingLayer.addChild(container)
      this.buildingSprites.set(b.id, { container, gfx, healthBar })
    }

    // Remove destroyed buildings
    for (const [id, sprite] of this.buildingSprites) {
      if (!seen.has(id)) {
        this.buildingLayer.removeChild(sprite.container)
        sprite.container.destroy({ children: true })
        this.buildingSprites.delete(id)
      }
    }
  }

  // Add a resource node icon to a tile
  addResourceNode(x, y, nodeType) {
    const key = `${x},${y}`
    if (this.resourceNodeSprites.has(key)) return // already has a node

    const icon = RESOURCE_NODE_ICONS[nodeType] || "📦"
    const text = new Text({
      text: icon,
      style: new TextStyle({ fontSize: 10, align: "center" }),
    })
    text.anchor.set(0.5, 0.5)
    text.x = x * TILE_SIZE + TILE_SIZE / 2
    text.y = y * TILE_SIZE + TILE_SIZE / 2
    this.resourceNodeLayer.addChild(text)
    this.resourceNodeSprites.set(key, text)
  }

  _hashCode(str) {
    let hash = 0
    for (let i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.charCodeAt(i)
      hash |= 0
    }
    return Math.abs(hash)
  }

  destroy() {
    if (this.app) {
      this.app.destroy(true)
      this.app = null
    }
  }
}
