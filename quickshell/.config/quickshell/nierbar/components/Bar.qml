import QtQuick
import Quickshell
import Quickshell.Wayland
import "../style"
import "../services"

PanelWindow {
  id: bar
  anchors { top: true; left: true; right: true }
  implicitHeight: Theme.barHeight
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Top

  HyprService { id: hypr }
  SystemService { id: sys }

  Rectangle {
    anchors.fill: parent
    color: Theme.bg
    opacity: 0.96
    border.color: Theme.line
    border.width: 1
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 1
    color: Theme.dim
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: Theme.sideMargin
    anchors.rightMargin: Theme.sideMargin

    Row {
      id: leftCluster
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10

      WorkspaceStrip {
        anchors.verticalCenter: parent.verticalCenter
        workspaceCount: 5
      }

      FocusedWindow {
        anchors.verticalCenter: parent.verticalCenter
        title: hypr.title
        windowClass: hypr.windowClass
        maxTitleWidth: Math.max(230, Math.min(420, bar.width * 0.28))
      }
    }

    CenterClock {
      id: centerClock
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
    }

    SystemCluster {
      id: rightCluster
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      sys: sys
    }
  }
}
