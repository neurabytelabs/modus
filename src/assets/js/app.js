import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import Renderer from "./renderer"
import WorldSocket from "./world_socket"

// ── LiveView Hooks ─────────────────────────────────────────

const Hooks = {}

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
          // Environment
          if (state.time_of_day) this.renderer.updateEnvironment(state)
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
        // Update environment visuals
        if (this.rendererReady && delta.cycle_progress != null) {
          this.renderer.updateEnvironment(delta)
        }
        if (delta.agents) this.lastAgents = delta.agents
        if (delta.tick != null) {
          this.pushEvent("tick_update", {
            tick: delta.tick,
            agent_count: delta.agent_count || 0,
            time_of_day: delta.time_of_day || "day",
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
    this.handleEvent("world_loaded", (_data) => {
      // After load, the channel will push full_state which re-renders everything
      console.log("[MODUS] World loaded, waiting for full_state broadcast")
      this.selectedAgentId = null
      if (this.rendererReady) this.renderer.selectAgent(null)
    })
  },

  destroyed() {
    if (this.worldSocket) this.worldSocket.disconnect()
    if (this.renderer) this.renderer.destroy()
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
      // Mind view toggle
      document.getElementById("mind-view-btn")?.click()
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
      // Screenshot
      document.querySelector("[phx-click='take_screenshot']")?.click()
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
