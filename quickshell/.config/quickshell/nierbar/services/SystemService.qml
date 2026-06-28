import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property string scriptPath: Quickshell.shellDir + "/scripts/system_state.sh"

  // Poll intervals (ms). Fast lane = cheap, quickly-changing values; slow lane =
  // expensive probes (nmcli/upower/bluetoothctl/nvidia-smi) that barely change.
  property int fastInterval: 800
  property int slowInterval: 3000

  property string volume: "--"
  property int maxVolume: 150    // hard cap (%); >100% is software gain and can clip/distort
  property bool muted: false
  property string brightness: "--"
  property string cpu: "--"
  property string gpu: "--"
  property string ram: "--"
  property string network: "none"
  property int wifiSignal: 0
  property bool vpn: false
  property string battery: "--"
  property int batterySeconds: -1
  property bool charging: false
  property string bluetooth: "off"
  property string keyboard: "KB"

  function refreshFast() { fastProc.running = true }
  function refreshSlow() { slowProc.running = true }
  function refresh() { refreshFast(); refreshSlow() }

  function parseFast(data) {
    try {
      const o = JSON.parse(data)
      volume = o.volume ?? "--"
      muted = o.muted ?? false
      brightness = o.brightness ?? "--"
      cpu = o.cpu ?? "--"
      ram = o.ram ?? "--"
    } catch (e) {
      console.log("SystemService fast parse failed:", e, data)
    }
  }

  function parseSlow(data) {
    try {
      const o = JSON.parse(data)
      gpu = o.gpu ?? "--"
      network = o.network ?? "none"
      wifiSignal = o.wifiSignal ?? 0
      vpn = o.vpn ?? false
      battery = o.battery ?? "--"
      batterySeconds = o.batterySeconds ?? -1
      charging = o.charging ?? false
      bluetooth = o.bluetooth ?? "off"
      keyboard = o.keyboard ?? "KB"
    } catch (e) {
      console.log("SystemService slow parse failed:", e, data)
    }
  }

  function run(args) { Quickshell.execDetached(args) }
  function openTerminal(cmd) { Quickshell.execDetached(["sh", "-c", "${TERMINAL:-foot} -e " + cmd]) }

  function changeVolume(delta) {
    var cur = parseInt(root.volume)
    if (isNaN(cur)) { refreshFast(); return }
    setVolume(cur + (delta > 0 ? 5 : -5))
  }

  // Set an absolute volume (percent), clamped to [0, maxVolume]. wpctl has no
  // built-in cap, so the clamp lives here.
  function setVolume(percent) {
    var p = Math.max(0, Math.min(root.maxVolume, Math.round(percent)))
    run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (p / 100).toFixed(2)])
    refreshFast()
  }

  function toggleMute() {
    run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    refreshFast()
  }

  function changeBrightness(delta) {
    run(["brightnessctl", "set", delta > 0 ? "5%+" : "5%-"])
    refreshFast()
  }

  // Set an absolute brightness (percent). Clamped to [1,100] so the slider
  // can't black out the screen entirely.
  function setBrightness(percent) {
    var p = Math.max(1, Math.min(100, Math.round(percent)))
    run(["brightnessctl", "set", p + "%"])
    refreshFast()
  }

  Component.onCompleted: refresh()

  Timer {
    interval: root.fastInterval
    running: true
    repeat: true
    onTriggered: root.refreshFast()
  }

  Timer {
    interval: root.slowInterval
    running: true
    repeat: true
    onTriggered: root.refreshSlow()
  }

  Process {
    id: fastProc
    command: [root.scriptPath, "fast"]
    stdout: StdioCollector { onStreamFinished: root.parseFast(text) }
  }

  Process {
    id: slowProc
    command: [root.scriptPath, "slow"]
    stdout: StdioCollector { onStreamFinished: root.parseSlow(text) }
  }
}
