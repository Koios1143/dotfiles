import QtQuick
import Quickshell
import Quickshell.Io

// Active power profile via TLP, cycled on click like waybar's power-profiles-daemon
// module. TLP exposes the same three named profiles (performance/balanced/power-saver)
// through `tlp <profile>`, but setting one needs root — a passwordless sudoers rule
// (see system/etc/sudoers.d/tlp-profile) whitelists exactly those commands. Reading
// the current profile via `tlp-stat -s` needs no root. A light poll picks up changes
// made elsewhere (power-source switch, `tlp start`).
Item {
  id: root
  property string active: ""                     // performance | balanced | power-saver

  // "on AC power" — wired in by the bar from sys.charging (which the state
  // script sets true whenever any power_supply/online == 1). Gates the
  // performance profile: on battery it is neither offered nor selectable.
  property bool onAc: true

  readonly property var allProfiles: ["performance", "balanced", "power-saver"]
  // performance is AC-only; on battery the cycle skips it entirely
  readonly property var profiles: onAc ? allProfiles : ["balanced", "power-saver"]

  function refresh() { getProc.running = true }

  function setProfile(p) {
    if (!p || p === root.active) return
    if (p === "performance" && !root.onAc) return  // no performance on battery
    root.active = p                               // optimistic; poll reconciles with reality
    setProc.command = ["sudo", "-n", "tlp", p]
    setProc.running = true
  }

  // Leaving AC while sitting in performance: drop to balanced so the bar never
  // shows the performance icon on battery (TLP auto-switch does the same, this
  // just makes it instant instead of waiting for the next poll).
  onOnAcChanged: if (!onAc && active === "performance") setProfile("balanced")

  function cycle() {
    if (root.profiles.length === 0) return
    const i = root.profiles.indexOf(root.active)
    setProfile(root.profiles[(i + 1) % root.profiles.length])
  }

  Component.onCompleted: refresh()

  // catch profile changes made outside the bar
  Timer { interval: 5000; running: true; repeat: true; onTriggered: root.refresh() }

  // currently active profile — "TLP profile = <name>/<AC|BAT>" from tlp-stat -s
  Process {
    id: getProc
    command: ["sh", "-c",
      "tlp-stat -s 2>/dev/null | sed -n 's#.*TLP profile[[:space:]]*=[[:space:]]*\\([a-z-]\\+\\)/.*#\\1#p'"]
    stdout: StdioCollector { onStreamFinished: {
      var p = ("" + text).trim()
      if (!root.onAc && p === "performance") p = "balanced"  // never surface performance on battery
      root.active = p
    } }
  }

  Process {
    id: setProc
    onExited: function (code, st) { root.refresh() }
  }
}
