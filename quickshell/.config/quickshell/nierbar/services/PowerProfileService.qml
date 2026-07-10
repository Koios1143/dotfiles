import QtQuick
import Quickshell
import Quickshell.Io

// Active power profile via powerprofilesctl, cycled on click like waybar's
// power-profiles-daemon module. One-shot invocations for get/set; a light poll
// picks up changes made elsewhere (GNOME, auto degrade). `profiles` is the
// available set in canonical fast→slow order so cycling is predictable.
Item {
  id: root
  property string active: ""                     // performance | balanced | power-saver
  property var profiles: ["performance", "balanced", "power-saver"]
  readonly property var order: ["performance", "balanced", "power-saver"]

  function refresh() { getProc.running = true }

  function setProfile(p) {
    if (!p || p === root.active) return
    setProc.command = ["powerprofilesctl", "set", p]
    setProc.running = true
  }

  function cycle() {
    if (root.profiles.length === 0) return
    const i = root.profiles.indexOf(root.active)
    setProfile(root.profiles[(i + 1) % root.profiles.length])
  }

  Component.onCompleted: { listProc.running = true; refresh() }

  // catch profile changes made outside the bar
  Timer { interval: 5000; running: true; repeat: true; onTriggered: root.refresh() }

  // currently active profile
  Process {
    id: getProc
    command: ["powerprofilesctl", "get"]
    stdout: StdioCollector { onStreamFinished: root.active = ("" + text).trim() }
  }

  // available profiles (once) — keep canonical order, drop any not present
  Process {
    id: listProc
    command: ["sh", "-c",
      "powerprofilesctl list 2>/dev/null | grep -oE '(performance|balanced|power-saver):' | tr -d ':'"]
    stdout: StdioCollector {
      onStreamFinished: {
        const found = ("" + text).trim().split(/\s+/).filter(s => s.length > 0)
        const present = root.order.filter(p => found.indexOf(p) >= 0)
        if (present.length > 0) root.profiles = present
      }
    }
  }

  Process {
    id: setProc
    onExited: function (code, st) { root.refresh() }
  }
}
