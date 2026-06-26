import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property string scriptPath: Quickshell.shellDir + "/scripts/system_state.sh"

  property string volume: "--"
  property bool muted: false
  property string brightness: "--"
  property string cpu: "--"
  property string gpu: "--"
  property string ram: "--"
  property string network: "none"
  property string battery: "--"
  property int batterySeconds: -1
  property bool charging: false
  property string bluetooth: "off"
  property string keyboard: "KB"

  function refresh() { proc.exec([scriptPath]) }

  function parse(data) {
    try {
      const obj = JSON.parse(data)
      volume = obj.volume ?? "--"
      muted = obj.muted ?? false
      brightness = obj.brightness ?? "--"
      cpu = obj.cpu ?? "--"
      gpu = obj.gpu ?? "--"
      ram = obj.ram ?? "--"
      network = obj.network ?? "none"
      battery = obj.battery ?? "--"
      batterySeconds = obj.batterySeconds ?? -1
      charging = obj.charging ?? false
      bluetooth = obj.bluetooth ?? "off"
      keyboard = obj.keyboard ?? "KB"
    } catch (e) {
      console.log("SystemService parse failed:", e, data)
    }
  }

  function run(args) { Quickshell.execDetached(args) }
  function openTerminal(cmd) { Quickshell.execDetached(["sh", "-c", "${TERMINAL:-foot} -e " + cmd]) }

  function changeVolume(delta) {
    run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", delta > 0 ? "5%+" : "5%-"])
    refresh()
  }

  function toggleMute() {
    run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    refresh()
  }

  function changeBrightness(delta) {
    run(["brightnessctl", "set", delta > 0 ? "5%+" : "5%-"])
    refresh()
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: proc
    stdout: SplitParser { onRead: data => root.parse(data) }
  }
}
