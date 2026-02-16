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

    this.renderer.init().then(() => {
      // Set up agent click callback
      this.renderer.onAgentClick = (agentId) => {
        this.renderer.selectAgent(agentId)
        if (this.worldSocket) {
          this.worldSocket.getAgentDetail(agentId, (detail) => {
            this.pushEvent("select_agent", { agent: detail })
          })
        }
      }

      this.worldSocket = new WorldSocket({
        onFullState: (state) => {
          if (state.grid) this.renderer.renderTerrain(state.grid)
          if (state.agents) {
            this.renderer.updateAgents(state.agents)
            this.lastAgents = state.agents
          }
          this.pushEvent("world_state", {
            tick: state.tick || 0,
            agent_count: state.agents ? state.agents.length : 0,
            status: state.status || "paused",
          })
        },
        onDelta: (delta) => {
          if (delta.agents) {
            this.renderer.updateAgents(delta.agents)
            this.lastAgents = delta.agents
          }
          if (delta.tick != null) {
            this.pushEvent("tick_update", {
              tick: delta.tick,
              agent_count: delta.agent_count || 0,
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
      })
      this.worldSocket.connect()
    })

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
    this.handleEvent("create_world", (data) => {
      if (this.worldSocket) this.worldSocket.createWorld(data.template, data.population, data.danger)
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
