import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
    PanelWindow {
        id: root

        // Cover waybar:Overlay
        WlrLayershell.layer: WlrLayer.Overlay
        // Own keyboard focus to accept arrow signals
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "powermenu"

        // Force full screen
        anchors { top: true; left: true; right: true; bottom: true }
        // Without exclusion zone
        exclusionMode: ExclusionMode.Ignore

        color: "transparent"   // Background using image, window remain transparent

        // ---- Options ----
        property var items: [
            { icon: "\uf023", label: "Lock",      cmd: "/home/koios/.local/share/quickshell-lockscreen/lock.sh" },
            { icon: "\uf2f5", label: "Logout",    cmd: "hyprctl dispatch 'hl.dsp.exit()'" },
            { icon: "\uf186", label: "Suspend",   cmd: "systemctl suspend" },
            { icon: "\uf2dc", label: "Hibernate", cmd: "systemctl hibernate" },
            { icon: "\uf011", label: "Shutdown",  cmd: "systemctl poweroff" },
            { icon: "\uf021", label: "Reboot",    cmd: "systemctl reboot" }
        ]
        property int sel: 0

        // ---- Run single command ----
	function runItem(i) {
	    console.log("runItem fired:", i, root.items[i].cmd);
	    Quickshell.execDetached(["sh", "-c", root.items[i].cmd]);
            Qt.quit();
        }

        // Background Image
        Image {
            anchors.fill: parent
            source: "YoRHa_bg1.png"
            fillMode: Image.PreserveAspectCrop
        }

        // Click other area to quit
        MouseArea {
            anchors.fill: parent
            onClicked: Qt.quit()
        }

        // ---- Keyboard focus scope ----
        FocusScope {
            id: scope
            anchors.fill: parent
            focus: true   // Get focus once open window

            Keys.onUpPressed:    root.sel = (root.sel - 1 + root.items.length) % root.items.length
            Keys.onDownPressed:  root.sel = (root.sel + 1) % root.items.length
            Keys.onReturnPressed: root.runItem(root.sel)
            Keys.onEnterPressed:  root.runItem(root.sel)
            Keys.onEscapePressed: Qt.quit()

            // ---- Buttom row ----
            Column {
                x: 120
                y: 272
                spacing: 20

                Repeater {
                    model: root.items
                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property var modelData

                        width: 510
                        height: 52
                        // Color when selected / not selected
                        color: root.sel === index
                               ? "#454138"
                               : Qt.rgba(216/255, 209/255, 188/255, 0.45)
                        border.width: root.sel === index ? 3 : 0
                        border.color: "#c2bba4"

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.sel = index           // mouse
                            onClicked: root.runItem(index)        // click
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 22
                            spacing: 18

                            Text {
                                text: row.modelData.icon
				font.family: "Symbols Nerd Font"
                                font.pixelSize: 24
				width: 30
				horizontalAlignment: Text.AlignHCenter
                                color: root.sel === row.index ? "#d8d1bc" : "#454138"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
				text: row.modelData.label
				font.family: "FOT-Rodin Pro"
				font.weight: Font.Medium
                                font.pixelSize: 26
                                color: root.sel === row.index ? "#d8d1bc" : "#454138"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
