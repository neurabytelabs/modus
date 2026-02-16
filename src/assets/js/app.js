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
          if (state.grid) this.renderer.renderTerrain(state.grid)
          if (state.agents) this.renderer.updateAgents(state.agents)
        }
        if (state.agents) this.lastAgents = state.agents
        this.pushEvent("world_state", {
          tick: state.tick || 0,
          agent_count: state.agents ? state.agents.length : 0,
          status: state.status || "paused",
        })
      },
      onDelta: (delta) => {
        if (this.rendererReady && delta.agents) {
          this.renderer.updateAgents(delta.agents)
        }
        if (delta.agents) this.lastAgents = delta.agents
        if (delta.tick != null) {
          this.pushEvent("tick_update", {
            tick: delta.tick,
            agent_count: delta.agent_count || 0,
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
      if (this.worldSocket) {
        this.worldSocket.chatAgent(data.agent_id, data.message)
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

// ── LiveSocket Setup ───────────────────────────────────────

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

liveSocket.connect()
window.liveSocket = liveSocket
