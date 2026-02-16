/**
 * MODUS World Socket — Phoenix Channel subscriber
 *
 * Connects to world:lobby channel, receives full state on join
 * and delta updates each tick.
 */
import { Socket } from "phoenix"

export default class WorldSocket {
  constructor(opts = {}) {
    this.onFullState = opts.onFullState || (() => {})
    this.onDelta = opts.onDelta || (() => {})
    this.onTick = opts.onTick || (() => {})
    this.onStatus = opts.onStatus || (() => {})
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

  disconnect() {
    if (this.channel) this.channel.leave()
    if (this.socket) this.socket.disconnect()
  }
}
