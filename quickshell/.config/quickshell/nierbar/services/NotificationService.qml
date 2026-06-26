import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Single freedesktop notification server for the whole shell (instantiate ONCE
// in shell.qml). Only one process can own org.freedesktop.Notifications, so
// swaync must be stopped for this to receive anything.
Item {
  id: root

  readonly property var model: server.trackedNotifications
  readonly property int count: server.trackedNotifications ? server.trackedNotifications.values.length : 0

  // emitted when a fresh notification arrives (used to raise a toast)
  signal arrived(var notif)

  NotificationServer {
    id: server
    keepOnReload: false
    actionsSupported: true
    actionIconsSupported: false
    bodySupported: true
    bodyMarkupSupported: true
    imageSupported: true

    onNotification: notification => {
      notification.tracked = true        // keep it in trackedNotifications
      root.arrived(notification)
    }
  }

  function dismissAll() {
    if (!server.trackedNotifications) return
    const vals = server.trackedNotifications.values.slice()
    for (let i = 0; i < vals.length; i++) vals[i].dismiss()
  }
}
