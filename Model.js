function emptyShare() {
  return {
    active: false,
    ssid: "",
    password: "",
    clients: 0,
    ip: "",
    iface: "",
    error: ""
  }
}

function emptyStatus() {
  return {
    present: false,
    state: "missing",
    connected: false,
    operator: "",
    accessTech: "",
    signal: 0,
    ip: "",
    apn: "",
    connection: "WWAN",
    registration: "",
    deviceState: "",
    recoverable: false,
    error: "",
    share: emptyShare()
  }
}

function parseShare(raw) {
  var share = raw && typeof raw === "object" ? raw : {}
  return {
    active: share.active === true,
    ssid: String(share.ssid || ""),
    password: String(share.password || ""),
    clients: parseInt(share.clients, 10) || 0,
    ip: String(share.ip || ""),
    iface: String(share.iface || ""),
    error: String(share.error || "")
  }
}

function parseStatus(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    if (!parsed || typeof parsed !== "object") return emptyStatus()
    return {
      present: parsed.present === true,
      state: String(parsed.state || "unknown"),
      connected: parsed.connected === true,
      operator: String(parsed.operator || ""),
      accessTech: String(parsed.accessTech || ""),
      signal: parseInt(parsed.signal, 10) || 0,
      ip: String(parsed.ip || ""),
      apn: String(parsed.apn || ""),
      connection: String(parsed.connection || "WWAN"),
      registration: String(parsed.registration || ""),
      deviceState: String(parsed.deviceState || ""),
      recoverable: parsed.recoverable === true,
      error: String(parsed.error || ""),
      share: parseShare(parsed.share)
    }
  } catch (error) {
    var failed = emptyStatus()
    failed.error = "Failed to read modem status"
    return failed
  }
}

function iconFor(status) {
  // Nerd Font Material Design cellular set (nf-md-*).
  // Use codepoints, not lookalike glyphs: a nearby range renders as
  // lock / cube / kayak in JetBrainsMono Nerd Font.
  var phone = "\u{F0855}" // md-cellphone-wireless
  var empty = "\u{F08BF}" // md-signal-cellular-outline
  var bar1 = "\u{F08BC}"  // md-signal-cellular-1
  var bar2 = "\u{F08BD}"  // md-signal-cellular-2
  var bar3 = "\u{F08BE}"  // md-signal-cellular-3

  if (!status || !status.present) return empty
  if (status.state === "unresponsive") return empty
  if (!status.connected) return phone
  var signal = status.signal || 0
  if (signal >= 70) return bar3
  if (signal >= 40) return bar2
  if (signal >= 15) return bar1
  return empty
}

function heroMeta(status, busy, action) {
  if (busy && action === "connect") return "CONNECTING"
  if (busy && action === "disconnect") return "DISCONNECTING"
  if (busy && action === "recover") return "RECOVERING"
  if (busy && action === "share-on") return "SHARING"
  if (busy && action === "share-off") return "STOPPING SHARE"
  if (status && status.state === "unresponsive") return "NOT RESPONDING"
  if (!status || !status.present) return status && status.recoverable ? "NOT RESPONDING" : "NO MODEM"
  if (status.state === "locked") return "SIM PIN REQUIRED"
  if (status.connected) {
    var bits = []
    if (status.operator) bits.push(status.operator.toUpperCase())
    if (status.accessTech) bits.push(status.accessTech.toUpperCase())
    if (status.signal > 0) bits.push(status.signal + "%")
    if (status.share && status.share.active) bits.push("SHARING")
    return bits.length ? bits.join(" · ") : "CONNECTED"
  }
  if (status.state === "enabled") return "READY"
  return String(status.state || "DISCONNECTED").toUpperCase()
}

function detail(status) {
  if (!status) return ""
  if (status.connected && status.ip) return status.ip
  if (status.apn) return status.apn
  return ""
}
