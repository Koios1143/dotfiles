import QtQuick
import Quickshell
import Quickshell.Wayland
import "../style"
import "../services"

// Drop-down WiFi picker anchored under the bar's network icon. Full-screen
// transparent overlay (click-away to dismiss), same pattern as powermenu.
PanelWindow {
  id: pop
  visible: false

  WlrLayershell.layer: WlrLayer.Overlay
  // OnDemand so the popup only grabs the keyboard once the password field asks.
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  WlrLayershell.namespace: "nierbar-network"
  anchors { top: true; left: true; right: true; bottom: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  property string pendingSsid: ""

  // scene-x and width of the icon that opened us, so the card sits below it
  property real anchorX: 0
  property real anchorWidth: 0

  function open() { pop.visible = true; net.refresh(); net.rescan() }
  function close() { pop.visible = false; pop.pendingSsid = ""; pwField.text = "" }
  function toggle() { pop.visible ? pop.close() : pop.open() }
  function openAt(x, w) { pop.anchorX = x; pop.anchorWidth = w; pop.open() }
  function toggleAt(x, w) { pop.visible ? pop.close() : pop.openAt(x, w) }

  function promptPassword(ssid) {
    pop.pendingSsid = ssid
    pwField.text = ""
    pwField.forceActiveFocus()
  }

  function rowClicked(n) {
    if (n.inUse) { net.disconnectFrom(n.ssid); return }
    // secured + never connected before → ask; otherwise let NM use its stored
    // secret (with a password-prompt fallback via net.needsPassword).
    if (n.security && n.security.length > 0 && !net.isSaved(n.ssid)) {
      pop.promptPassword(n.ssid)
    } else {
      net.connectTo(n.ssid, "")
    }
  }

  function sigIcon(s) {
    if (s >= 75) return "󰤨"
    if (s >= 55) return "󰤥"
    if (s >= 35) return "󰤢"
    if (s > 0)   return "󰤟"
    return "󰤯"
  }

  NetworkService {
    id: net
    onNeedsPassword: ssid => { if (pop.visible) pop.promptPassword(ssid) }
  }

  // click anywhere outside the card to close
  MouseArea {
    anchors.fill: parent
    onClicked: pop.close()
  }

  Rectangle {
    id: card
    anchors.top: parent.top
    anchors.topMargin: Theme.barHeight + 6
    width: 320
    // centred under the icon, clamped to stay on screen
    x: Math.max(Theme.sideMargin,
         Math.min(parent.width - width - Theme.sideMargin,
                  pop.anchorX + pop.anchorWidth / 2 - width / 2))
    implicitHeight: layout.implicitHeight + 24
    height: implicitHeight
    color: Theme.bg
    border.color: Theme.line
    border.width: 1
    radius: Theme.itemRadius

    // swallow clicks so they don't reach the dismiss handler behind the card
    MouseArea { anchors.fill: parent }

    Column {
      id: layout
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: 12
      spacing: 8

      // ---- header: title + rescan + wifi toggle ----
      Item {
        width: parent.width
        height: 22

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "NETWORK"
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
            text: ""                              // rescan
            color: net.busy ? Theme.amber : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconText
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: net.rescan()
            }
          }

          Text {
            text: net.wifiEnabled ? "󰖩" : "󰖪"      // wifi on / off
            color: net.wifiEnabled ? Theme.blue : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconText
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: net.toggleWifi()
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Theme.dim }

      // ---- network list ----
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
            model: net.networks
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
                  width: 20
                  text: pop.sigIcon(row.modelData.signal)
                  color: row.modelData.inUse ? Theme.blue : Theme.fg
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.iconText
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 20 - 8 - 8 - lockText.implicitWidth
                  elide: Text.ElideRight
                  text: row.modelData.ssid
                  color: row.modelData.inUse ? Theme.blue : Theme.fg
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.smallText
                }

                Text {
                  id: lockText
                  anchors.verticalCenter: parent.verticalCenter
                  text: (row.modelData.security && row.modelData.security.length > 0) ? "" : ""
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
                onClicked: pop.rowClicked(row.modelData)
              }
            }
          }

          Text {
            visible: net.networks.length === 0
            padding: 6
            text: net.wifiEnabled ? "No networks found" : "WiFi is off"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallText
          }
        }
      }

      // ---- inline password entry for secured networks ----
      Rectangle {
        visible: pop.pendingSsid.length > 0
        width: parent.width
        height: 1
        color: Theme.dim
      }

      Column {
        visible: pop.pendingSsid.length > 0
        width: parent.width
        spacing: 6

        Text {
          width: parent.width
          elide: Text.ElideRight
          text: "Password · " + pop.pendingSsid
          color: Theme.fg
          font.family: Theme.fontFamily
          font.pixelSize: Theme.smallText
        }

        Rectangle {
          width: parent.width
          height: 26
          color: Theme.bgAlt
          border.color: pwField.activeFocus ? Theme.line : Theme.dim
          border.width: 1

          TextInput {
            id: pwField
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallText
            echoMode: TextInput.Password
            clip: true
            onAccepted: { net.connectTo(pop.pendingSsid, text); pop.pendingSsid = ""; text = "" }
            Keys.onEscapePressed: { pop.pendingSsid = ""; text = "" }
          }
        }

        Row {
          width: parent.width
          spacing: 6
          layoutDirection: Qt.RightToLeft

          Rectangle {
            width: 84; height: 24
            color: connMouse.containsMouse ? Theme.activeBg : "transparent"
            border.color: Theme.line; border.width: 1
            Text {
              anchors.centerIn: parent
              text: "Connect"
              color: connMouse.containsMouse ? Theme.activeFg : Theme.fg
              font.family: Theme.fontFamily
              font.pixelSize: Theme.smallText
            }
            MouseArea {
              id: connMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { net.connectTo(pop.pendingSsid, pwField.text); pop.pendingSsid = ""; pwField.text = "" }
            }
          }

          Rectangle {
            width: 72; height: 24
            color: cancelMouse.containsMouse ? Theme.bgAlt : "transparent"
            border.color: Theme.dim; border.width: 1
            Text {
              anchors.centerIn: parent
              text: "Cancel"
              color: Theme.muted
              font.family: Theme.fontFamily
              font.pixelSize: Theme.smallText
            }
            MouseArea {
              id: cancelMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { pop.pendingSsid = ""; pwField.text = "" }
            }
          }
        }
      }

      // ---- status line ----
      Text {
        visible: net.status.length > 0
        width: parent.width
        elide: Text.ElideRight
        text: net.status
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tinyText
      }
    }
  }
}
