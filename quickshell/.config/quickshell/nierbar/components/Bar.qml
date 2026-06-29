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

    // slow glow-breath: the whole HUD frame dims and swells back like a low idle
    // pulse. Animating opacity (not repainting the Canvas) keeps it cheap.
    SequentialAnimation on opacity {
      loops: Animation.Infinite
      running: true
      NumberAnimation { from: 0.55; to: 1.0;  duration: 900;  easing.type: Easing.InOutSine }
      NumberAnimation { from: 1.0;  to: 0.55; duration: 1300; easing.type: Easing.InOutSine }
    }

    onPaint: {
      const ctx = getContext("2d")
      ctx.reset()
      const W = width, H = height
      const m = 3      // inset from the bar edge
      const c = 12     // chamfer (corner cut) length
      const c2 = 5     // small accent tick length

      ctx.strokeStyle = Theme.fg
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

  // top-right corner status tick that occasionally double-blinks, like a panel
  // handshake LED. Sits on top of the (breathing) frame tick at that corner.
  // The frame tick is centred at (W-5.5, 5.5); this overlays it, rotated to "\".
  Rectangle {
    id: statusFlash
    width: 8
    height: 1.5
    antialiasing: true
    rotation: 45
    transformOrigin: Item.Center
    color: Theme.fg
    opacity: 0
    x: bar.width - 5.5 - width / 2
    y: 5.5 - height / 2

    SequentialAnimation on opacity {
      loops: Animation.Infinite
      running: true
      PauseAnimation { duration: 5500 }
      NumberAnimation { to: 1; duration: 60 }
      NumberAnimation { to: 0; duration: 90 }
      PauseAnimation { duration: 110 }
      NumberAnimation { to: 1; duration: 60 }
      NumberAnimation { to: 0; duration: 130 }
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
