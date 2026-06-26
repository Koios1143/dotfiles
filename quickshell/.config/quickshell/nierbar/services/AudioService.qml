import QtQuick
import Quickshell
import Quickshell.Io

// Output-device enumeration / switching via pactl. Volume itself stays in
// SystemService (wpctl on @DEFAULT_AUDIO_SINK@), which follows the default sink.
Item {
  id: root
  property var sinks: []          // [{ name, description }]
  property string defaultSink: ""

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

  // Pairs "Name:" with the following "Description:" within each sink block.
  function parseSinks(text) {
    var lines = ("" + text).split("\n")
    var out = []
    var cur = ""
    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].trim()
      if (t.indexOf("Name:") === 0) {
        cur = t.substring(5).trim()
      } else if (t.indexOf("Description:") === 0 && cur.length > 0) {
        out.push({ name: cur, description: t.substring(12).trim() })
        cur = ""
      }
    }
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
