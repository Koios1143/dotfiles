import QtQuick
import Quickshell
import Quickshell.Wayland
import "../style"

// Drop-down brightness panel: a draggable/scrollable slider, opened below the
// brightness icon. Shares the bar's SystemService (passed in as `sys`).
PanelWindow {
  id: bp
  visible: false

  property var sys

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "nierbar-brightness"
  anchors { top: true; left: true; right: true; bottom: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  property bool dragging: false
  property int level: 0

  // scene-x and width of the icon that opened us, so the card sits below it
  property real anchorX: 0
  property real anchorWidth: 0

  function open() { bp.visible = true; if (sys) sys.refreshFast() }
  function close() { bp.visible = false }
  function openAt(x, w) { bp.anchorX = x; bp.anchorWidth = w; bp.open() }
  function toggleAt(x, w) { bp.visible ? bp.close() : bp.openAt(x, w) }

  function brIcon() {
    if (bp.level <= 33) return "󰃞"
    if (bp.level <= 66) return "󰃟"
    return "󰃠"
  }

  // follow polled brightness except while dragging the handle
  Binding {
    target: bp
    property: "level"
    value: sys ? Number(sys.brightness) : 0
    when: !bp.dragging
  }

  MouseArea {
    anchors.fill: parent
    onClicked: bp.close()
  }

  Rectangle {
    id: card
    anchors.top: parent.top
    anchors.topMargin: Theme.barHeight + 6
    width: 260
    // centred under the icon, clamped to stay on screen
    x: Math.max(Theme.sideMargin,
         Math.min(parent.width - width - Theme.sideMargin,
                  bp.anchorX + bp.anchorWidth / 2 - width / 2))
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

      // ---- header ----
      Item {
        width: parent.width
        height: 22

        Text {
          id: brIconText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: bp.brIcon()
          color: Theme.fg
          font.family: Theme.fontFamily
          font.pixelSize: Theme.iconText
        }

        Text {
          anchors.left: brIconText.right
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: "BRIGHTNESS"
          color: Theme.fg
          font.family: Theme.fontFamily
          font.pixelSize: Theme.normalText
          font.letterSpacing: 2
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: bp.level + "%"
          color: Theme.muted
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

          Rectangle {
            height: parent.height
            radius: 3
            width: parent.width * Math.min(1, bp.level / 100)
            color: Theme.blue
          }

          Rectangle {
            width: 12
            height: 12
            radius: 6
            color: Theme.fg
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(0, Math.min(parent.width - width,
                 parent.width * (bp.level / 100) - width / 2))
          }
        }

        MouseArea {
          anchors.fill: parent
          function apply(mx) {
            if (!bp.sys) return
            var f = Math.max(0, Math.min(1, mx / width))
            bp.level = Math.round(f * 100)
            bp.sys.setBrightness(bp.level)
          }
          onPressed: e => { bp.dragging = true; apply(e.x) }
          onPositionChanged: e => { if (bp.dragging) apply(e.x) }
          onReleased: bp.dragging = false
          onCanceled: bp.dragging = false
          property real wheelAccum: 0
          onWheel: w => {
            if (!bp.sys) return
            wheelAccum += Wheel.norm(w)
            while (wheelAccum >= Wheel.step) { wheelAccum -= Wheel.step; bp.sys.changeBrightness(1) }
            while (wheelAccum <= -Wheel.step) { wheelAccum += Wheel.step; bp.sys.changeBrightness(-1) }
          }
        }
      }
    }
  }
}
