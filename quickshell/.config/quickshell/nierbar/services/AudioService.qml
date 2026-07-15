import QtQuick
import Quickshell
import Quickshell.Io

// Output-device enumeration / switching via pactl. Volume itself stays in
// SystemService (wpctl on @DEFAULT_AUDIO_SINK@), which follows the default sink.
Item {
  id: root
  property var sinks: []          // [{ name, description, port, avail }]  avail: "yes"|"no"|"unknown"
  property string defaultSink: ""

  // Usable outputs only: drops HDMI/DP ports with no cable ("not available").
  // Analog ports report "unknown" (driver can't detect jacks) and stay visible.
  property var availableSinks: sinks.filter(function (s) { return s.avail !== "no" })

  function refresh() {
    defaultProc.running = true
    listProc.running = true
  }

  function setDefaultSink(name) {
    // set the default sink, then move existing streams over to it
    switchProc.command = ["sh", "-c",
      'pactl set-default-sink "$1"; for i in $(pactl list short sink-inputs 2>/dev/null | cut -f1); do pactl move-sink-input "$i" "$1" 2>/dev/null; done',
      "_", name]
    switchProc.running = true
  }

  // Walks each sink block, collecting Name / Description plus the port's short
  // code (HDMI1/HDMI2/HDMI3/Speaker) and its availability. Each sink here maps
  // to exactly one port (UCM splits profiles into separate sinks), so the sole
  // "[Out] X: ... (type: ...)" line in the Ports section describes that sink.
  function parseSinks(text) {
    var lines = ("" + text).split("\n")
    var out = []
    var cur = null
    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].trim()
      if (t.indexOf("Name:") === 0) {
        if (cur && cur.name.length > 0) out.push(cur)
        cur = { name: t.substring(5).trim(), description: "", port: "", avail: "unknown" }
      } else if (cur) {
        if (t.indexOf("Description:") === 0) {
          cur.description = t.substring(12).trim()
        } else if (t.indexOf("[Out]") === 0 && t.indexOf("(type:") >= 0) {
          var m = t.match(/\[Out\]\s+([^:]+):/)
          if (m) cur.port = m[1].trim()
          // "not available" contains "available", so test it first.
          if (t.indexOf("not available") >= 0) cur.avail = "no"
          else if (t.indexOf("availability unknown") >= 0) cur.avail = "unknown"
          else if (t.indexOf("available") >= 0) cur.avail = "yes"
        }
      }
    }
    if (cur && cur.name.length > 0) out.push(cur)
    root.sinks = out
  }

  Component.onCompleted: refresh()

  Process {
    id: defaultProc
    command: ["pactl", "get-default-sink"]
    stdout: StdioCollector { onStreamFinished: root.defaultSink = ("" + text).trim() }
  }

  Process {
    id: listProc
    command: ["pactl", "list", "sinks"]
    stdout: StdioCollector { onStreamFinished: root.parseSinks(text) }
  }

  Process {
    id: switchProc
    onExited: function (code, st) { root.refresh() }
  }
}
