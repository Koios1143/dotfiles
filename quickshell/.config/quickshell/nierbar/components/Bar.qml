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

  // shared SystemService (created in shell.qml so popups can use it too)
  property var sys
  // forwarded from shell.qml so icons can toggle their popups
  property var onNetworkClick: null
  property var onVolumeClick: null
  property var onBrightnessClick: null
  property var onBluetoothClick: null
  property var onClockClick: null

  HyprService { id: hypr }

  Rectangle {
    anchors.fill: parent
    color: Theme.bg
    opacity: 0.96
  }

  // decorative chamfered HUD frame with corner accent ticks (matches the mockup)
  Canvas {
    id: frame
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
      const ctx = getContext("2d")
      ctx.reset()
      const W = width, H = height
      const m = 3      // inset from the bar edge
      const c = 12     // chamfer (corner cut) length
      const c2 = 5     // small accent tick length

      ctx.strokeStyle = Theme.line
      ctx.lineWidth = 1

      // main chamfered-rectangle outline
      ctx.beginPath()
      ctx.moveTo(m + c, m)
      ctx.lineTo(W - m - c, m)
      ctx.lineTo(W - m, m + c)
      ctx.lineTo(W - m, H - m - c)
      ctx.lineTo(W - m - c, H - m)
      ctx.lineTo(m + c, H - m)
      ctx.lineTo(m, H - m - c)
      ctx.lineTo(m, m + c)
      ctx.closePath()
      ctx.stroke()

      // small parallel accent tick tucked into each corner
      ctx.beginPath()
      ctx.moveTo(m, m + c2);          ctx.lineTo(m + c2, m)
      ctx.moveTo(W - m, m + c2);      ctx.lineTo(W - m - c2, m)
      ctx.moveTo(W - m, H - m - c2);  ctx.lineTo(W - m - c2, H - m)
      ctx.moveTo(m, H - m - c2);      ctx.lineTo(m + c2, H - m)
      ctx.stroke()
    }
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
      onClockClick: bar.onClockClick
    }

    SystemCluster {
      id: rightCluster
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      sys: bar.sys
      onNetworkClick: bar.onNetworkClick
      onVolumeClick: bar.onVolumeClick
      onBrightnessClick: bar.onBrightnessClick
      onBluetoothClick: bar.onBluetoothClick
    }
  }
}
