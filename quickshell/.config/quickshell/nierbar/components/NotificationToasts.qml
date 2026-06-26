import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../style"

// Transient pop-up toasts for incoming notifications, stacked at the top-right
// just under the bar. Auto-expire after a few seconds; click to dismiss.
PanelWindow {
  id: toasts
  property var notif

  anchors { top: true; right: true }
  implicitWidth: 340
  implicitHeight: Math.max(1, col.implicitHeight + Theme.barHeight + 12)
  color: "transparent"
  visible: toasts.active.length > 0
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "nierbar-toasts"
  exclusionMode: ExclusionMode.Ignore

  // active toast list (JS array of Notification objects); reassign to refresh
  property var active: []

  function show(n) { toasts.active = toasts.active.concat([n]) }
  function remove(n) { toasts.active = toasts.active.filter(x => x !== n) }

  Connections {
    target: toasts.notif
    function onArrived(n) { toasts.show(n) }
  }

  Column {
    id: col
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Theme.barHeight + 6
    anchors.rightMargin: Theme.sideMargin
    spacing: 6

    Repeater {
      model: toasts.active
      delegate: Rectangle {
        id: toast
        required property var modelData
        width: 320
        height: tin.implicitHeight + 14
        color: Theme.bg
        radius: Theme.itemRadius
        border.color: modelData.urgency === NotificationUrgency.Critical ? Theme.red : Theme.line
        border.width: 1

        // critical toasts stay until dismissed; others auto-expire
        Timer {
          interval: 5000
          running: toast.modelData.urgency !== NotificationUrgency.Critical
          onTriggered: toasts.remove(toast.modelData)
        }

        Column {
          id: tin
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: 10
          anchors.rightMargin: 24
          anchors.topMargin: 7
          spacing: 1

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: toast.modelData.appName || "通知"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tinyText
            font.letterSpacing: 1
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            visible: toast.modelData.summary && toast.modelData.summary.length > 0
            text: toast.modelData.summary
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallText
          }
          Text {
            width: parent.width
            visible: toast.modelData.body && toast.modelData.body.length > 0
            text: toast.modelData.body
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tinyText
          }
        }

        Text {
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.topMargin: 6
          anchors.rightMargin: 8
          text: "✕"
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.tinyText
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { toast.modelData.dismiss(); toasts.remove(toast.modelData) }
        }
      }
    }
  }
}
