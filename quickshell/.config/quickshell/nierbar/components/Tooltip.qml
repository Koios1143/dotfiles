import QtQuick
import "../style"

Rectangle {
  id: root
  property alias text: label.text
  property bool shown: false

  visible: shown && label.text.length > 0
  z: 999
  color: Theme.bgAlt
  border.color: Theme.line
  border.width: 1
  radius: 1
  implicitWidth: label.implicitWidth + 14
  implicitHeight: 24

  Text {
    id: label
    anchors.centerIn: parent
    color: Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.smallText
  }
}
