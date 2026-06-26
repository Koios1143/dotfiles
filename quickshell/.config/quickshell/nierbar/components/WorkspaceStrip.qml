import QtQuick
import Quickshell.Hyprland
import "../style"

Row {
  id: root

  // Keep the bar compact. Increase this if you routinely use more workspaces.
  property int workspaceCount: 5

  spacing: 5

  function isFocused(id) {
    return Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === id
  }

  Repeater {
    model: root.workspaceCount

    Rectangle {
      required property int index
      property int wsId: index + 1
      property bool focused: root.isFocused(wsId)

      width: Theme.workspaceSize
      height: Theme.workspaceSize
      radius: 1
      color: focused ? Theme.activeBg : "transparent"
      border.color: focused ? Theme.activeBg : Theme.dim
      border.width: 1

      Text {
        anchors.centerIn: parent
        text: wsId
        color: parent.focused ? Theme.activeFg : Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.normalText
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        acceptedButtons: Qt.LeftButton

        onClicked: Hyprland.dispatch("workspace " + wsId)

        onWheel: wheel => {
          if (wheel.angleDelta.y > 0)
            Hyprland.dispatch("workspace e-1")
          else if (wheel.angleDelta.y < 0)
            Hyprland.dispatch("workspace e+1")
        }
      }
    }
  }
}
