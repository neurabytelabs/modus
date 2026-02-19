import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import Renderer from "./renderer"
import WorldSocket from "./world_socket"

// ── LiveView Hooks ─────────────────────────────────────────

const Hooks = {}

// ── Export & Share Hooks ────────────────────────────────────

Hooks.ImportFile = {
  mounted() {
    const dropzone = this.el
    const input = dropzone.querySelector("input[type=file]")
    const hook = this

    dropzone.addEventListener("click", () => input.click())

    input.addEventListener("change", (e) => {
      const file = e.target.files[0]
      if (!file) return
      const reader = new FileReader()
      reader.onload = (ev) => {
        hook.pushEvent("do_import_json", { json: ev.target.result })
      }
      reader.readAsText(file)
    })

    dropzone.addEventListener("dragover", (e) => {
      e.preventDefault()
      dropzone.classList.add("border-purple-500/50")
    })
    dropzone.addEventListener("dragleave", () => {
      dropzone.classList.remove("border-purple-500/50")
    })
    dropzone.addEventListener("drop", (e) => {
      e.preventDefault()
      dropzone.classList.remove("border-purple-500/50")
      const file = e.dataTransfer.files[0]
      if (!file) return
      const reader = new FileReader()
      reader.onload = (ev) => {
        hook.pushEvent("do_import_json", { json: ev.target.result })
      }
      reader.readAsText(file)
    })
  }
}

Hooks.CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const targetId = this.el.dataset.target
      const target = document.getElementById(targetId)
      if (target) {
        navigator.clipboard.writeText(target.value || target.textContent)
        this.el.textContent = "✅ Copied!"
        setTimeout(() => { this.el.textContent = "📋 Copy to Clipboard" }, 2000)
      }
    })
  }
}

Hooks.WorldCanvas = {
  mounted() {
    this.renderer = new Renderer(this.el)
    this.worldSocket = null
    this.lastAgents = []
    this.rendererReady = false
    this.selectedAgentId = null

    // Init renderer with timeout (Pixi.js may hang without WebGL)
    const initWithTimeout = Promise.race([
      this.renderer.init(),
      new Promise((_, reject) => setTimeout(() => reject(new Error("Pixi init timeout (5s)")), 5000))
    ])

    initWithTimeout.then(() => {
      this.rendererReady = true
      window.__modusRenderer = this.renderer
      window.__modusSocket = this.worldSocket
      // Update zoom level indicator in top bar
      this.renderer.onZoomLevelChange = (level) => {
        const el = document.getElementById("zoom-level-indicator")
        if (el) el.textContent = level.toUpperCase()
      }
      console.log("[MODUS] Renderer initialized, exposed on window.__modusRenderer")
    }).catch(err => {
      console.error("[MODUS] Renderer failed:", err)
      const skel = document.getElementById("canvas-skeleton")
      if (skel) skel.innerHTML = '<div style="color:#f87171;font-size:14px;text-align:center;padding:20px"><p>⚠️ ' + err.message + '</p><p style="color:#64748b;font-size:11px;margin-top:8px">Simulation running — visual renderer unavailable</p></div>'
    })

    // Set up agent click callback (safe even if renderer not ready)
    // Store hook ref for async callbacks
    this.el.__modusHook = this
    this.renderer.onAgentClick = (agentId) => {
      console.log("[MODUS] onAgentClick fired:", agentId)
      // Get fresh hook reference from DOM element
      const hook = document.getElementById("world-canvas").__modusHook
      if (hook && hook.renderer && hook.rendererReady) hook.renderer.selectAgent(agentId)
      const ws = hook ? hook.worldSocket : null
      if (ws) {
        ws.getAgentDetail(agentId, (detail) => {
          console.log("[MODUS] Got agent detail, pushing to LiveView:", detail?.name)
          try {
            // Use fresh hook reference for pushEvent
            const freshHook = document.getElementById("world-canvas").__modusHook
            if (freshHook) {
              freshHook.selectedAgentId = detail.id
              freshHook.pushEvent("select_agent", { agent: detail })
              // Notify channel to track selected agent for live updates
              if (freshHook.worldSocket && freshHook.worldSocket.channel) {
                freshHook.worldSocket.channel.push("select_agent", { agent_id: detail.id })
              }
              console.log("[MODUS] pushEvent select_agent sent via hook")
            } else {
              console.error("[MODUS] No hook reference available")
            }
          } catch (err) {
            console.error("[MODUS] pushEvent failed:", err)
          }
        })
      } else {
        console.warn("[MODUS] No worldSocket available for agent detail")
      }
    }

    // Connect WebSocket immediately
    this.worldSocket = new WorldSocket({
      onFullState: (state) => {
        if (this.rendererReady) {
          if (state.grid_width && state.grid_height) {
            this.renderer.setGridSize(state.grid_width, state.grid_height)
          }
          if (state.grid) this.renderer.renderTerrain(state.grid)
          if (state.agents) this.renderer.updateAgents(state.agents)
          if (state.buildings) this.renderer.updateBuildings(state.buildings)
          if (state.neighborhoods) this.renderer.updateNeighborhoods(state.neighborhoods)
          if (state.world_events) this.renderer.updateWorldEvents(state.world_events)
          // Environment
          if (state.time_of_day) this.renderer.updateEnvironment(state)
          // Seasons
          if (state.season) this.renderer.updateSeason(state.season)
        }
        if (state.agents) this.lastAgents = state.agents
        this.pushEvent("world_state", {
          tick: state.tick || 0,
          agent_count: state.agents ? state.agents.length : 0,
          status: state.status || "paused",
          time_of_day: state.time_of_day || "day",
        })
      },
      onDelta: (delta) => {
        if (this.rendererReady && delta.agents) {
          this.renderer.updateAgents(delta.agents)
        }
        if (this.rendererReady && delta.buildings) {
          this.renderer.updateBuildings(delta.buildings)
        }
        if (this.rendererReady && delta.neighborhoods) {
          this.renderer.updateNeighborhoods(delta.neighborhoods)
        }
        if (this.rendererReady && delta.world_events) {
          this.renderer.updateWorldEvents(delta.world_events)
        }
        // Update environment visuals
        if (this.rendererReady && delta.cycle_progress != null) {
          this.renderer.updateEnvironment(delta)
        }
        // Season update from delta
        if (this.rendererReady && delta.season) {
          this.renderer.updateSeason(delta.season)
        }
        if (delta.agents) this.lastAgents = delta.agents
        if (delta.tick != null) {
          this.pushEvent("tick_update", {
            tick: delta.tick,
            agent_count: delta.agent_count || 0,
            time_of_day: delta.time_of_day || "day",
            day_phase: delta.day_phase || "day",
            season: delta.season || null,
          })
        }

        // Real-time agent detail update
        if (this.selectedAgentId && this.worldSocket && delta.tick != null && delta.tick % 5 === 0) {
          this.worldSocket.getAgentDetail(this.selectedAgentId, (detail) => {
            this.pushEvent("agent_detail_update", { detail })
          })
        }
      },
      onTick: (data) => {
        this.pushEvent("tick_update", {
          tick: data.tick,
          agent_count: data.agent_count || 0,
        })
      },
      onStatus: (data) => {
        this.pushEvent("status_change", { status: data.status })
      },
      onChatReply: (data) => {
        this.pushEvent("chat_response", { reply: data.reply })
      },
      onAgentDetailUpdate: (data) => {
        if (data.detail && this.selectedAgentId && data.detail.id === this.selectedAgentId) {
          this.pushEvent("agent_detail_update", { detail: data.detail })
        }
      },
    })
    this.worldSocket.connect()

    // Listen for control events from LiveView
    this.handleEvent("start_simulation", () => {
      if (this.worldSocket) this.worldSocket.startSimulation()
    })
    this.handleEvent("pause_simulation", () => {
      if (this.worldSocket) this.worldSocket.pauseSimulation()
    })
    this.handleEvent("reset_simulation", () => {
      if (this.worldSocket) this.worldSocket.resetSimulation()
    })
    this.handleEvent("chat_to_agent", (data) => {
      console.log("[MODUS] chat_to_agent received from LiveView:", data.agent_id, data.message)
      if (this.worldSocket) {
        this.worldSocket.chatAgent(data.agent_id, data.message)
        console.log("[MODUS] chatAgent pushed to channel")
      } else {
        console.error("[MODUS] worldSocket not available for chat!")
      }
    })
    this.handleEvent("set_speed", (data) => {
      if (this.worldSocket) this.worldSocket.setSpeed(data.speed)
    })
    this.handleEvent("inject_event", (data) => {
      if (this.worldSocket) this.worldSocket.injectEvent(data.event_type)
    })
    this.handleEvent("trigger_world_event", (data) => {
      if (this.worldSocket) this.worldSocket.triggerWorldEvent(data.event_type)
    })
    this.handleEvent("deselect_agent", () => {
      this.selectedAgentId = null
      if (this.rendererReady) this.renderer.selectAgent(null)
      if (this.worldSocket && this.worldSocket.channel) {
        this.worldSocket.channel.push("deselect_agent", {})
      }
    })
    this.handleEvent("create_world", (data) => {
      if (this.worldSocket) this.worldSocket.createWorld(data.template, data.population, data.danger)
    })
    this.handleEvent("toggle_mind_view", (data) => {
      if (this.rendererReady && this.renderer) {
        this.renderer.mindViewActive = data.active
        if (this.renderer.terrainLayer) {
          this.renderer.terrainLayer.alpha = data.active ? 0.3 : 1.0
        }
      }
    })
    // Deus features
    this.handleEvent("toggle_god_mode", (data) => {
      if (this.rendererReady && this.renderer) {
        this.renderer.setGodMode(data.active)
      }
    })
    this.handleEvent("toggle_cinematic", (data) => {
      if (this.rendererReady && this.renderer) {
        this.renderer.setCinematicMode(data.active)
      }
    })
    this.handleEvent("take_screenshot", () => {
      if (this.rendererReady && this.renderer) {
        this.renderer.takeScreenshot()
      }
    })
    this.handleEvent("screenshot_with_overlay", (data) => {
      if (this.rendererReady && this.renderer && this.renderer.app && this.renderer.app.canvas) {
        const canvas = this.renderer.app.canvas
        // Create overlay canvas
        const overlay = document.createElement("canvas")
        overlay.width = canvas.width
        overlay.height = canvas.height
        const ctx = overlay.getContext("2d")
        ctx.drawImage(canvas, 0, 0)
        // Draw world name overlay
        const name = data.world_name || "MODUS"
        const tick = data.tick || 0
        // Background bar
        ctx.fillStyle = "rgba(0,0,0,0.6)"
        ctx.fillRect(0, overlay.height - 48, overlay.width, 48)
        // World name
        ctx.font = "bold 20px 'Inter', sans-serif"
        ctx.fillStyle = "#e2e8f0"
        ctx.fillText(name, 16, overlay.height - 18)
        // Tick + MODUS branding
        ctx.font = "12px 'JetBrains Mono', monospace"
        ctx.fillStyle = "#94a3b8"
        ctx.textAlign = "right"
        ctx.fillText(`t:${tick} · MODUS`, overlay.width - 16, overlay.height - 18)
        // Download
        const link = document.createElement("a")
        link.download = `modus-${name.replace(/\s+/g, "-").toLowerCase()}-t${tick}.png`
        link.href = overlay.toDataURL("image/png")
        link.click()
      }
    })
    this.handleEvent("download_file", (data) => {
      const blob = new Blob([data.content], { type: data.mime || "text/plain" })
      const url = URL.createObjectURL(blob)
      const link = document.createElement("a")
      link.download = data.filename || "download.txt"
      link.href = url
      link.click()
      URL.revokeObjectURL(url)
    })
    this.handleEvent("world_loaded", (_data) => {
      // After load, the channel will push full_state which re-renders everything
      console.log("[MODUS] World loaded, waiting for full_state broadcast")
      this.selectedAgentId = null
      if (this.rendererReady) this.renderer.selectAgent(null)
    })

    // ── Build Mode ──────────────────────────────────────────
    this.handleEvent("toggle_build_mode", (data) => {
      if (this.rendererReady && this.renderer) {
        this.renderer.setBuildMode(data.active)
      }
    })
    this.handleEvent("set_build_brush", (data) => {
      if (this.rendererReady && this.renderer) {
        this.renderer.setBuildBrush(data.brush, data.type || "terrain")
      }
    })

    // ── Agent Designer ──────────────────────────────────────
    this.handleEvent("designer_place_mode", (data) => {
      console.log("[MODUS] Designer place mode:", data)
      this._designerPlacing = data
      if (this.rendererReady && this.renderer && this.renderer.app && this.renderer.app.canvas) {
        this.renderer.app.canvas.style.cursor = "crosshair"
      }
    })

    // Handle map click for agent/animal placement — intercept renderer's _handleClick
    this._designerPlacing = null
    const origHandleClick = this.renderer._handleClick.bind(this.renderer)
    this.renderer._handleClick = (e) => {
      if (this._designerPlacing) {
        const rect = this.renderer.app.canvas.getBoundingClientRect()
        const mx = e.clientX - rect.left
        const my = e.clientY - rect.top
        const wx = (mx - this.renderer.worldContainer.x) / this.renderer.scale
        const wy = (my - this.renderer.worldContainer.y) / this.renderer.scale
        const tileSize = 16 // TILE_SIZE from renderer
        const tileX = Math.floor(wx / tileSize)
        const tileY = Math.floor(wy / tileSize)

        const dp = this._designerPlacing
        this._designerPlacing = null
        this.renderer.app.canvas.style.cursor = "grab"

        if (dp.mode === "agent") {
          const d = dp.data
          this.worldSocket.spawnCustomAgent({
            name: d.name || "Unnamed",
            occupation: d.occupation,
            mood: d.mood,
            personality: d.personality,
            x: tileX,
            y: tileY
          }, (err, resp) => {
            if (!err) console.log("[MODUS] Agent placed:", resp)
          })
        } else if (dp.mode === "animal") {
          this.worldSocket.spawnAnimal(dp.data.animal, tileX, tileY, (err, resp) => {
            if (!err) console.log("[MODUS] Animal placed:", resp)
          })
        }
        this.pushEvent("agent_placed", {})
        return
      }
      origHandleClick(e)
    }

    // Debounced paint to avoid flooding the channel
    this._lastPaint = ""
    this._paintThrottle = 0

    // Wire up renderer paint callbacks
    this.renderer.onPaintTerrain = (x, y, terrain) => {
      const key = `${x},${y},${terrain}`
      if (key === this._lastPaint) return
      this._lastPaint = key
      if (this.worldSocket) {
        this.worldSocket.paintTerrain(x, y, terrain)
      }
    }
    this.renderer.onPlaceResource = (x, y, nodeType) => {
      const key = `r${x},${y},${nodeType}`
      if (key === this._lastPaint) return
      this._lastPaint = key
      if (this.worldSocket) {
        this.worldSocket.placeResource(x, y, nodeType)
      }
    }
    this.renderer.onPlaceBuilding = (x, y, type) => {
      const key = `b${x},${y},${type}`
      if (key === this._lastPaint) return
      this._lastPaint = key
      if (this.worldSocket) {
        this.worldSocket.placeBuilding(x, y, type)
      }
    }

    // Listen for broadcast updates
    if (this.worldSocket) {
      this.worldSocket.onTerrainPainted = (data) => {
        if (this.rendererReady && this.renderer) {
          this.renderer.paintTile(data.x, data.y, data.terrain)
        }
      }
      this.worldSocket.onResourcePlaced = (data) => {
        if (this.rendererReady && this.renderer) {
          this.renderer.addResourceNode(data.x, data.y, data.node_type)
        }
      }
      this.worldSocket.onWorldEvent = (data) => {
        // Show toast notification for world events
        this.pushEvent("world_event_toast", {
          emoji: data.emoji,
          type: data.type,
          severity: data.severity,
        })
      }
      this.worldSocket.onWorldEventEnded = (data) => {
        if (this.rendererReady && this.renderer) {
          this.renderer.removeWorldEvent(data.id)
        }
      }
      this.worldSocket.onSeasonChange = (data) => {
        // Update renderer season
        if (this.rendererReady && this.renderer) {
          this.renderer.updateSeason(data)
        }
        // Show toast
        this.pushEvent("season_change_toast", {
          emoji: data.emoji,
          season_name: data.season_name,
        })
      }
    }
  },

  destroyed() {
    if (this.worldSocket) this.worldSocket.disconnect()
    if (this.renderer) this.renderer.destroy()
  },
}

// ── Demo Canvas Hook (read-only, no god mode) ──────────────

Hooks.DemoCanvas = {
  mounted() {
    this.renderer = new Renderer(this.el)
    this.worldSocket = null
    this.rendererReady = false

    const initWithTimeout = Promise.race([
      this.renderer.init(),
      new Promise((_, reject) => setTimeout(() => reject(new Error("Pixi init timeout (5s)")), 5000))
    ])

    initWithTimeout.then(() => {
      this.rendererReady = true
      console.log("[MODUS Demo] Renderer initialized")
      this._setupDemoKeyboardShortcuts()
    }).catch(err => {
      console.error("[MODUS Demo] Renderer failed:", err)
      const skel = document.getElementById("canvas-skeleton")
      if (skel) skel.innerHTML = '<div style="color:#f87171;font-size:14px;text-align:center;padding:20px"><p>⚠️ ' + err.message + '</p><p style="color:#64748b;font-size:11px;margin-top:8px">Simulation running — visual renderer unavailable</p></div>'
    })

    // Connect to world:lobby in read-only mode
    this.worldSocket = new WorldSocket({
      onFullState: (state) => {
        if (this.rendererReady) {
          if (state.grid_width && state.grid_height) {
            this.renderer.setGridSize(state.grid_width, state.grid_height)
          }
          if (state.grid) this.renderer.renderTerrain(state.grid)
          if (state.agents) this.renderer.updateAgents(state.agents)
          if (state.buildings) this.renderer.updateBuildings(state.buildings)
          if (state.neighborhoods) this.renderer.updateNeighborhoods(state.neighborhoods)
          if (state.world_events) this.renderer.updateWorldEvents(state.world_events)
          if (state.time_of_day) this.renderer.updateEnvironment(state)
          if (state.season) this.renderer.updateSeason(state.season)
        }
        this.pushEvent("tick_update", {
          tick: state.tick || 0,
          agent_count: state.agents ? state.agents.length : 0,
          time_of_day: state.time_of_day || "day",
          season: state.season || null,
          weather: state.weather || null,
        })
      },
      onDelta: (delta) => {
        if (this.rendererReady) {
          if (delta.agents) this.renderer.updateAgents(delta.agents)
          if (delta.buildings) this.renderer.updateBuildings(delta.buildings)
          if (delta.neighborhoods) this.renderer.updateNeighborhoods(delta.neighborhoods)
          if (delta.world_events) this.renderer.updateWorldEvents(delta.world_events)
          if (delta.cycle_progress != null) this.renderer.updateEnvironment(delta)
          if (delta.season) this.renderer.updateSeason(delta.season)
        }
        if (delta.tick != null) {
          this.pushEvent("tick_update", {
            tick: delta.tick,
            agent_count: delta.agent_count || 0,
            time_of_day: delta.time_of_day || "day",
            day_phase: delta.day_phase || "day",
            season: delta.season || null,
            weather: delta.weather || null,
          })
        }
      },
      onTick: () => {},
      onStatus: () => {},
      onChatReply: () => {},
      onAgentDetailUpdate: () => {},
    })
    this.worldSocket.connect()

    // Season change updates
    if (this.worldSocket) {
      this.worldSocket.onSeasonChange = (data) => {
        if (this.rendererReady) this.renderer.updateSeason(data)
      }
      this.worldSocket.onWorldEvent = () => {}
      this.worldSocket.onWorldEventEnded = (data) => {
        if (this.rendererReady) this.renderer.removeWorldEvent(data.id)
      }
    }
  },

  destroyed() {
    if (this._demoKeyHandler) document.removeEventListener("keydown", this._demoKeyHandler)
    if (this.worldSocket) this.worldSocket.disconnect()
    if (this.renderer) this.renderer.destroy()
  },

  _setupDemoKeyboardShortcuts() {
    const PAN_STEP = 40
    const self = this
    this._demoKeyHandler = (e) => {
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT") return
      if (!self.rendererReady || !self.renderer) return

      const r = self.renderer
      switch (e.code) {
        case "ArrowUp":
          e.preventDefault()
          if (r.stage) r.stage.y += PAN_STEP
          break
        case "ArrowDown":
          e.preventDefault()
          if (r.stage) r.stage.y -= PAN_STEP
          break
        case "ArrowLeft":
          e.preventDefault()
          if (r.stage) r.stage.x += PAN_STEP
          break
        case "ArrowRight":
          e.preventDefault()
          if (r.stage) r.stage.x -= PAN_STEP
          break
        case "Equal":
        case "NumpadAdd":
          e.preventDefault()
          if (r.setZoomLevel) {
            const levels = ["world", "region", "local"]
            const idx = levels.indexOf(r.zoomLevel)
            if (idx < levels.length - 1) r.setZoomLevel(levels[idx + 1])
          } else if (r.stage) {
            r.stage.scale.x = Math.min(r.stage.scale.x * 1.2, 5)
            r.stage.scale.y = Math.min(r.stage.scale.y * 1.2, 5)
          }
          break
        case "Minus":
        case "NumpadSubtract":
          e.preventDefault()
          if (r.setZoomLevel) {
            const levels = ["world", "region", "local"]
            const idx = levels.indexOf(r.zoomLevel)
            if (idx > 0) r.setZoomLevel(levels[idx - 1])
          } else if (r.stage) {
            r.stage.scale.x = Math.max(r.stage.scale.x / 1.2, 0.2)
            r.stage.scale.y = Math.max(r.stage.scale.y / 1.2, 0.2)
          }
          break
      }
    }
    document.addEventListener("keydown", this._demoKeyHandler)
  },
}

// ── Keyboard Shortcuts ─────────────────────────────────────

document.addEventListener("keydown", (e) => {
  // Don't trigger shortcuts when typing in inputs
  if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT") return

  switch (e.code) {
    case "Space":
      e.preventDefault()
      // Toggle play/pause via LiveView
      const btn = document.querySelector("[phx-click='start'], [phx-click='pause']")
      if (btn) btn.click()
      break
    case "Digit1":
    case "Numpad1":
      document.querySelector("[phx-value-speed='1']")?.click()
      break
    case "Digit5":
    case "Numpad5":
      document.querySelector("[phx-value-speed='5']")?.click()
      break
    case "Digit0":
    case "Numpad0":
      document.querySelector("[phx-value-speed='10']")?.click()
      break
    case "KeyM":
      if (window.__modusRenderer) {
        const visible = window.__modusRenderer.toggleMinimap()
        console.log("[MODUS] Minimap:", visible ? "ON" : "OFF")
      }
      break
    case "KeyB":
      // Build mode toggle (priority over mind view when not in build mode)
      document.querySelector("[phx-click='toggle_build_mode']")?.click()
      break
    case "KeyG":
      // God Mode toggle
      document.querySelector("[phx-click='toggle_god_mode']")?.click()
      break
    case "KeyC":
      // Cinematic camera toggle
      document.querySelector("[phx-click='toggle_cinematic']")?.click()
      break
    case "KeyP":
      // Screenshot with overlay
      document.querySelector("[phx-click='screenshot_with_overlay']")?.click()
      break
    case "KeyT":
      // Text mode toggle
      {
        const hook = document.getElementById("world-canvas")?.__modusHook
        if (hook) hook.pushEvent("toggle_text_mode", {})
      }
      break
    case "KeyZ":
      // Zen mode toggle
      {
        const hook = document.getElementById("world-canvas")?.__modusHook
        if (hook) hook.pushEvent("toggle_zen_mode", {})
      }
      break
    case "Equal": // + key
    case "NumpadAdd":
      // Zoom in one level
      if (window.__modusRenderer) {
        const r = window.__modusRenderer
        const levels = ["world", "region", "local"]
        const idx = levels.indexOf(r.zoomLevel)
        if (idx < levels.length - 1) {
          const lvl = r.setZoomLevel(levels[idx + 1])
          console.log("[MODUS] Zoom:", lvl)
        }
      }
      break
    case "Minus":
    case "NumpadSubtract":
      // Zoom out one level
      if (window.__modusRenderer) {
        const r = window.__modusRenderer
        const levels = ["world", "region", "local"]
        const idx = levels.indexOf(r.zoomLevel)
        if (idx > 0) {
          const lvl = r.setZoomLevel(levels[idx - 1])
          console.log("[MODUS] Zoom:", lvl)
        }
      }
      break
    case "KeyF":
      // Fog of war toggle
      if (window.__modusRenderer) {
        const fow = window.__modusRenderer.toggleFogOfWar()
        console.log("[MODUS] Fog of War:", fow ? "ON" : "OFF")
      }
      break
    case "Escape":
      // Deselect agent
      document.querySelector("[phx-click='deselect_agent']")?.click()
      break
  }
})

// ── LiveSocket Setup ───────────────────────────────────────

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

liveSocket.connect()
window.liveSocket = liveSocket
