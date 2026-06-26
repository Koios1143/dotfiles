import QtQuick
import Quickshell
import Quickshell.Wayland
import "../style"
import "../services"

// Drop-down volume panel: draggable/scrollable slider + output-device picker.
// Shares the bar's SystemService (passed in as `sys`) so state stays in sync.
PanelWindow {
  id: vp
  visible: false

  property var sys

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "nierbar-volume"
  anchors { top: true; left: true; right: true; bottom: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  property bool dragging: false
  property int level: 0

  // scene-x and width of the icon that opened us, so the card sits below it
  property real anchorX: 0
  property real anchorWidth: 0

  function open() { vp.visible = true; audio.refresh(); if (sys) sys.refreshFast() }
  function close() { vp.visible = false }
  function toggle() { vp.visible ? vp.close() : vp.open() }
  function openAt(x, w) { vp.anchorX = x; vp.anchorWidth = w; vp.open() }
  function toggleAt(x, w) { vp.visible ? vp.close() : vp.openAt(x, w) }

  function maxVol() { return sys ? sys.maxVolume : 100 }
  function volIcon() {
    if (sys && sys.muted) return "󰝟"
    if (vp.level <= 0) return "󰕿"
    if (vp.level <= 50) return "󰖀"
    return "󰕾"
  }

  AudioService { id: audio }

  // follow polled volume except while the user is dragging the handle
  Binding {
    target: vp
    property: "level"
    value: sys ? Number(sys.volume) : 0
    when: !vp.dragging
  }

  // click outside the card to dismiss
  MouseArea {
    anchors.fill: parent
    onClicked: vp.close()
  }

  Rectangle {
    id: card
    anchors.top: parent.top
    anchors.topMargin: Theme.barHeight + 6
    width: 300
    // centred under the icon, clamped to stay on screen
    x: Math.max(Theme.sideMargin,
         Math.min(parent.width - width - Theme.sideMargin,
                  vp.anchorX + vp.anchorWidth / 2 - width / 2))
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

      // ---- header: mute toggle + title + percent ----
      Item {
        width: parent.width
        height: 22

        Text {
          id: muteIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: vp.volIcon()
          color: (vp.sys && vp.sys.muted) ? Theme.muted : Theme.fg
          font.family: Theme.fontFamily
          font.pixelSize: Theme.iconText
          MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (vp.sys) vp.sys.toggleMute() }
          }
        }

        Text {
          anchors.left: muteIcon.right
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: "VOLUME"
          color: Theme.fg
          font.family: Theme.fontFamily
          font.pixelSize: Theme.normalText
          font.letterSpacing: 2
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: (vp.sys && vp.sys.muted) ? "muted" : (vp.level + "%")
          color: vp.level > 100 ? Theme.amber : Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.smallText
        }
      }

      // ---- slider ----
      Item {
        width: parent.width
        height: 18

        Rectangle {
          id: track
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: 6
          radius: 3
          color: Theme.dim

          // 100% reference tick (only meaningful when cap exceeds 100)
          Rectangle {
            visible: vp.maxVol() > 100
            width: 1
            height: 12
            color: Theme.muted
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * (100 / vp.maxVol())
          }

          Rectangle {
            height: parent.height
            radius: 3
            width: parent.width * Math.min(1, vp.level / vp.maxVol())
            color: vp.level > 100 ? Theme.amber : Theme.blue
          }

          Rectangle {
            width: 12
            height: 12
            radius: 6
            color: Theme.fg
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(parent.width - width,
                 parent.width * (vp.level / vp.maxVol()) - width / 2))
          }
        }

        MouseArea {
          anchors.fill: parent
          function apply(mx) {
            if (!vp.sys) return
            var f = Math.max(0, Math.min(1, mx / width))
            vp.level = Math.round(f * vp.maxVol())
            vp.sys.setVolume(vp.level)
          }
          onPressed: e => { vp.dragging = true; apply(e.x) }
          onPositionChanged: e => { if (vp.dragging) apply(e.x) }
          onReleased: vp.dragging = false
          onCanceled: vp.dragging = false
          property real wheelAccum: 0
          onWheel: w => {
            if (!vp.sys) return
            wheelAccum += Wheel.norm(w)
            while (wheelAccum >= Wheel.step) { wheelAccum -= Wheel.step; vp.sys.changeVolume(1) }
            while (wheelAccum <= -Wheel.step) { wheelAccum += Wheel.step; vp.sys.changeVolume(-1) }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Theme.dim }

      // ---- output devices ----
      Text {
        text: "OUTPUT"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tinyText
        font.letterSpacing: 2
      }

      Column {
        id: sinkCol
        width: parent.width
        spacing: 2

        Repeater {
          model: audio.sinks
          delegate: Rectangle {
            id: srow
            required property var modelData
            property bool isDefault: srow.modelData.name === audio.defaultSink
            width: sinkCol.width
            height: 30
            color: sinkMouse.containsMouse ? Theme.bgAlt : "transparent"

            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: 6
              anchors.rightMargin: 6
              spacing: 8

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                text: srow.isDefault ? "󰄬" : ""
                color: Theme.blue
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallText
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 16 - 8
                elide: Text.ElideRight
                text: srow.modelData.description
                color: srow.isDefault ? Theme.blue : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallText
              }
            }

            MouseArea {
              id: sinkMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: audio.setDefaultSink(srow.modelData.name)
            }
          }
        }

        Text {
          visible: audio.sinks.length === 0
          padding: 6
          text: "No output devices"
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.smallText
        }
      }
    }
  }
}
