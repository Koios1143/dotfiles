import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Item {
  id: root
  property string scriptPath: Quickshell.shellDir + "/scripts/system_state.sh"

  // Poll intervals (ms). The fast lane now only carries cpu/ram — volume and
  // brightness are event-driven (see below) so they update the instant they
  // change instead of waiting for the next poll.
  //   volume/mute -> Pipewire service (reactive, zero latency)
  //   brightness  -> `udevadm monitor` on the backlight subsystem, which fires
  //                  a `change` event on every brightnessctl write (keyboard or
  //                  slider), triggering a cheap `brightnessctl -m` re-read.
  property int fastInterval: 800
  property int slowInterval: 3000

  // --- Volume / mute: bound live to the default PipeWire sink ---
  readonly property var _sink: Pipewire.defaultAudioSink
  property int maxVolume: 150    // hard cap (%); >100% is software gain and can clip/distort
  property string volume: (_sink && _sink.audio) ? String(Math.round(_sink.audio.volume * 100)) : "--"
  property bool muted: (_sink && _sink.audio) ? _sink.audio.muted : false

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
  function refreshBrightness() { brightProc.running = true }
  function refresh() { refreshFast(); refreshSlow(); refreshBrightness() }

  function parseFast(data) {
    try {
      const o = JSON.parse(data)
      cpu = o.cpu ?? "--"
      ram = o.ram ?? "--"
    } catch (e) {
      console.log("SystemService fast parse failed:", e, data)
    }
  }

  // `brightnessctl -m` -> "device,class,current,percent%,max". Linear scale
  // everywhere (read + keyboard/scroll/slider writes) so the % moves in clean
  // ±5% steps (0/5/…/100) and 0% is a true blackout. Read and write must share
  // the same scale or the displayed number won't match what a step actually does.
  function parseBrightness(data) {
    var f = data.trim().split(",")
    if (f.length >= 4) {
      var p = f[3].replace("%", "")
      if (p !== "") brightness = p
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
    if (isNaN(cur)) return
    setVolume(cur + (delta > 0 ? 5 : -5))
  }

  // Set an absolute volume (percent), clamped to [0, maxVolume]. PipeWire has
  // no built-in cap, so the clamp lives here. Writing straight to the sink is
  // reflected back through the live binding instantly.
  function setVolume(percent) {
    if (!_sink || !_sink.audio) return
    var p = Math.max(0, Math.min(root.maxVolume, Math.round(percent)))
    _sink.audio.volume = p / 100
  }

  function toggleMute() {
    if (_sink && _sink.audio) _sink.audio.muted = !_sink.audio.muted
  }

  // brightnessctl writes trigger a backlight `change` udev event, which drives
  // the re-read below — no explicit refresh needed here.
  // Linear, no floor (can reach raw 0), matching the XF86 keyboard binds so
  // stepping from either source lands on the same values.
  function changeBrightness(delta) {
    run(["brightnessctl", "set", delta > 0 ? "5%+" : "5%-"])
  }

  // Set an absolute brightness (percent), linear. 0 = raw 0 = fully dark; no
  // safety floor.
  function setBrightness(percent) {
    var p = Math.max(0, Math.min(100, Math.round(percent)))
    run(["brightnessctl", "set", p + "%"])
  }

  Component.onCompleted: refresh()

  // Keep the default sink's properties live so volume/muted stay current.
  PwObjectTracker { objects: root._sink ? [root._sink] : [] }

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

  // Brightness: one cheap read, driven by backlight udev events instead of a
  // timer so the bar reflects keyboard changes with sub-frame latency.
  Process {
    id: brightProc
    command: ["brightnessctl", "-m"]
    stdout: StdioCollector { onStreamFinished: root.parseBrightness(text) }
  }

  // Coalesces the burst of events that key-repeat produces into one final read.
  Timer {
    id: brightDebounce
    interval: 40
    repeat: false
    onTriggered: root.refreshBrightness()
  }

  Process {
    id: brightMon
    command: ["udevadm", "monitor", "--udev", "--subsystem-match=backlight"]
    running: true
    stdout: SplitParser { onRead: brightDebounce.restart() }
  }

  Process {
    id: slowProc
    command: [root.scriptPath, "slow"]
    stdout: StdioCollector { onStreamFinished: root.parseSlow(text) }
  }
}
