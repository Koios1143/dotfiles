import QtQuick
import Quickshell
import "../style"
import "../services"

Row {
  id: root
  property var sys
  property var onNetworkClick: null
  property var onVolumeClick: null
  property var onBrightnessClick: null
  property var onBluetoothClick: null
  spacing: Theme.compactGap

  // non-visual: Row skips invisible children, so it stays out of the layout.
  // sys.charging is true whenever on AC (the state script keys it off /online),
  // so it doubles as the "on AC" gate that hides performance on battery.
  PowerProfileService { id: power; visible: false; onAc: root.sys ? !!root.sys.charging : true }

  function pct(v) { return v === "--" ? "--" : v + "%" }
  function volumeIcon() {
    if (sys.muted) return "󰝟"
    const v = Number(sys.volume)
    if (isNaN(v) || v <= 0) return "󰕿"
    if (v <= 50) return "󰖀"
    return "󰕾"
  }
  function brightnessIcon() {
    const v = Number(sys.brightness)
    if (isNaN(v)) return String.fromCodePoint(0xF00E0)   // full sun
    if (v <= 40) return String.fromCodePoint(0xF00DE)    // small sun (dim)
    return String.fromCodePoint(0xF00E0)                 // full sun
  }
  function batteryColor() {
    if (sys.charging) return Theme.green
    const n = Number(sys.battery)
    if (isNaN(n)) return Theme.fg
    if (n <= 10) return Theme.red
    if (n <= 25) return Theme.amber
    return Theme.fg
  }
  function batteryIcon() {
    const n = Number(sys.battery)
    // Font Awesome horizontal battery (matches the mockup), 5 fill levels.
    // Charging is shown by the green colour, not a bolt.
    let base
    if (isNaN(n) || n <= 10) base = 0xF244       // empty
    else if (n <= 35) base = 0xF243              // quarter
    else if (n <= 60) base = 0xF242              // half
    else if (n <= 85) base = 0xF241              // three-quarters
    else base = 0xF240                           // full
    return String.fromCodePoint(base)
  }
  function batteryTime() {
    if (sys.batterySeconds < 0) return "unknown remaining"
    const h = Math.floor(sys.batterySeconds / 3600)
    const m = Math.floor((sys.batterySeconds % 3600) / 60)
    if (h > 0) return h + "h " + m + "m remaining"
    return m + "m remaining"
  }
  function networkIcon() {
    if (sys.vpn) return "󰦝"                  // shield while a VPN tunnel is up
    if (sys.network === "wired") return "󰈀"
    if (sys.network === "wifi") {
      const s = Number(sys.wifiSignal)
      if (s >= 75) return "󰤨"
      if (s >= 55) return "󰤥"
      if (s >= 35) return "󰤢"
      if (s > 0)   return "󰤟"
      return "󰤯"
    }
    return "󰤭"
  }
  function networkColor() {
    if (sys.vpn) return Theme.green          // green = secured tunnel
    return sys.network === "none" ? Theme.red : Theme.fg
  }
  function networkTip() {
    const base = sys.network === "wired" ? "Wired connected"
               : sys.network === "wifi" ? ("WiFi connected · " + sys.wifiSignal + "%")
               : "No network"
    return sys.vpn ? ("VPN active · " + base) : base
  }
  function powerIcon() {
    switch (power.active) {
      case "performance": return String.fromCodePoint(0xF04C5)  // speedometer
      case "power-saver": return String.fromCodePoint(0xF032A)  // leaf
      default:            return String.fromCodePoint(0xF05D1)  // scale-balance (balanced)
    }
  }
  function powerColor() {
    switch (power.active) {
      case "performance": return Theme.amber
      case "power-saver": return Theme.green
      default:            return Theme.fg
    }
  }
  function powerTip() {
    const n = power.active === "performance" ? "Performance"
            : power.active === "power-saver" ? "Power Saver"
            : power.active === "balanced" ? "Balanced" : "…"
    return "Power profile: " + n + " · click to cycle"
  }
  function bluetoothIcon() { return sys.bluetooth === "connected" ? "󰂱" : "󰂯" }
  function bluetoothColor() { return sys.bluetooth === "connected" ? Theme.blue : Theme.fg }
  function bluetoothTip() {
    if (sys.bluetooth === "connected") return "Bluetooth connected"
    if (sys.bluetooth === "on") return "Bluetooth on"
    return "Bluetooth off"
  }

  StatusItem {
    id: volItem
    icon: root.volumeIcon()
    label: root.pct(sys.volume)
    tooltip: sys.muted ? "Muted" : "Volume " + root.pct(sys.volume)
    onWheelUp: () => sys.changeVolume(1)
    onWheelDown: () => sys.changeVolume(-1)
    onMiddleClick: () => sys.toggleMute()
    // pass the icon's scene x + width so the popup can sit directly below it
    onLeftClick: () => { if (root.onVolumeClick) root.onVolumeClick(volItem.mapToItem(null, 0, 0).x, volItem.width) }
  }

  Divider {}

  StatusItem {
    id: brItem
    icon: root.brightnessIcon()
    label: root.pct(sys.brightness)
    tooltip: "Brightness " + root.pct(sys.brightness)
    onWheelUp: () => sys.changeBrightness(1)
    onWheelDown: () => sys.changeBrightness(-1)
    onLeftClick: () => { if (root.onBrightnessClick) root.onBrightnessClick(brItem.mapToItem(null, 0, 0).x, brItem.width) }
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
    minWidth: 52
    tooltip: root.pct(sys.battery) + " · " + root.batteryTime()
    onLeftClick: () => Quickshell.execDetached(["sh", "-c", "gnome-control-center power || powerprofilesctl get || true"])
  }

  Divider {}

  StatusItem {
    id: powerItem
    icon: root.powerIcon()
    label: ""
    fg: root.powerColor()
    tooltip: root.powerTip()
    compact: true
    minWidth: 24
    onLeftClick: () => power.cycle()
  }

  Divider {}

  StatusItem {
    id: netItem
    icon: root.networkIcon()
    label: ""
    fg: root.networkColor()
    tooltip: root.networkTip()
    minWidth: 24
    onLeftClick: () => { if (root.onNetworkClick) root.onNetworkClick(netItem.mapToItem(null, 0, 0).x, netItem.width) }
  }

  Divider {}

  StatusItem {
    id: btItem
    icon: root.bluetoothIcon()
    label: ""
    fg: root.bluetoothColor()
    tooltip: root.bluetoothTip()
    compact: true
    minWidth: 22
    onLeftClick: () => { if (root.onBluetoothClick) root.onBluetoothClick(btItem.mapToItem(null, 0, 0).x, btItem.width) }
  }

  // system tray sits at the far right; the divider hides with it when empty
  Divider { visible: tray.visible }

  SystemTray {
    id: tray
    anchors.verticalCenter: parent.verticalCenter
  }
}
