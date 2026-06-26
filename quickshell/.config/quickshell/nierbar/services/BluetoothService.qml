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

  Process {
    id: scanProc
    command: ["bluetoothctl", "scan", "on"]
  }
}
