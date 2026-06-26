import QtQuick
import Quickshell
import "../style"

Row {
  id: root
  property var sys
  spacing: Theme.compactGap

  function pct(v) { return v === "--" ? "--" : v + "%" }
  function batteryColor() {
    const n = Number(sys.battery)
    if (isNaN(n)) return Theme.fg
    if (n <= 10) return Theme.red
    if (n <= 25) return Theme.amber
    return Theme.fg
  }
  function batteryBaseIcon() {
    const n = Number(sys.battery)
    if (isNaN(n)) return ""
    if (n <= 10) return ""
    if (n <= 25) return ""
    if (n <= 50) return ""
    if (n <= 75) return ""
    return ""
  }
  function batteryIcon() {
    // Font Awesome battery icons are horizontal. Add a bolt while charging.
    return sys.charging ? batteryBaseIcon() + " " : batteryBaseIcon()
  }
  function batteryTime() {
    if (sys.batterySeconds < 0) return "unknown remaining"
    const h = Math.floor(sys.batterySeconds / 3600)
    const m = Math.floor((sys.batterySeconds % 3600) / 60)
    if (h > 0) return h + "h " + m + "m remaining"
    return m + "m remaining"
  }
  function networkIcon() {
    if (sys.network === "wired") return "󰈀"
    if (sys.network === "wifi") return "󰤨"
    return "󰤭"
  }
  function networkColor() { return sys.network === "none" ? Theme.red : Theme.fg }
  function networkTip() {
    if (sys.network === "wired") return "Wired connected"
    if (sys.network === "wifi") return "WiFi connected"
    return "No network"
  }
  function bluetoothIcon() { return sys.bluetooth === "connected" ? "󰂱" : "󰂯" }
  function bluetoothColor() { return sys.bluetooth === "connected" ? Theme.blue : Theme.fg }
  function bluetoothTip() {
    if (sys.bluetooth === "connected") return "Bluetooth connected"
    if (sys.bluetooth === "on") return "Bluetooth on"
    return "Bluetooth off"
  }

  StatusItem {
    icon: sys.muted ? "󰝟" : ""
    label: root.pct(sys.volume)
    tooltip: sys.muted ? "Muted" : "Volume " + root.pct(sys.volume)
    onWheelUp: () => sys.changeVolume(1)
    onWheelDown: () => sys.changeVolume(-1)
    onMiddleClick: () => sys.toggleMute()
    onLeftClick: () => Quickshell.execDetached(["sh", "-c", "pavucontrol || pwvucontrol || true"])
  }

  Divider {}

  StatusItem {
    icon: "󰃠"
    label: root.pct(sys.brightness)
    tooltip: "Brightness " + root.pct(sys.brightness)
    onWheelUp: () => sys.changeBrightness(1)
    onWheelDown: () => sys.changeBrightness(-1)
  }

  Divider {}

  StatusItem {
    icon: root.networkIcon()
    label: ""
    fg: root.networkColor()
    tooltip: root.networkTip()
    minWidth: 24
    onLeftClick: () => Quickshell.execDetached(["sh", "-c", "nm-connection-editor || nmtui || true"])
  }

  Divider {}

  StatusItem { label: "CPU\n" + root.pct(sys.cpu); minWidth: 42; tooltip: "CPU " + root.pct(sys.cpu); onLeftClick: () => Quickshell.execDetached(["sh", "-c", "missioncenter || resources || btop || true"]) }
  Divider {}
  StatusItem { label: "GPU\n" + root.pct(sys.gpu); minWidth: 42; tooltip: "GPU " + root.pct(sys.gpu); onLeftClick: () => Quickshell.execDetached(["sh", "-c", "missioncenter || resources || btop || true"]) }
  Divider {}
  StatusItem { label: "RAM\n" + root.pct(sys.ram); minWidth: 42; tooltip: "RAM " + root.pct(sys.ram); onLeftClick: () => Quickshell.execDetached(["sh", "-c", "missioncenter || resources || btop || true"]) }
  Divider {}

  StatusItem {
    icon: root.batteryIcon()
    label: root.pct(sys.battery)
    fg: root.batteryColor()
    minWidth: sys.charging ? 64 : 52
    tooltip: root.pct(sys.battery) + " · " + root.batteryTime()
    onLeftClick: () => Quickshell.execDetached(["sh", "-c", "gnome-control-center power || powerprofilesctl get || true"])
  }

  Divider {}

  StatusItem {
    icon: root.bluetoothIcon()
    label: ""
    fg: root.bluetoothColor()
    tooltip: root.bluetoothTip()
    compact: true
    minWidth: 22
    onLeftClick: () => Quickshell.execDetached(["sh", "-c", "blueman-manager || blueberry || true"])
  }

  StatusItem {
    icon: "󰌌"
    label: ""
    tooltip: sys.keyboard
    compact: true
    minWidth: 22
  }
}
