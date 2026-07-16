import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../style"

// StatusNotifierItem tray: shows app-provided tray icons (fcitx5, Discord,
// download managers, …). Left click activates, middle secondary-activates,
// right click (or left when the item is menu-only) opens its context menu.
Row {
  id: root
  spacing: 8

  // ── which applets to show ──────────────────────────────────────────────
  // Match on each item's SNI `id`. Current ids on this machine:
  //   "nm-applet"  (network)   "blueman" (bluetooth)
  //   "Fcitx"      (fcitx5)     "chrome_status_icon_1" (chrome)
  // Find an unknown one by hovering (tooltip) or:  busctl --user get-property
  //   <svc> <path> org.kde.StatusNotifierItem Id   (matching is case-sensitive)
  //
  // hidden : ids to always drop (network/bluetooth already live in the bar).
  // allowed: if non-empty, show ONLY these ids (allow-list mode); [] = show all.
  property var hidden: ["nm-applet", "blueman"]
  property var allowed: []

  readonly property var shownItems: SystemTray.items.values.filter(function (it) {
    if (root.hidden.indexOf(it.id) >= 0) return false
    if (root.allowed.length > 0 && root.allowed.indexOf(it.id) < 0) return false
    return true
  })

  visible: shownItems.length > 0

  Repeater {
    model: root.shownItems

    delegate: Item {
      id: trayItem
      required property var modelData
      implicitWidth: 20
      implicitHeight: Theme.itemHeight

      function openMenu() {
        if (!modelData.hasMenu) return
        const p = mapToItem(null, width / 2, height)
        modelData.display(QsWindow.window, p.x, p.y)
      }

      Image {
        id: img
        anchors.centerIn: parent
        width: 17
        height: 17
        // request at 2x so the icon stays crisp when scaled down
        sourceSize.width: 34
        sourceSize.height: 34
        fillMode: Image.PreserveAspectFit
        smooth: true
        source: trayItem.modelData.icon
        opacity: trayItem.modelData.status === Status.Passive ? 0.7 : 1.0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        // gentle pulse when an item requests attention (e.g. new message)
        SequentialAnimation on scale {
          running: trayItem.modelData.status === Status.NeedsAttention
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { from: 1.0; to: 1.18; duration: 500; easing.type: Easing.InOutSine }
          NumberAnimation { from: 1.18; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
        }
      }

      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
          const it = trayItem.modelData
          if (event.button === Qt.LeftButton) {
            if (it.onlyMenu) trayItem.openMenu()
            else it.activate()
          } else if (event.button === Qt.MiddleButton) {
            it.secondaryActivate()
          } else if (event.button === Qt.RightButton) {
            trayItem.openMenu()
          }
        }
        onWheel: wheel => {
          if (wheel.angleDelta.y !== 0) trayItem.modelData.scroll(wheel.angleDelta.y, false)
          if (wheel.angleDelta.x !== 0) trayItem.modelData.scroll(wheel.angleDelta.x, true)
        }
      }

      Tooltip {
        x: trayItem.width / 2 - width / 2
        y: Theme.barHeight + 6
        text: {
          const it = trayItem.modelData
          return (it.tooltipTitle && it.tooltipTitle.length) ? it.tooltipTitle
               : (it.title && it.title.length) ? it.title
               : it.id
        }
        shown: mouse.containsMouse
      }
    }
  }
}
