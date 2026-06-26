import QtQuick
import "../style"

Item {
  id: root
  property string title: "Desktop"
  property string windowClass: ""
  property int maxTitleWidth: 360

  implicitWidth: Math.min(maxTitleWidth, row.implicitWidth + 12)
  implicitHeight: Theme.itemHeight

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.color: Theme.dim
    border.width: 1
    opacity: 0.7
  }

  Row {
    id: row
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: 8
    spacing: 6

    Text {
      text: "◉"
      color: Theme.muted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.tinyText
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: titleText
      width: Math.min(root.maxTitleWidth - 28, implicitWidth)
      text: root.title
      color: Theme.fg
      elide: Text.ElideRight
      font.family: Theme.fontFamily
      font.pixelSize: Theme.normalText
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }

  Tooltip {
    x: Math.min(0, root.width / 2 - width / 2)
    y: Theme.barHeight + 6
    text: root.title
    shown: mouse.containsMouse && root.title.length > 0 && titleText.truncated
  }
}
