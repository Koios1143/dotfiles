import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../style"

// Drop-down opened below the centre clock: live time, a week-scrollable
// calendar (each scroll notch moves one week), and a notifications section.
PanelWindow {
  id: pop
  visible: false

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "nierbar-calendar"
  anchors { top: true; left: true; right: true; bottom: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  property real anchorX: 0
  property real anchorWidth: 0
  property var notif        // shared NotificationService

  property var now: new Date()
  property var today: new Date()
  property var viewStart: pop.weekStart(pop.addDays(new Date(), -14))   // 2 weeks of past context

  // ---- date helpers ----
  function addDays(d, n) {
    const x = new Date(d.getFullYear(), d.getMonth(), d.getDate())
    x.setDate(x.getDate() + n)
    return x
  }
  function weekStart(d) {            // back to Sunday
    const x = new Date(d.getFullYear(), d.getMonth(), d.getDate())
    x.setDate(x.getDate() - x.getDay())
    return x
  }
  function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
  }
  function labelDate() { return pop.addDays(pop.viewStart, 21) }   // middle of the 6-week grid

  function resetToToday() {
    pop.today = new Date()
    pop.viewStart = pop.weekStart(pop.addDays(pop.today, -14))
  }

  function open() { pop.visible = true; pop.now = new Date(); pop.resetToToday() }
  function close() { pop.visible = false }
  function openAt(x, w) { pop.anchorX = x; pop.anchorWidth = w; pop.open() }
  function toggleAt(x, w) { pop.visible ? pop.close() : pop.openAt(x, w) }

  Timer {
    interval: 1000
    running: pop.visible
    repeat: true
    onTriggered: pop.now = new Date()
  }


  MouseArea {
    anchors.fill: parent
    onClicked: pop.close()
  }

  Rectangle {
    id: card
    anchors.top: parent.top
    anchors.topMargin: Theme.barHeight + 6
    width: 300
    x: Math.max(Theme.sideMargin,
         Math.min(parent.width - width - Theme.sideMargin,
                  pop.anchorX + pop.anchorWidth / 2 - width / 2))
    implicitHeight: layout.implicitHeight + 24
    height: implicitHeight
    color: Theme.bg
    border.color: Theme.line
    border.width: 1
    radius: Theme.itemRadius

    MouseArea { anchors.fill: parent }   // swallow clicks

    Column {
      id: layout
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: 12
      spacing: 10

      // ---- live time / date ----
      Column {
        width: parent.width
        spacing: -1
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Qt.formatDateTime(pop.now, "HH:mm:ss")
          color: Theme.fg
          font.family: Theme.fontFamily
          font.pixelSize: Theme.timeText
          font.letterSpacing: 2
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Qt.formatDateTime(pop.now, "yyyy / MM / dd  ddd").toUpperCase()
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.tinyText
          font.letterSpacing: 1
        }
      }

      Rectangle { width: parent.width; height: 1; color: Theme.dim }

      // ---- calendar nav ----
      Item {
        width: parent.width
        height: 20

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "‹"
          color: Theme.fg
          font.family: Theme.fontFamily
          font.pixelSize: Theme.normalText
          MouseArea {
            anchors.fill: parent; anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: pop.viewStart = pop.addDays(pop.viewStart, -7)
          }
        }

        Text {
          anchors.centerIn: parent
          text: Qt.formatDateTime(pop.labelDate(), "yyyy 年 M 月")
          color: Theme.fg
          font.family: Theme.fontFamily
          font.pixelSize: Theme.normalText
          font.letterSpacing: 1
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 12

          Text {
            text: "今日"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tinyText
            anchors.verticalCenter: parent.verticalCenter
            MouseArea {
              anchors.fill: parent; anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: pop.resetToToday()
            }
          }
          Text {
            text: "›"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.normalText
            anchors.verticalCenter: parent.verticalCenter
            MouseArea {
              anchors.fill: parent; anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: pop.viewStart = pop.addDays(pop.viewStart, 7)
            }
          }
        }
      }

      // ---- calendar grid (scroll = move one week) ----
      MouseArea {
        width: parent.width
        height: grid.implicitHeight
        property real wheelAccum: 0
        onWheel: w => {
          wheelAccum += Wheel.norm(w)
          // physical up -> earlier weeks, down -> later weeks
          while (wheelAccum >= Wheel.step) { wheelAccum -= Wheel.step; pop.viewStart = pop.addDays(pop.viewStart, -7) }
          while (wheelAccum <= -Wheel.step) { wheelAccum += Wheel.step; pop.viewStart = pop.addDays(pop.viewStart, 7) }
        }

        Grid {
          id: grid
          anchors.horizontalCenter: parent.horizontalCenter
          columns: 7
          rowSpacing: 1
          columnSpacing: 1

          readonly property int cell: 38

          // weekday header
          Repeater {
            model: ["日", "一", "二", "三", "四", "五", "六"]
            delegate: Item {
              required property var modelData
              required property int index
              width: grid.cell
              height: 18
              Text {
                anchors.centerIn: parent
                text: parent.modelData
                color: (index === 0 || index === 6) ? Theme.muted : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tinyText
              }
            }
          }

          // 6 weeks x 7 days
          Repeater {
            model: 42
            delegate: Rectangle {
              required property int index
              property var d: pop.addDays(pop.viewStart, index)
              property bool isToday: pop.sameDay(d, pop.today)
              property bool inMonth: d.getMonth() === pop.labelDate().getMonth()
              width: grid.cell
              height: 26
              radius: Theme.itemRadius
              color: isToday ? Theme.activeBg : "transparent"
              Text {
                anchors.centerIn: parent
                text: d.getDate()
                color: isToday ? Theme.activeFg : (inMonth ? Theme.fg : Theme.dim)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallText
              }
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Theme.dim }

      // ---- notifications ----
      Item {
        width: parent.width
        height: 20
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "通知"
          color: Theme.fg
          font.family: Theme.fontFamily
          font.pixelSize: Theme.normalText
          font.letterSpacing: 2
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: pop.notif && pop.notif.count > 0
          text: "全部清除"
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.smallText
          MouseArea {
            anchors.fill: parent; anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (pop.notif) pop.notif.dismissAll() }
          }
        }
      }

      Flickable {
        width: parent.width
        height: Math.min(contentHeight, 200)
        contentWidth: width
        contentHeight: ncol.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: ncol
          width: parent.width
          spacing: 4

          Repeater {
            model: pop.notif ? pop.notif.model : null
            delegate: Rectangle {
              id: nrow
              required property var modelData
              width: ncol.width
              height: ninner.implicitHeight + 12
              color: Theme.bgAlt
              radius: Theme.itemRadius
              border.color: modelData.urgency === NotificationUrgency.Critical ? Theme.red : Theme.dim
              border.width: 1

              Column {
                id: ninner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 8
                anchors.rightMargin: 24
                anchors.topMargin: 6
                spacing: 1

                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  text: nrow.modelData.appName || "通知"
                  color: Theme.muted
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.tinyText
                  font.letterSpacing: 1
                }
                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  visible: nrow.modelData.summary && nrow.modelData.summary.length > 0
                  text: nrow.modelData.summary
                  color: Theme.fg
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.smallText
                }
                Text {
                  width: parent.width
                  visible: nrow.modelData.body && nrow.modelData.body.length > 0
                  text: nrow.modelData.body
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                  color: Theme.muted
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.tinyText
                }
              }

              Text {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: 5
                anchors.rightMargin: 7
                text: "✕"
                color: dismMouse.containsMouse ? Theme.fg : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tinyText
                MouseArea {
                  id: dismMouse
                  anchors.fill: parent
                  anchors.margins: -4
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: nrow.modelData.dismiss()
                }
              }
            }
          }

          Text {
            visible: !pop.notif || pop.notif.count === 0
            padding: 6
            text: "沒有通知"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallText
          }
        }
      }
    }
  }
}
