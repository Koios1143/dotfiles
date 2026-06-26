import QtQuick
import Quickshell
import Quickshell.Io

// NetworkManager glue for the bar's network popup. All interaction goes through
// `nmcli`, matching the polling approach already used in system_state.sh.
Item {
  id: root

  property bool wifiEnabled: true
  property var networks: []        // [{ ssid, signal, security, inUse }]
  property var savedConnections: []  // names of stored wifi profiles
  property string activeSsid: ""
  property bool busy: false
  property string status: ""

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
}
