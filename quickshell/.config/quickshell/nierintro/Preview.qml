// Live preview, for watching the transition at real frame pacing.
//
//   qml6 Preview.qml                      # uses the current wallpaper
//   qml6 Preview.qml -- /path/to/bg.png
//
// Space replays, Esc quits.

import QtQuick

Window {
    id: win
    visible: true
    width: 1280
    height: 720
    title: "NieR intro preview"
    color: "#000000"

    readonly property string backdrop: {
        var a = Qt.application.arguments
        var last = a[a.length - 1]
        // arguments[last] is the .qml file itself when nothing was passed
        var given = a.length > 1 && last.indexOf("/") === 0 && !/\.qml$/.test(last)
        return given ? last : "/home/koios/Pictures/wallpapers/bg9.jpg"
    }

    NierBackdrop {
        anchors.fill: parent
        amount: intro.latticeProgress
        Image {
            anchors.fill: parent
            source: "file://" + win.backdrop
            fillMode: Image.PreserveAspectCrop
        }
    }

    NierIntro { id: intro; anchors.fill: parent }

    // stand-in for the real menu, so the last two beats are visible
    Item {
        anchors.fill: parent
        opacity: 1

        Row {
            x: parent.height * 0.032
            y: parent.height * 0.050
            spacing: parent.height * 0.011
            Repeater {
                model: ["MAP", "QUESTS", "ITEMS", "WEAPONS", "SKILLS", "INTEL", "SYSTEM"]
                delegate: Rectangle {
                    required property int index
                    required property string modelData
                    visible: index < intro.tabsShown
                    height: win.height * 0.026
                    width: label.width + height * 1.6
                    color: index === 0 ? intro.ink : Qt.rgba(0, 0, 0, 0.07)
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.index === 0 ? intro.beige : intro.ink
                        font.pixelSize: win.height * 0.016
                        font.letterSpacing: 1
                        font.family: "JetBrainsMono Nerd Font"
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            opacity: intro.bodyProgress
            Text {
                x: win.height * 0.032
                y: win.height * 0.135
                text: "MAP"
                color: intro.ink
                font.pixelSize: win.height * 0.042
                font.letterSpacing: 6
                font.family: "JetBrainsMono Nerd Font"
            }
            Text {
                x: win.height * 0.032
                y: win.height * 0.882
                text: "View the map or perform a quick-save."
                color: intro.ink
                font.pixelSize: win.height * 0.017
                font.family: "JetBrainsMono Nerd Font"
            }
        }
    }

    Component.onCompleted: { intro.prepare(); replay.start() }
    Timer { id: replay; interval: 250; onTriggered: intro.start() }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onSpacePressed: intro.start()
        Keys.onEscapePressed: Qt.quit()
    }
}
