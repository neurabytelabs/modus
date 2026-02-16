/**
 * MODUS World Socket — Phoenix Channel subscriber
 *
 * Connects to world:lobby channel, receives full state on join
 * and delta updates each tick. Supports chat + agent detail.
 */
import { Socket } from "phoenix"

export default class WorldSocket {
  constructor(opts = {}) {
    this.onFullState = opts.onFullState || (() => {})
    this.onDelta = opts.onDelta || (() => {})
    this.onTick = opts.onTick || (() => {})
    this.onStatus = opts.onStatus || (() => {})
    this.onChatReply = opts.onChatReply || (() => {})
    this.channel = null
    this.socket = null
  }

  connect() {
    this.socket = new Socket("/socket", {
      params: { token: window.userToken || "" },
    })
    this.socket.connect()

    this.channel = this.socket.channel("world:lobby", {})

    this.channel.on("full_state", (payload) => {
      this.onFullState(payload)
    })

    this.channel.on("delta", (payload) => {
      this.onDelta(payload)
    })

    this.channel.on("tick", (payload) => {
      this.onTick(payload)
    })

    this.channel.on("status_change", (payload) => {
      this.onStatus(payload)
    })

    this.channel.on("chat_reply", (payload) => {
      this.onChatReply(payload)
    })

    this.channel
      .join()
      .receive("ok", (resp) => {
        console.log("[MODUS] Joined world:lobby", resp)
        if (resp.grid) this.onFullState(resp)
      })
      .receive("error", (resp) => {
        console.error("[MODUS] Failed to join world:lobby", resp)
      })
  }

  // Send commands to server
  startSimulation() {
    this.channel.push("start", {})
  }

  pauseSimulation() {
    this.channel.push("pause", {})
  }

  resetSimulation() {
    this.channel.push("reset", {})
  }

  chatAgent(agentId, message) {
    this.channel.push("chat_agent", { agent_id: agentId, message: message })
  }

  setSpeed(speed) {
    this.channel.push("set_speed", { speed })
  }

  injectEvent(eventType) {
    this.channel.push("inject_event", { event_type: eventType })
  }

  createWorld(template, population, danger) {
    this.channel.push("create_world", { template, population, danger })
  }

  getAgentDetail(agentId, callback) {
    this.channel
      .push("get_agent_detail", { agent_id: agentId })
      .receive("ok", (detail) => {
        if (callback) callback(detail)
      })
      .receive("error", (err) => {
        console.error("[MODUS] Agent detail error:", err)
      })
  }

  disconnect() {
    if (this.channel) this.channel.leave()
    if (this.socket) this.socket.disconnect()
  }
}
