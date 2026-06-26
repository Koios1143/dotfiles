import QtQuick
import "../style"

Item {
  id: root
  implicitWidth: 220
  implicitHeight: Theme.barHeight

  property date now: new Date()

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  Row {
    anchors.centerIn: parent
    spacing: 18

    Text {
      text: "◇─────"
      color: Theme.line
      font.family: Theme.fontFamily
      font.pixelSize: Theme.tinyText
      anchors.verticalCenter: clockBlock.verticalCenter
    }

    Column {
      id: clockBlock
      spacing: -1
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(root.now, "HH:mm")
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.timeText
        font.letterSpacing: 2
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(root.now, "yyyy / MM / dd  ddd").toUpperCase()
        color: Theme.fg
        opacity: 0.86
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tinyText
        font.letterSpacing: 1
      }
    }

    Text {
      text: "─────◇"
      color: Theme.line
      font.family: Theme.fontFamily
      font.pixelSize: Theme.tinyText
      anchors.verticalCenter: clockBlock.verticalCenter
    }
  }
}
