import Quickshell
import QtQuick
import "components"
import "services"

ShellRoot {
  // one notification server for the whole shell (only one process can own the
  // freedesktop notifications bus). Shared by every screen's popup + toasts.
  NotificationService { id: notifs }

  Variants {
    model: Quickshell.screens

    Scope {
      id: unit
      required property var modelData

      // one poller per screen, shared by the bar and the volume popup
      SystemService { id: sys }

      Bar {
        screen: unit.modelData
        sys: sys
        onNetworkClick: (x, w) => netPopup.toggleAt(x, w)
        onVolumeClick: (x, w) => volPopup.toggleAt(x, w)
        onBrightnessClick: (x, w) => brightPopup.toggleAt(x, w)
        onBluetoothClick: (x, w) => btPopup.toggleAt(x, w)
        onClockClick: (x, w) => calPopup.toggleAt(x, w)
      }

      NetworkPopup {
        id: netPopup
        screen: unit.modelData
      }

      VolumePopup {
        id: volPopup
        screen: unit.modelData
        sys: sys
      }

      BrightnessPopup {
        id: brightPopup
        screen: unit.modelData
        sys: sys
      }

      BluetoothPopup {
        id: btPopup
        screen: unit.modelData
      }

      CalendarPopup {
        id: calPopup
        screen: unit.modelData
        notif: notifs
      }

      NotificationToasts {
        screen: unit.modelData
        notif: notifs
      }
    }
  }
}
