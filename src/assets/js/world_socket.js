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
    this.onAgentDetailUpdate = opts.onAgentDetailUpdate || (() => {})
    this.onTerrainPainted = opts.onTerrainPainted || (() => {})
    this.onResourcePlaced = opts.onResourcePlaced || (() => {})
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

    this.channel.on("agent_detail_update", (payload) => {
      this.onAgentDetailUpdate(payload)
    })

    this.channel.on("terrain_painted", (payload) => {
      this.onTerrainPainted(payload)
    })

    this.channel.on("resource_placed", (payload) => {
      this.onResourcePlaced(payload)
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

  saveWorld(name, callback) {
    this.channel
      .push("save_world", { name: name || "" })
      .receive("ok", (resp) => {
        console.log("[MODUS] World saved:", resp)
        if (callback) callback(null, resp)
      })
      .receive("error", (err) => {
        console.error("[MODUS] Save failed:", err)
        if (callback) callback(err)
      })
  }

  loadWorld(worldId, callback) {
    this.channel
      .push("load_world", { world_id: worldId })
      .receive("ok", (resp) => {
        console.log("[MODUS] World loaded:", resp)
        if (callback) callback(null, resp)
      })
      .receive("error", (err) => {
        console.error("[MODUS] Load failed:", err)
        if (callback) callback(err)
      })
  }

  listWorlds(callback) {
    this.channel
      .push("list_worlds", {})
      .receive("ok", (resp) => {
        if (callback) callback(null, resp.worlds || [])
      })
      .receive("error", (err) => {
        if (callback) callback(err)
      })
  }

  deleteWorld(worldId, callback) {
    this.channel
      .push("delete_world", { world_id: worldId })
      .receive("ok", (resp) => {
        if (callback) callback(null, resp)
      })
      .receive("error", (err) => {
        if (callback) callback(err)
      })
  }

  // ── World Builder ──────────────────────────────────────────

  paintTerrain(x, y, terrain, callback) {
    this.channel
      .push("paint_terrain", { x, y, terrain })
      .receive("ok", () => { if (callback) callback(null) })
      .receive("error", (err) => { if (callback) callback(err) })
  }

  placeResource(x, y, nodeType, callback) {
    this.channel
      .push("place_resource", { x, y, node_type: nodeType })
      .receive("ok", () => { if (callback) callback(null) })
      .receive("error", (err) => { if (callback) callback(err) })
  }

  gatherResource(agentId, x, y) {
    this.channel.push("gather_resource", { agent_id: agentId, x, y })
  }

  placeBuilding(x, y, type, callback) {
    this.channel
      .push("place_building", { x, y, type })
      .receive("ok", () => { if (callback) callback(null) })
      .receive("error", (err) => { if (callback) callback(err) })
  }

  // ── Agent Designer ──────────────────────────────────────────

  spawnCustomAgent(data, callback) {
    this.channel
      .push("spawn_custom_agent", data)
      .receive("ok", (resp) => {
        console.log("[MODUS] Custom agent spawned:", resp)
        if (callback) callback(null, resp)
      })
      .receive("error", (err) => {
        console.error("[MODUS] Spawn failed:", err)
        if (callback) callback(err)
      })
  }

  spawnAnimal(type, x, y, callback) {
    this.channel
      .push("spawn_animal", { type, x, y })
      .receive("ok", (resp) => {
        console.log("[MODUS] Animal spawned:", resp)
        if (callback) callback(null, resp)
      })
      .receive("error", (err) => {
        console.error("[MODUS] Animal spawn failed:", err)
        if (callback) callback(err)
      })
  }

  disconnect() {
    if (this.channel) this.channel.leave()
    if (this.socket) this.socket.disconnect()
  }
}
