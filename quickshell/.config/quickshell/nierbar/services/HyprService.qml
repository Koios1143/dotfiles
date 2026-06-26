import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property string title: "Desktop"
  property string windowClass: ""
  property string scriptPath: Quickshell.shellDir + "/scripts/hypr_state.sh"

  function refresh() {
    proc.exec([scriptPath])
  }

  function parse(data) {
    try {
      const obj = JSON.parse(data)
      title = obj.title && obj.title.length ? obj.title : "Desktop"
      windowClass = obj.class || ""
    } catch (e) {
      console.log("HyprService parse failed:", e, data)
    }
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 700
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: proc
    stdout: SplitParser { onRead: data => root.parse(data) }
  }
}
