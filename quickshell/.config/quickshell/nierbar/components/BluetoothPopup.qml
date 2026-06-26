import QtQuick
import Quickshell
import Quickshell.Wayland
import "../style"
import "../services"

// Drop-down Bluetooth panel: power toggle, scan toggle, and a device list with
// connect/disconnect. Opened directly below the bar's bluetooth icon.
PanelWindow {
  id: pop
  visible: false

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "nierbar-bluetooth"
  anchors { top: true; left: true; right: true; bottom: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  // scene-x and width of the icon that opened us, so the card sits below it
  property real anchorX: 0
  property real anchorWidth: 0

  function open() { pop.visible = true; bt.refresh() }
  function close() { pop.visible = false; bt.stopScan() }
  function openAt(x, w) { pop.anchorX = x; pop.anchorWidth = w; pop.open() }
  function toggleAt(x, w) { pop.visible ? pop.close() : pop.openAt(x, w) }

  BluetoothService { id: bt }

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
      spacing: 8

      // ---- header: title + scan + power ----
      Item {
        width: parent.width
        height: 22

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "BLUETOOTH"
          color: Theme.fg
          font.family: Theme.fontFamily
          font.pixelSize: Theme.normalText
          font.letterSpacing: 2
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 14

          Text {
            text: ""                              // scan
            color: bt.scanning ? Theme.amber : (bt.powered ? Theme.muted : Theme.dim)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconText
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              enabled: bt.powered
              onClicked: bt.scanning ? bt.stopScan() : bt.startScan()
            }
          }

          Text {
            text: bt.powered ? "󰂯" : "󰂲"           // bluetooth on / off
            color: bt.powered ? Theme.blue : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconText
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: bt.togglePower()
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Theme.dim }

      // ---- device list ----
      Flickable {
        id: listFlick
        width: parent.width
        height: Math.min(contentHeight, 260)
        contentWidth: width
        contentHeight: listCol.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: listCol
          width: listFlick.width
          spacing: 2

          Repeater {
            model: bt.devices
            delegate: Rectangle {
              id: row
              required property var modelData
              width: listCol.width
              height: 34
              color: rowMouse.containsMouse ? Theme.bgAlt : "transparent"

              Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: 8

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 18
                  text: row.modelData.connected ? "󰂱" : "󰂯"
                  color: row.modelData.connected ? Theme.blue : Theme.fg
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.iconText
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 18 - 8 - markText.implicitWidth
                  elide: Text.ElideRight
                  text: row.modelData.name.length > 0 ? row.modelData.name : row.modelData.mac
                  color: row.modelData.connected ? Theme.blue : Theme.fg
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.smallText
                }

                Text {
                  id: markText
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.modelData.connected ? "connected" : ""
                  color: Theme.muted
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.tinyText
                }
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: row.modelData.connected
                  ? bt.disconnectDevice(row.modelData.mac)
                  : bt.connectDevice(row.modelData.mac)
              }
            }
          }

          Text {
            visible: bt.devices.length === 0
            padding: 6
            text: bt.powered ? (bt.scanning ? "Scanning…" : "No devices") : "Bluetooth is off"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallText
          }
        }
      }

      // ---- status line ----
      Text {
        visible: bt.status.length > 0
        width: parent.width
        elide: Text.ElideRight
        text: bt.status
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tinyText
      }
    }
  }
}
