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

        // ---- Options (desc drives the footer message; edit freely) ----
        property var items: [
            { icon: "\uf023", label: "Lock",      desc: "Lock the session",            cmd: "/home/koios/.config/quickshell/nier-lock/quickshell-lockscreen/lock.sh" },
            { icon: "\uf2f5", label: "Logout",    desc: "End the session and log out",  cmd: "hyprctl dispatch 'hl.dsp.exit()'" },
            { icon: "\uf186", label: "Suspend",   desc: "Sleep, keeping state in RAM",  cmd: "systemctl suspend" },
            { icon: "\uf2dc", label: "Hibernate", desc: "Save state to disk and stop",  cmd: "systemctl hibernate" },
            { icon: "\uf011", label: "Shutdown",  desc: "Power off the machine",        cmd: "systemctl poweroff" },
            { icon: "\uf021", label: "Reboot",    desc: "Restart the machine",          cmd: "systemctl reboot" }
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
                id: col
                x: 120
                y: 272
                spacing: 20

                Repeater {
                    id: rep
                    model: root.items
                    delegate: Rectangle {
                        id: row
                        required property int index
                        required property var modelData

                        width: 510
                        height: 52
                        // unselected buttons have an opaque fill (covers the grid like
                        // the game, so no wash); selected turns dark + gets focus lines
                        color: root.sel === index ? "#454138" : "#aeaa95"

                        // focus lines: thin near-black rules above & below the selected
                        // button, held ~6px off it (they overflow into the row spacing)
                        Rectangle {
                            visible: root.sel === row.index
                            width: parent.width; height: 2; color: "#26241f"
                            anchors.bottom: parent.top; anchors.bottomMargin: 6
                        }
                        Rectangle {
                            visible: root.sel === row.index
                            width: parent.width; height: 2; color: "#26241f"
                            anchors.top: parent.bottom; anchors.topMargin: 6
                        }

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

            // ---- kite movement axis is baked into YoRHa_bg1.png (thick x62-73,
            //      thin x84-86), aligned to the two nav bars left of MAP. ----

            // ---- Sliding NieR kite, pointing at the selected option.
            //      gap=16 puts the ring (~x79) in the baked rail gap (73..84). ----
            SelectionKite {
                target: rep.count > 0 ? rep.itemAt(root.sel) : null
                gap: 16
            }

            // ---- Footer overlay (the bar itself is baked into YoRHa_bg1.png).
            //      This transparent layer just holds the dynamic message (left)
            //      and the key hints (right), sitting above the baked bar. ----
            Rectangle {
                id: footer
                x: 0; width: parent.width
                y: 918; height: 82
                color: "transparent"

                // reusable hint = bordered keycap + label
                component Hint: Item {
                    property string keys: ""
                    property string label: ""
                    implicitHeight: 24
                    implicitWidth: kc.width + lbl.implicitWidth + 8
                    Rectangle {
                        id: kc; height: 22; radius: 3
                        width: Math.max(34, kt.implicitWidth + 14)
                        color: "transparent"; border.color: "#454138"; border.width: 1
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        Text { id: kt; anchors.centerIn: parent; text: keys
                               font.family: "FOT-Rodin Pro"; font.pixelSize: 13; color: "#454138" }
                    }
                    Text {
                        id: lbl; anchors.left: kc.right; anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: label; font.family: "FOT-Rodin Pro"; font.pixelSize: 18; color: "#454138"
                    }
                }

                // left: dynamic per-option message (edit items[].desc to change)
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 110
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.items[root.sel].desc || ""
                    font.family: "FOT-Rodin Pro"; font.pixelSize: 22; color: "#454138"
                }
                // right: key hints
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 120
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 30
                    Hint { keys: "\u2191\u2193"; label: "Select" }
                    Hint { keys: "\u21b5";       label: "Confirm" }
                    Hint { keys: "Esc";          label: "Back" }
                }
            }
        }
    }
}
