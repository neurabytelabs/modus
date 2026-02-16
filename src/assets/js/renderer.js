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

export default class Renderer {
  constructor(container) {
    this.container = container
    this.app = null
    this.worldContainer = null
    this.terrainLayer = null
    this.agentLayer = null
    this.agentSprites = new Map() // id -> {gfx, label, targetX, targetY}

    // Camera state
    this.dragging = false
    this.dragStart = { x: 0, y: 0 }
    this.camStart = { x: 0, y: 0 }
    this.scale = 1.0
  }

  async init() {
    this.app = new Application()
    await this.app.init({
      background: 0x0f172a,
      resizeTo: this.container,
      antialias: true,
      autoDensity: true,
      resolution: window.devicePixelRatio || 1,
    })
    this.container.appendChild(this.app.canvas)

    // World container (camera target)
    this.worldContainer = new Container()
    this.app.stage.addChild(this.worldContainer)

    // Layers
    this.terrainLayer = new Container()
    this.agentLayer = new Container()
    this.worldContainer.addChild(this.terrainLayer)
    this.worldContainer.addChild(this.agentLayer)

    // Center camera
    const totalW = GRID_W * TILE_SIZE
    const totalH = GRID_H * TILE_SIZE
    this.worldContainer.x = (this.app.screen.width - totalW) / 2
    this.worldContainer.y = (this.app.screen.height - totalH) / 2

    this._setupCamera()
    this._startAnimLoop()
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
  }

  // ── Agents ───────────────────────────────────────────────

  updateAgents(agents) {
    const seen = new Set()

    for (const agent of agents) {
      seen.add(agent.id)
      const px = agent.x * TILE_SIZE + TILE_SIZE / 2
      const py = agent.y * TILE_SIZE + TILE_SIZE / 2

      if (this.agentSprites.has(agent.id)) {
        // Update target for lerp
        const sprite = this.agentSprites.get(agent.id)
        sprite.targetX = px
        sprite.targetY = py
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

        this.agentLayer.addChild(agentContainer)
        this.agentSprites.set(agent.id, {
          container: agentContainer,
          gfx,
          label,
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
      }
    }
  }

  // ── Animation Loop (lerp) ───────────────────────────────

  _startAnimLoop() {
    this.app.ticker.add(() => {
      const lerp = 0.15
      for (const [, sprite] of this.agentSprites) {
        const c = sprite.container
        c.x += (sprite.targetX - c.x) * lerp
        c.y += (sprite.targetY - c.y) * lerp
      }
    })
  }

  // ── Camera Controls ─────────────────────────────────────

  _setupCamera() {
    const canvas = this.app.canvas

    // Pan (drag)
    canvas.addEventListener("pointerdown", (e) => {
      this.dragging = true
      this.dragStart = { x: e.clientX, y: e.clientY }
      this.camStart = { x: this.worldContainer.x, y: this.worldContainer.y }
      canvas.style.cursor = "grabbing"
    })

    canvas.addEventListener("pointermove", (e) => {
      if (!this.dragging) return
      this.worldContainer.x = this.camStart.x + (e.clientX - this.dragStart.x)
      this.worldContainer.y = this.camStart.y + (e.clientY - this.dragStart.y)
    })

    canvas.addEventListener("pointerup", () => {
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
