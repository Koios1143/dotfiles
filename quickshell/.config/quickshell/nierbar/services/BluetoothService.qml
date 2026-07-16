import QtQuick
import Quickshell
import Quickshell.Io

// Bluetooth control via bluetoothctl. State (power + device list) comes from
// scripts/bluetooth.sh; actions are one-shot bluetoothctl invocations.
Item {
  id: root
  property string scriptPath: Quickshell.shellDir + "/scripts/bluetooth.sh"

  property bool powered: false
  property bool scanning: false
  property var devices: []        // [{ mac, name, connected }]
  property string status: ""

  function refresh() { stateProc.running = true }

  function togglePower() {
    powerProc.command = ["bluetoothctl", "power", root.powered ? "off" : "on"]
    powerProc.running = true
  }

  function connectDevice(mac) {
    root.status = "Connecting…"
    connProc.command = ["bluetoothctl", "connect", mac]
    connProc.running = true
  }

  function disconnectDevice(mac) {
    root.status = "Disconnecting…"
    disProc.command = ["bluetoothctl", "disconnect", mac]
    disProc.running = true
  }

  function startScan() {
    if (root.scanning) return
    root.scanning = true
    scanProc.running = true        // persistent: scans until stopped
  }

  function stopScan() {
    root.scanning = false
    scanProc.running = false       // killing the process stops the scan
  }

  function parse(data) {
    try {
      const o = JSON.parse(data)
      root.powered = o.powered ?? false
      root.devices = o.devices ?? []
    } catch (e) {
      console.log("BluetoothService parse failed:", e, data)
    }
  }

  Component.onCompleted: refresh()

  // while scanning, keep pulling in newly-discovered devices
  Timer {
    interval: 2500
    running: root.scanning
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: [root.scriptPath]
    stdout: StdioCollector { onStreamFinished: root.parse(text) }
  }

  Process {
    id: powerProc
    onExited: function (code, st) { root.refresh() }
  }

  Process {
    id: connProc
    stderr: StdioCollector { id: connErr }
    onExited: function (code, st) {
      root.status = code === 0 ? "Connected" : (("" + connErr.text).trim() || "Connection failed")
      root.refresh()
    }
  }

  Process {
    id: disProc
    onExited: function (code, st) { root.status = ""; root.refresh() }
  }

  // `bluetoothctl scan on` given as args is one-shot: it enables discovery then
  // exits, and BlueZ stops the scan the moment that D-Bus client disconnects —
  // so nothing new is ever found. `--timeout` instead blocks for the duration,
  // keeping the client (and discovery) alive; killing the process (stopScan)
  // drops the client and cleanly ends discovery. 3600s comfortably outlasts any
  // popup session.
  Process {
    id: scanProc
    command: ["bluetoothctl", "--timeout", "3600", "scan", "on"]
    // if discovery ends on its own (timeout reached), reflect it in the UI
    onExited: function (code, st) { root.scanning = false }
  }
}
