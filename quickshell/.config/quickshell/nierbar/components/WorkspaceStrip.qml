import QtQuick
import Quickshell.Hyprland
import "../style"

Row {
  id: root

  // Keep the bar compact. Increase this if you routinely use more workspaces.
  property int workspaceCount: 5

  // shared across delegates so touchpad scrolling steps cleanly
  property real wheelAccum: 0

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

        // This Hyprland build evaluates dispatch requests as Lua (see hyprland.lua),
        // so send the Lua dispatcher call itself, not the plain "workspace N" string.
        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsId + " })")

        onWheel: wheel => {
          // physical up => previous workspace, down => next
          root.wheelAccum += Wheel.norm(wheel)
          while (root.wheelAccum >= Wheel.step) { root.wheelAccum -= Wheel.step; Hyprland.dispatch('hl.dsp.focus({ workspace = "e-1" })') }
          while (root.wheelAccum <= -Wheel.step) { root.wheelAccum += Wheel.step; Hyprland.dispatch('hl.dsp.focus({ workspace = "e+1" })') }
        }
      }
    }
  }
}
