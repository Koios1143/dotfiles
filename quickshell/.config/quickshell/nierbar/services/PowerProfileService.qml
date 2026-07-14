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
  readonly property var profiles: ["performance", "balanced", "power-saver"]

  function refresh() { getProc.running = true }

  function setProfile(p) {
    if (!p || p === root.active) return
    root.active = p                               // optimistic; poll reconciles with reality
    setProc.command = ["sudo", "-n", "tlp", p]
    setProc.running = true
  }

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
    stdout: StdioCollector { onStreamFinished: root.active = ("" + text).trim() }
  }

  Process {
    id: setProc
    onExited: function (code, st) { root.refresh() }
  }
}
