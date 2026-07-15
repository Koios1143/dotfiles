import QtQuick
import Quickshell
import Quickshell.Wayland
import "../style"
import "../services"

// Drop-down WiFi picker anchored under the bar's network icon. Full-screen
// transparent overlay (click-away to dismiss), same pattern as powermenu.
PanelWindow {
  id: pop
  // `shown` drives the open/close animation; `visible` trails it so the window
  // stays mapped until the close transition finishes.
  property bool shown: false
  visible: shown || cardScale.yScale > 0.001

  WlrLayershell.layer: WlrLayer.Overlay
  // OnDemand so the popup only grabs the keyboard once the password field asks.
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  WlrLayershell.namespace: "nierbar-network"
  anchors { top: true; left: true; right: true; bottom: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  property string pendingSsid: ""

  // ---- hotspot panel UI state ----
  property bool hsShowPw: false    // reveal the password field (eye toggle)
  property bool hsShowQr: false    // show the join QR instead of the client list
  property string hsBand: "bg"     // currently-selected band in the picker

  // scene-x and width of the icon that opened us, so the card sits below it
  property real anchorX: 0
  property real anchorWidth: 0

  function seedHotspotFields() {
    if (!ssidField.activeFocus) ssidField.text = net.hotspotSsid
    if (!pwHsField.activeFocus) pwHsField.text = net.hotspotPassword
    pop.hsBand = net.hotspotBand
  }

  function open() { pop.shown = true; net.refresh(); net.rescan(); pop.seedHotspotFields() }
  function close() { pop.shown = false; pop.pendingSsid = ""; pwField.text = ""; pop.hsShowQr = false }
  function toggle() { pop.shown ? pop.close() : pop.open() }
  function openAt(x, w) { pop.anchorX = x; pop.anchorWidth = w; pop.open() }
  function toggleAt(x, w) { pop.shown ? pop.close() : pop.openAt(x, w) }

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

  function profIcon(type) {
    if (type === "vpn" || type === "wireguard") return "󰖂"
    if (type === "802-3-ethernet") return "󰈀"
    return "󰛳"
  }

  // toggle a stored ethernet/vpn profile on or off
  function profileClicked(p) {
    if (p.active) net.deactivate(p.name, p.uuid)
    else net.activate(p.name, p.uuid)
  }

  function toggleHotspot() {
    if (net.hotspotActive) net.stopHotspot()
    else net.startHotspot(net.hotspotSsid, net.hotspotPassword, net.hotspotBand)
  }

  // re-apply the current field values to a running hotspot (SSID / pw / band)
  function applyHotspot() {
    net.startHotspot(ssidField.text, pwHsField.text, pop.hsBand)
    if (pop.hsShowQr) net.makeQr()
  }

  NetworkService {
    id: net
    onNeedsPassword: ssid => { if (pop.shown) pop.promptPassword(ssid) }
  }

  // the hotspot status arrives asynchronously after open(); reseed the fields
  // (unless the user is mid-edit) so they reflect the stored config.
  Connections {
    target: net
    function onHotspotSsidChanged() { if (!ssidField.activeFocus) ssidField.text = net.hotspotSsid }
    function onHotspotPasswordChanged() { if (!pwHsField.activeFocus) pwHsField.text = net.hotspotPassword }
    function onHotspotBandChanged() { pop.hsBand = net.hotspotBand }
  }

  // poll associated clients while the hotspot panel is showing the list
  Timer {
    interval: 4000
    repeat: true
    triggeredOnStart: true
    running: pop.shown && net.hotspotActive && !pop.hsShowQr
    onTriggered: net.refreshClients()
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

    // HUD panel: unfolds downward out of the bar on open, retracts back up on
    // close (scaled from the top edge so it reads as deploy / pull-back, not a fade).
    transform: Scale {
      id: cardScale
      origin.y: 0
      yScale: pop.shown ? 1 : 0
      Behavior on yScale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
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
            text: "󰀃"                              // hotspot (access point)
            color: net.hotspotActive ? Theme.blue : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconText
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: pop.toggleHotspot()
            }
          }

          Text {
            // wifi reads as "off" while the hotspot owns the radio (client mode
            // is dropped); clicking it then stops the hotspot to restore wifi.
            text: (net.wifiEnabled && !net.hotspotActive) ? "󰖩" : "󰖪"
            color: (net.wifiEnabled && !net.hotspotActive) ? Theme.blue : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconText
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: net.hotspotActive ? net.stopHotspot() : net.toggleWifi()
            }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Theme.dim }

      // shared delegate for ethernet/vpn profile rows (click to toggle)
      Component {
        id: profileDelegate
        Rectangle {
          id: prow
          required property var modelData
          width: parent ? parent.width : 0
          height: 34
          color: prowMouse.containsMouse ? Theme.bgAlt : "transparent"

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
              text: pop.profIcon(prow.modelData.type)
              color: prow.modelData.active ? Theme.blue : Theme.fg
              font.family: Theme.fontFamily
              font.pixelSize: Theme.iconText
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 20 - 8 - 8 - checkText.implicitWidth
              elide: Text.ElideRight
              text: prow.modelData.name
              color: prow.modelData.active ? Theme.blue : Theme.fg
              font.family: Theme.fontFamily
              font.pixelSize: Theme.smallText
            }

            Text {
              id: checkText
              anchors.verticalCenter: parent.verticalCenter
              text: prow.modelData.active ? "󰄬" : ""
              color: Theme.blue
              font.family: Theme.fontFamily
              font.pixelSize: Theme.iconText
            }
          }

          MouseArea {
            id: prowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pop.profileClicked(prow.modelData)
          }
        }
      }

      // ---- ethernet ----
      Text {
        visible: net.ethernets.length > 0
        text: "ETHERNET"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tinyText
        font.letterSpacing: 1.5
      }

      Column {
        visible: net.ethernets.length > 0
        width: parent.width
        spacing: 2
        Repeater { model: net.ethernets; delegate: profileDelegate }
      }

      // ---- network list ----
      Text {
        visible: net.ethernets.length > 0 || net.vpns.length > 0
        text: "WI-FI"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tinyText
        font.letterSpacing: 1.5
      }

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
            // while the AP is up the device can't scan as a client; hide the
            // whole list (including the hotspot's own SSID).
            model: net.hotspotActive ? [] : net.networks
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
            visible: net.hotspotActive || net.networks.length === 0
            padding: 6
            text: net.hotspotActive ? "Hotspot active — WiFi paused"
                                    : (net.wifiEnabled ? "No networks found" : "WiFi is off")
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallText
          }
        }
      }

      // ---- vpn ----
      Text {
        visible: net.vpns.length > 0
        text: "VPN"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tinyText
        font.letterSpacing: 1.5
      }

      Column {
        visible: net.vpns.length > 0
        width: parent.width
        spacing: 2
        Repeater { model: net.vpns; delegate: profileDelegate }
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

      // ==== hotspot settings (only while the hotspot is running) ====
      Rectangle {
        visible: net.hotspotActive
        width: parent.width
        height: 1
        color: Theme.dim
      }

      Column {
        visible: net.hotspotActive
        width: parent.width
        spacing: 8

        Text {
          text: "HOTSPOT"
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.tinyText
          font.letterSpacing: 1.5
        }

        // ---- SSID ----
        Text {
          text: "SSID"
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.tinyText
        }
        Rectangle {
          width: parent.width
          height: 26
          color: Theme.bgAlt
          border.color: ssidField.activeFocus ? Theme.line : Theme.dim
          border.width: 1
          TextInput {
            id: ssidField
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallText
            clip: true
            onAccepted: pop.applyHotspot()
          }
        }

        // ---- password (with reveal toggle, hidden by default) ----
        Text {
          text: "Password"
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.tinyText
        }
        Rectangle {
          width: parent.width
          height: 26
          color: Theme.bgAlt
          border.color: pwHsField.activeFocus ? Theme.line : Theme.dim
          border.width: 1

          TextInput {
            id: pwHsField
            anchors.left: parent.left
            anchors.right: eyeBtn.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            height: parent.height
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallText
            echoMode: pop.hsShowPw ? TextInput.Normal : TextInput.Password
            clip: true
            onAccepted: pop.applyHotspot()
          }

          Text {
            id: eyeBtn
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: pop.hsShowPw ? "󰈈" : "󰈉"      // open eye = shown, eye-off = hidden
            color: pop.hsShowPw ? Theme.blue : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconText
            MouseArea {
              anchors.fill: parent
              anchors.margins: -4
              cursorShape: Qt.PointingHandCursor
              onClicked: pop.hsShowPw = !pop.hsShowPw
            }
          }
        }

        // ---- band ----
        Text {
          text: "Band"
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.tinyText
        }
        Row {
          width: parent.width
          spacing: 6

          Rectangle {
            width: (parent.width - 6) / 2
            height: 26
            color: pop.hsBand === "bg" ? Theme.activeBg : "transparent"
            border.color: pop.hsBand === "bg" ? Theme.activeBg : Theme.dim
            border.width: 1
            Text {
              anchors.centerIn: parent
              text: "2.4 GHz"
              color: pop.hsBand === "bg" ? Theme.activeFg : Theme.fg
              font.family: Theme.fontFamily
              font.pixelSize: Theme.smallText
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: pop.hsBand = "bg"
            }
          }

          Rectangle {
            width: (parent.width - 6) / 2
            height: 26
            color: pop.hsBand === "a" ? Theme.activeBg : "transparent"
            border.color: pop.hsBand === "a" ? Theme.activeBg : Theme.dim
            border.width: 1
            Text {
              anchors.centerIn: parent
              text: "5 GHz"
              color: pop.hsBand === "a" ? Theme.activeFg : Theme.fg
              font.family: Theme.fontFamily
              font.pixelSize: Theme.smallText
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: pop.hsBand = "a"
            }
          }
        }

        // ---- apply + QR toggle ----
        Row {
          width: parent.width
          spacing: 6
          layoutDirection: Qt.RightToLeft

          Rectangle {
            width: 84
            height: 26
            color: applyMouse.containsMouse ? Theme.activeBg : "transparent"
            border.color: Theme.line
            border.width: 1
            Text {
              anchors.centerIn: parent
              text: "Apply"
              color: applyMouse.containsMouse ? Theme.activeFg : Theme.fg
              font.family: Theme.fontFamily
              font.pixelSize: Theme.smallText
            }
            MouseArea {
              id: applyMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: pop.applyHotspot()
            }
          }

          Rectangle {
            width: parent.width - 84 - 6
            height: 26
            color: qrMouse.containsMouse ? Theme.bgAlt : "transparent"
            border.color: pop.hsShowQr ? Theme.line : Theme.dim
            border.width: 1
            Text {
              anchors.centerIn: parent
              text: pop.hsShowQr ? "󰅖  Hide QR" : "󰐲  Show QR"
              color: Theme.fg
              font.family: Theme.fontFamily
              font.pixelSize: Theme.smallText
            }
            MouseArea {
              id: qrMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { pop.hsShowQr = !pop.hsShowQr; if (pop.hsShowQr) net.makeQr() }
            }
          }
        }

        // ---- QR view (replaces the client list while shown) ----
        Item {
          visible: pop.hsShowQr
          width: parent.width
          height: visible ? 176 : 0
          Rectangle {
            anchors.centerIn: parent
            width: 168
            height: 168
            color: "white"
            Image {
              anchors.centerIn: parent
              width: 156
              height: 156
              source: net.hotspotQrPath
              fillMode: Image.PreserveAspectFit
              smooth: false
              cache: false
            }
          }
        }

        // ---- connected devices ----
        Column {
          visible: !pop.hsShowQr
          width: parent.width
          spacing: 4

          Text {
            text: "CONNECTED (" + net.hotspotClients.length + ")"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tinyText
            font.letterSpacing: 1.5
          }

          Repeater {
            model: net.hotspotClients
            delegate: Row {
              id: clientRow
              required property var modelData
              width: parent ? parent.width : 0
              height: 18
              spacing: 8

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 3.5
                color: Theme.green
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 7 - 8
                elide: Text.ElideRight
                text: clientRow.modelData
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallText
              }
            }
          }

          Text {
            visible: net.hotspotClients.length === 0
            text: "No devices connected"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallText
          }
        }
      }
    }
  }
}
