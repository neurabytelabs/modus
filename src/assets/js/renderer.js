/**
 * MODUS 2D Renderer — Pixi.js v8
 *
 * Renders the 50x50 tile world with terrain, agents, camera controls.
 */
import { Application, Container, Graphics, Text, TextStyle } from "pixi.js"

const TILE_SIZE = 16
const AGENT_RADIUS = 6
const GRID_W = 50
const GRID_H = 50

const TERRAIN_COLORS = {
  grass:    0x4ade80,
  water:    0x60a5fa,
  forest:   0x166534,
  mountain: 0x78716c,
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

    // Agent click callback
    this.onAgentClick = null
    this.selectedAgentId = null

    // Mind View toggle
    this.mindViewActive = false

    // Camera state
    this.dragging = false
    this.didDrag = false
    this.dragStart = { x: 0, y: 0 }
    this.camStart = { x: 0, y: 0 }
    this.scale = 1.0
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
    this.worldContainer.addChild(this.terrainLayer)
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
    this._startAnimLoop()

    // Hide loading skeleton
    const skeleton = document.getElementById("canvas-skeleton")
    if (skeleton) skeleton.style.display = "none"
  }

  // ── Terrain ──────────────────────────────────────────────

  renderTerrain(grid) {
    this.terrainLayer.removeChildren()
    const gfx = new Graphics()

    for (const cell of grid) {
      const color = TERRAIN_COLORS[cell.terrain] || 0x333333
      gfx.rect(cell.x * TILE_SIZE, cell.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
      gfx.fill(color)
    }

    // Grid lines (subtle)
    gfx.setStrokeStyle({ width: 0.5, color: 0xffffff, alpha: 0.04 })
    for (let x = 0; x <= GRID_W; x++) {
      gfx.moveTo(x * TILE_SIZE, 0)
      gfx.lineTo(x * TILE_SIZE, GRID_H * TILE_SIZE)
      gfx.stroke()
    }
    for (let y = 0; y <= GRID_H; y++) {
      gfx.moveTo(0, y * TILE_SIZE)
      gfx.lineTo(GRID_W * TILE_SIZE, y * TILE_SIZE)
      gfx.stroke()
    }

    this.terrainLayer.addChild(gfx)

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
      gather: "🌾", find_food: "🍖",
      find_friend: "💬", talk: "💬",
      go_home_sleep: "😴", sleep: "😴",
      help_nearby: "🤝", flee: "🏃",
      idle: "",
      reasoning: "💭",
    }
    this.app.ticker.add((ticker) => {
      const lerp = 0.15
      glowPhase += ticker.deltaTime * 0.08
      const glowAlpha = 0.3 + Math.sin(glowPhase) * 0.2
      const breathScale = 1.0 + Math.sin(glowPhase * 1.5) * 0.03
      const bounceY = Math.sin(glowPhase * 3) * 1.5

      // ── Relationship Lines ──
      this._drawRelationshipLines()

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
      const dx = e.clientX - this.dragStart.x
      const dy = e.clientY - this.dragStart.y
      if (Math.abs(dx) > 3 || Math.abs(dy) > 3) this.didDrag = true
      this.worldContainer.x = this.camStart.x + dx
      this.worldContainer.y = this.camStart.y + dy
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

    // Zoom (scroll)
    canvas.addEventListener("wheel", (e) => {
      e.preventDefault()
      const delta = e.deltaY > 0 ? 0.9 : 1.1
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
    }, { passive: false })
  }

  // ── Helpers ─────────────────────────────────────────────

  _handleClick(e) {
    if (!this.onAgentClick) return
    const rect = this.app.canvas.getBoundingClientRect()
    const mx = e.clientX - rect.left
    const my = e.clientY - rect.top
    // Convert to world coordinates
    const wx = (mx - this.worldContainer.x) / this.scale
    const wy = (my - this.worldContainer.y) / this.scale

    // Debug: log all agent positions
    const agentPositions = []
    for (const [id, sprite] of this.agentSprites) {
      agentPositions.push({id: id.slice(0,8), tx: sprite.targetX.toFixed(0), ty: sprite.targetY.toFixed(0), cx: sprite.container.x.toFixed(0), cy: sprite.container.y.toFixed(0)})
    }
    console.log("[MODUS] Click at world:", wx.toFixed(1), wy.toFixed(1), "agents:", this.agentSprites.size, "positions:", JSON.stringify(agentPositions))

    // Find closest agent within click radius (check both target and current lerped position)
    let closest = null
    let closestDist = TILE_SIZE * 2.5

    for (const [id, sprite] of this.agentSprites) {
      // Distance to target position
      const dx1 = sprite.targetX - wx
      const dy1 = sprite.targetY - wy
      const dist1 = Math.sqrt(dx1 * dx1 + dy1 * dy1)
      // Distance to current lerped position
      const dx2 = sprite.container.x - wx
      const dy2 = sprite.container.y - wy
      const dist2 = Math.sqrt(dx2 * dx2 + dy2 * dy2)
      // Use whichever is closer
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
