import QtQuick
import Quickshell
import Quickshell.Io

// NetworkManager glue for the bar's network popup. All interaction goes through
// `nmcli`, matching the polling approach already used in system_state.sh.
Item {
  id: root

  property string scriptPath: Quickshell.shellDir + "/scripts/hotspot.sh"

  property bool wifiEnabled: true
  property var networks: []        // [{ ssid, signal, security, inUse }]
  property var savedConnections: []  // names of stored wifi profiles
  property var ethernets: []       // [{ name, uuid, type, active }]
  property var vpns: []            // [{ name, uuid, type, active }]  (vpn + wireguard)
  property string activeSsid: ""
  property bool busy: false
  property string status: ""

  // set true while a popup is showing the list so it keeps re-scanning
  property bool polling: false

  // ---- hotspot (AP mode sharing the wired/other connection) ----
  property bool hotspotActive: false
  property string hotspotDevice: ""       // iface the AP runs on (for client lookup)
  property string hotspotSsid: "nierbar"  // last-used / default config, prefilled in UI
  property string hotspotPassword: ""
  property string hotspotBand: "bg"        // "bg" = 2.4GHz, "a" = 5GHz
  property var hotspotClients: []          // display names of associated stations
  property string hotspotQrPath: ""        // file:// url of the last rendered QR
  property int _qrGen: 0                    // bumps the url so the Image reloads

  // raised when a passwordless connect fails because a secret is required
  signal needsPassword(string ssid)

  // last connect attempt, so onExited knows whether to fall back to a prompt
  property string _lastSsid: ""
  property bool _lastHadPassword: false

  // a stored profile means NetworkManager already has the secret
  function isSaved(ssid) { return root.savedConnections.indexOf(ssid) !== -1 }

  function refresh() {
    radioProc.running = true
    listProc.running = true
    savedProc.running = true
    profProc.running = true
    hsStatusProc.running = true
  }

  // ---- hotspot control ----

  function refreshHotspot() { hsStatusProc.running = true }

  function parseHotspot(data) {
    try {
      var o = JSON.parse(data)
      root.hotspotActive = o.active ?? false
      root.hotspotDevice = o.device ?? ""
      if (o.ssid && o.ssid.length) root.hotspotSsid = o.ssid
      root.hotspotPassword = o.password ?? ""
      if (o.band && o.band.length) root.hotspotBand = o.band
      if (!root.hotspotActive) root.hotspotClients = []
    } catch (e) {
      console.log("NetworkService parseHotspot failed:", e, data)
    }
  }

  // starting the AP takes the wifi device out of client mode, so the normal
  // wifi connection drops — that is the intended "turn wifi off" behaviour.
  function startHotspot(ssid, password, band) {
    root.busy = true
    root.status = "Starting hotspot…"
    hsStartProc.command = [root.scriptPath, "start",
                           ssid || "nierbar", password || "", band || "bg"]
    hsStartProc.running = true
  }

  function stopHotspot() {
    root.busy = true
    root.status = "Stopping hotspot…"
    hsStopProc.running = true
  }

  function refreshClients() {
    if (!root.hotspotActive) { root.hotspotClients = []; return }
    hsClientsProc.command = [root.scriptPath, "clients", root.hotspotDevice]
    hsClientsProc.running = true
  }

  function makeQr() {
    hsQrProc.command = [root.scriptPath, "qr", root.hotspotSsid, root.hotspotPassword]
    hsQrProc.running = true
  }

  // bring a stored profile up / down by uuid. Works for any type (ethernet,
  // vpn, wireguard); the secret stays in NetworkManager so nothing is forgotten.
  function activate(name, uuid) {
    root.busy = true
    root.status = "Activating " + name + "…"
    profUpProc.command = ["nmcli", "connection", "up", "uuid", uuid]
    profUpProc.running = true
  }

  function deactivate(name, uuid) {
    root.busy = true
    root.status = "Deactivating " + name + "…"
    profDownProc.command = ["nmcli", "connection", "down", "uuid", uuid]
    profDownProc.running = true
  }

  // parse `connection show`: NAME may contain ':', so it goes last and is
  // rejoined; uuid/type/active are colon-free. Splits profiles by type.
  function parseProfiles(text) {
    var lines = ("" + text).trim().split("\n").filter(function (l) { return l.length > 0 })
    var eth = []
    var vpn = []
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split(":")
      if (parts.length < 4) continue
      var uuid = parts[0]
      var type = parts[1]
      var active = parts[2] === "yes"
      var name = parts.slice(3).join(":")
      var entry = ({ name: name, uuid: uuid, type: type, active: active })
      if (type === "802-3-ethernet") eth.push(entry)
      else if (type === "vpn" || type === "wireguard") vpn.push(entry)
    }
    function byActiveThenName(a, b) { return (b.active - a.active) || a.name.localeCompare(b.name) }
    eth.sort(byActiveThenName)
    vpn.sort(byActiveThenName)
    root.ethernets = eth
    root.vpns = vpn
  }

  function rescan() {
    root.busy = true
    root.status = "Scanning…"
    rescanProc.running = true
  }

  function connectTo(ssid, password) {
    root.busy = true
    root.status = "Connecting to " + ssid + "…"
    root._lastSsid = ssid
    root._lastHadPassword = (password && password.length > 0)
    var args = ["nmcli", "device", "wifi", "connect", ssid]
    if (root._lastHadPassword)
      args.push("password", password)
    connectProc.command = args
    connectProc.running = true
  }

  function disconnectFrom(ssid) {
    root.busy = true
    root.status = "Disconnecting…"
    downProc.command = ["nmcli", "connection", "down", ssid]
    downProc.running = true
  }

  function toggleWifi() {
    toggleProc.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "off" : "on"]
    toggleProc.running = true
  }

  // nmcli -t escapes ':' inside fields as '\:'. We put SSID last and rejoin the
  // remainder so embedded colons don't shift the other columns.
  function parseList(text) {
    var lines = ("" + text).trim().split("\n").filter(function (l) { return l.length > 0 })
    var seen = ({})
    var out = []
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split(":")
      if (parts.length < 4) continue
      var inUse = parts[0] === "*"
      var signal = parseInt(parts[1]) || 0
      var security = parts[2] || ""
      var ssid = parts.slice(3).join(":")
      if (ssid.length === 0) continue
      if (seen[ssid] !== undefined) {            // dedupe BSSIDs, keep strongest
        if (signal > seen[ssid].signal) seen[ssid].signal = signal
        if (inUse) seen[ssid].inUse = true
        continue
      }
      var entry = ({ ssid: ssid, signal: signal, security: security, inUse: inUse })
      seen[ssid] = entry
      out.push(entry)
    }
    out.sort(function (a, b) { return (b.inUse - a.inUse) || (b.signal - a.signal) })
    root.networks = out
    var act = ""
    for (var j = 0; j < out.length; j++) {
      if (out[j].inUse) { act = out[j].ssid; break }
    }
    root.activeSsid = act
  }

  Component.onCompleted: refresh()

  // While a popup is open, keep the scan list fresh. NetworkManager also does
  // its own background scans, so a periodic rescan just nudges it and re-lists.
  // We drive rescanProc directly (not rescan()) to avoid the busy/status flicker
  // that the manual rescan button intentionally shows.
  Timer {
    interval: 12000
    repeat: true
    running: root.polling && root.wifiEnabled && !root.hotspotActive
    onTriggered: rescanProc.running = true
  }

  Process {
    id: radioProc
    command: ["nmcli", "radio", "wifi"]
    stdout: StdioCollector {
      onStreamFinished: root.wifiEnabled = (("" + text).trim() === "enabled")
    }
  }

  Process {
    id: listProc
    command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list"]
    stdout: StdioCollector {
      onStreamFinished: root.parseList(text)
    }
  }

  Process {
    id: rescanProc
    command: ["nmcli", "device", "wifi", "rescan"]
    // rescan errors out if triggered too often; we ignore the code and re-list.
    onExited: function (code, st) { root.busy = false; root.status = ""; root.refresh() }
  }

  Process {
    id: savedProc
    command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
    stdout: StdioCollector {
      onStreamFinished: {
        // TYPE is the last field; NAME may contain ':' so rejoin the rest.
        var lines = ("" + text).trim().split("\n").filter(function (l) { return l.length > 0 })
        var names = []
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split(":")
          var type = parts[parts.length - 1]
          if (type !== "802-11-wireless") continue
          names.push(parts.slice(0, -1).join(":"))
        }
        root.savedConnections = names
      }
    }
  }

  Process {
    id: connectProc
    stdout: StdioCollector { id: connOut }
    stderr: StdioCollector { id: connErr }
    onExited: function (code, st) {
      root.busy = false
      if (code === 0) {
        root.status = "Connected"
      } else {
        var err = ("" + connErr.text).trim()
        // a passwordless attempt that needs a secret → ask for the password
        if (!root._lastHadPassword && /secret|password|key|802[._-]?1x/i.test(err)) {
          root.status = "Password required"
          root.needsPassword(root._lastSsid)
        } else {
          root.status = err || "Connection failed"
        }
      }
      root.refresh()
    }
  }

  Process {
    id: downProc
    onExited: function (code, st) { root.busy = false; root.status = ""; root.refresh() }
  }

  Process {
    id: toggleProc
    onExited: function (code, st) { root.refresh() }
  }

  Process {
    id: profProc
    command: ["nmcli", "-t", "-f", "UUID,TYPE,ACTIVE,NAME", "connection", "show"]
    stdout: StdioCollector {
      onStreamFinished: root.parseProfiles(text)
    }
  }

  Process {
    id: profUpProc
    stderr: StdioCollector { id: profUpErr }
    onExited: function (code, st) {
      root.busy = false
      // vpns that need interactive secrets (OTP, credentials) fail here; surface
      // the error rather than silently doing nothing.
      root.status = (code === 0) ? "" : (("" + profUpErr.text).trim() || "Activation failed")
      root.refresh()
    }
  }

  Process {
    id: profDownProc
    onExited: function (code, st) { root.busy = false; root.status = ""; root.refresh() }
  }

  Process {
    id: hsStatusProc
    command: [root.scriptPath, "status"]
    stdout: StdioCollector { onStreamFinished: root.parseHotspot(text) }
  }

  Process {
    id: hsStartProc
    stderr: StdioCollector { id: hsStartErr }
    onExited: function (code, st) {
      root.busy = false
      root.status = (code === 0) ? "Hotspot on"
                                 : (("" + hsStartErr.text).trim() || "Hotspot failed")
      root.refresh()
    }
  }

  Process {
    id: hsStopProc
    command: [root.scriptPath, "stop"]
    onExited: function (code, st) { root.busy = false; root.status = ""; root.refresh() }
  }

  Process {
    id: hsClientsProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.hotspotClients = JSON.parse(text) }
        catch (e) { root.hotspotClients = [] }
      }
    }
  }

  Process {
    id: hsQrProc
    stdout: StdioCollector {
      onStreamFinished: {
        var p = ("" + text).trim()
        if (p.length) { root._qrGen++; root.hotspotQrPath = "file://" + p + "?g=" + root._qrGen }
      }
    }
  }
}
