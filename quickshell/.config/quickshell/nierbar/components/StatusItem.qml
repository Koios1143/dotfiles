import QtQuick
import Quickshell
import "../style"

Item {
  id: root
  property string icon: ""
  property string label: ""
  property string tooltip: ""
  property color fg: Theme.fg
  property int minWidth: content.implicitWidth + 10
  property bool enableHover: tooltip.length > 0
  property bool compact: false
  property var onLeftClick: null
  property var onMiddleClick: null
  property var onWheelUp: null
  property var onWheelDown: null

  implicitWidth: Math.max(minWidth, content.implicitWidth + (compact ? 4 : 8))
  implicitHeight: Theme.itemHeight

  Row {
    id: content
    anchors.centerIn: parent
    height: root.implicitHeight
    spacing: compact ? 3 : 5

    Text {
      visible: root.icon.length > 0
      text: root.icon
      color: root.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.iconText
      height: parent.height
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      id: labelText
      visible: root.label.length > 0
      text: root.label
      color: root.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.smallText
      width: root.label.indexOf("\n") >= 0 ? Math.max(1, root.minWidth - 8) : implicitWidth
      height: parent.height
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: root.label.indexOf("\n") >= 0 ? Text.AlignHCenter : Text.AlignLeft
      lineHeight: root.label.indexOf("\n") >= 0 ? 0.9 : 1.0
      lineHeightMode: Text.ProportionalHeight
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: (root.onLeftClick !== null || root.onMiddleClick !== null) ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: event => {
      if (event.button === Qt.LeftButton && root.onLeftClick) root.onLeftClick()
      if (event.button === Qt.MiddleButton && root.onMiddleClick) root.onMiddleClick()
    }
    onWheel: wheel => {
      if (wheel.angleDelta.y > 0 && root.onWheelUp) root.onWheelUp()
      if (wheel.angleDelta.y < 0 && root.onWheelDown) root.onWheelDown()
    }
  }

  Tooltip {
    x: root.width / 2 - width / 2
    y: Theme.barHeight + 6
    text: root.tooltip
    shown: root.enableHover && mouse.containsMouse
  }
}
