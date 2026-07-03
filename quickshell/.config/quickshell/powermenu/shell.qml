import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: shell
    // `s` lives on the component-root object so every unqualified `s` in the theme
    // body resolves (the theme was authored with `s` on its root Rectangle).
    readonly property real s: (win.screen && win.screen.height > 0 ? win.screen.height : 1080) / 768
    // Reuse the lock/login theme's assets (svg tab icons, emblem frames, bg) via
    // an absolute file:// url — quickshell doesn't resolve "../" relative paths here.
    readonly property string themeUrl: "file:///home/koios/.config/quickshell/nier-lock/themes/nier-automata/"

PanelWindow {
    id: win
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "powermenu"
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    Rectangle {
    id: root
    anchors.fill: parent
    focus: true
    color:  "#c0bc9e"

    // Click empty area to dismiss
    MouseArea { anchors.fill: parent; onClicked: Qt.quit() }

    // ── Power options (the selected item's desc drives the bottom-bar text) ──
    property var items: [
        { icon: "", label: "Lock",      desc: "Lock the session",             cmd: "/home/koios/.config/quickshell/nier-lock/quickshell-lockscreen/lock.sh" },
        { icon: "", label: "Logout",    desc: "End the session and log out",   cmd: "hyprctl dispatch 'hl.dsp.exit()'" },
        { icon: "", label: "Suspend",   desc: "Sleep, keeping state in RAM",   cmd: "systemctl suspend" },
        { icon: "", label: "Hibernate", desc: "Save state to disk and stop",   cmd: "systemctl hibernate" },
        { icon: "", label: "Shutdown",  desc: "Power off the machine",         cmd: "systemctl poweroff" },
        { icon: "", label: "Reboot",    desc: "Restart the machine",           cmd: "systemctl reboot" }
    ]
    property int sel: 0
    function runItem(i) { Quickshell.execDetached(["sh", "-c", root.items[i].cmd]); Qt.quit(); }

    Keys.onUpPressed:     root.sel = (root.sel - 1 + root.items.length) % root.items.length
    Keys.onDownPressed:   root.sel = (root.sel + 1) % root.items.length
    Keys.onReturnPressed: root.runItem(root.sel)
    Keys.onEnterPressed:  root.runItem(root.sel)
    Keys.onEscapePressed: Qt.quit()
    Component.onCompleted: root.forceActiveFocus()

    // Colors
    readonly property color nierBg:        "#c0bc9e"
    readonly property color nierDarker:    "#1a1814"
    readonly property color nierBorder:    "#706c58"
    readonly property color nierAccent:    "#d0cca8"
    readonly property color nierText:      "#2a2820"
    readonly property color nierDot:       "#524e3e"
    property color nierDark:       "#2a2820"
    property color nierTextMid:    "#706c58"
    property color nierSelected:   "#3e3c33"

    // Effect
    property real scanPos: 0
    NumberAnimation {
        target: root; property: "scanPos"; from: 0; to: 1; duration: 4000; loops: Animation.Infinite; running: true
    }

    property real  uiOpacity:    0
    property real  panelOffset:  40 * s
    property real  brandReveal:  0

    property string currentTime: Qt.formatTime(new Date(), "hh:mm")
    property string currentDate: Qt.formatDate(new Date(), "yyyy.MM.dd")

    // Theme ships no bundled font -> empty family = system default (as on the lock screen)
    readonly property string fontName: ""
    // Clock/date font — matches nierbar's date & time font
    readonly property string clockFont: "JetBrainsMono Nerd Font"

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            root.currentTime = Qt.formatTime(new Date(), "hh:mm")
            root.currentDate = Qt.formatDate(new Date(), "yyyy.MM.dd")
        }
    }

    Rectangle {
        anchors.fill: parent; color: root.nierBg

        Image {
            anchors.fill: parent
            source: shell.themeUrl + "bg.png"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true; opacity: 0.92
        }

        // Suble Background Grid
        Canvas {
            anchors.fill: parent; opacity: 0.04
            onPaint: {
                var ctx = getContext("2d"); ctx.strokeStyle = "#000000"; ctx.lineWidth = 1;
                var step = 40 * s
                // Offset so one vertical line lands exactly on the horizontal centre of the screen
                for (var x = (width / 2) % step; x < width; x += step) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke(); }
                for (var y = 0; y < height; y += step) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke(); }
            }
        }

        // Sweeping Global Scanner Beam
        Rectangle {
            width: parent.width; height: 1
            color: root.nierAccent; opacity: 0.2
            y: root.scanPos * parent.height
        }

        // Scrolling technical labels (Left Edge)
        Repeater {
            model: 8
            Text {
                property real ty: index * (root.height / 8) + 20 * s
                x: 10 * s; y: ty
                text: "SYNC_NODE_" + index + " // 0x" + (index * 255).toString(16).toUpperCase()
                font.family: root.fontName; font.pixelSize: 6 * s; color: root.nierText; opacity: 0.15
                transform: Rotation { angle: -90 }
                SequentialAnimation on y {
                    loops: Animation.Infinite
                    NumberAnimation { from: ty; to: ty - 60 * s; duration: 25000; easing.type: Easing.Linear }
                    NumberAnimation { from: ty + 60 * s; to: ty; duration: 0 }
                }
            }
        }

        // Static thin scanlines
        Canvas {
            anchors.fill: parent; opacity: 0.05
            onPaint: {
                var ctx = getContext("2d"); ctx.strokeStyle = "#000000"; ctx.lineWidth = 1;
                for (var y = 0; y < height; y += 3 * s) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke(); }
            }
        }
    }

    // ── DATA PANELS ─────────────────────────────────────────────────────────
    

    // Left decorative technical bar
    Rectangle {
        anchors.left: parent.left; anchors.leftMargin: 20 * s
        anchors.top: topBar.bottom; anchors.bottom: botBar.top
        width: 1; color: root.nierBorder; opacity: 0.3
    }

    // ── Animated floating data particles ─────────────────────────────────────
    Repeater {
        model: 22
        Item {
            id: dp
            property real px:   (index * 63.7) % root.width
            property real py:   root.height * 0.15 + (index * 41.3) % (root.height * 0.7)
            property int  dur:  18000 + (index % 7) * 1800
            property int  del:  (index % 11) * 700
            property real sz:   1 + (index % 3) * 0.6

            x: dp.px; y: dp.py

            SequentialAnimation on y {
                loops: Animation.Infinite
                PauseAnimation  { duration: dp.del }
                NumberAnimation { from: dp.py; to: dp.py - 220; duration: dp.dur; easing.type: Easing.Linear }
                NumberAnimation { duration: 0; to: dp.py }
            }
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                PauseAnimation  { duration: dp.del }
                NumberAnimation { from: 0; to: 0.5;  duration: dp.dur * 0.08 }
                NumberAnimation { from: 0.5; to: 0.5; duration: dp.dur * 0.72 }
                NumberAnimation { from: 0.5; to: 0;   duration: dp.dur * 0.20 }
            }
            Rectangle {
                width: dp.sz * s; height: dp.sz * s
                color: root.nierDot; opacity: 0.6
            }
        }
    }

    // ── Horizontal scan dashes ────────────────────────────────────────────────
    Repeater {
        model: 5
        Rectangle {
            id: sd
            property real sy:   root.height * 0.18 + index * (root.height * 0.16)
            property int  dur:  7000 + index * 900
            property int  del:  index * 500
            y: sd.sy; width: 55 * s + index * 18; height: 1
            color: root.nierDot; opacity: 0; x: -width
            SequentialAnimation on x {
                loops: Animation.Infinite
                PauseAnimation  { duration: sd.del }
                NumberAnimation { from: -sd.width; to: root.width + sd.width; duration: sd.dur; easing.type: Easing.Linear }
            }
            SequentialAnimation on opacity {
                loops: Animation.Infinite
                PauseAnimation  { duration: sd.del }
                NumberAnimation { from: 0;    to: 0.3;  duration: 150 }
                NumberAnimation { from: 0.3;  to: 0.3;  duration: sd.dur - 300 }
                NumberAnimation { from: 0.3;  to: 0;    duration: 150 }
            }
        }
    }

    // ── TOP HEADER BAR ───────────────────────────────────────────────────────
    Rectangle {
        id: topBar
        width: parent.width; height: 40 * s
        color: root.nierDarker

        // Decorative triangle rows
        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = "#524e3e"
                var step = 10 * s
                var count = Math.floor(width / step)
                var triSize = 3 * s
                for (var i = 0; i < count; i++) {
                    var x = i * step + 2 * s
                    // top row (downward triangles)
                    ctx.beginPath()
                    ctx.moveTo(x, 5 * s)
                    ctx.lineTo(x + triSize, 5 * s)
                    ctx.lineTo(x + triSize/2, 5 * s + triSize)
                    ctx.fill()
                    
                    // bottom row (upward triangles)
                    ctx.beginPath()
                    ctx.moveTo(x, 35 * s)
                    ctx.lineTo(x + triSize, 35 * s)
                    ctx.lineTo(x + triSize/2, 35 * s - triSize)
                    ctx.fill()
                }
            }
        }

        // Tab row
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10 * s
            spacing: 0

            Repeater {
                model: [
                    { name: "MAP" },
                    { name: "QUESTS" },
                    { name: "ITEMS" },
                    { name: "WEAPONS" },
                    { name: "LOGIN" },
                    { name: "INTEL" },
                    { name: "SYSTEM" }
                ]
                Rectangle {
                    id: tabBtn
                    property bool isActive: modelData.name === "SYSTEM"
                    property bool hovered: tMa.containsMouse
                    width:  tabContent.implicitWidth + 20 * s
                    height: topBar.height
                    color:  isActive ? root.nierSelected : (hovered ? "#4a4840" : "transparent")
                    border.color: (isActive || hovered) ? root.nierBorder : "transparent"
                    border.width: (isActive || hovered) ? 1 : 0
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: tabContent
                        anchors.centerIn: parent
                        spacing: 5 * s
                        Image {
                            id: tabIcon
                            source: shell.themeUrl + "svgs/" + modelData.name.toLowerCase() + ".svg"
                            sourceSize.height: 14 * s
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            anchors.verticalCenter: parent.verticalCenter
                            // Tint the flat #ADA895 svg to match the tab state, keeping
                            // the same hover/active colour logic the text icons had.
                            layer.enabled: true
                            layer.effect: ColorOverlay {
                                color: (tabBtn.isActive || tabBtn.hovered) ? root.nierAccent : root.nierBorder
                            }
                        }
                        Text {
                            text: modelData.name
                            font.family: root.fontName; font.pixelSize: 10 * s
                            font.letterSpacing: 2 * s
                            color: (tabBtn.isActive || tabBtn.hovered) ? root.nierAccent : root.nierBorder
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true }
                }
            }
        }
    }

    // ── BOTTOM STATUS BAR ────────────────────────────────────────────────────
    Rectangle {
        id: botBar
        width: parent.width; height: 36 * s
        anchors.bottom: parent.bottom
        color: root.nierDarker

        Canvas {
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = "#524e3e"
                var step = 10 * s
                var count = Math.floor(width / step)
                var triSize = 3 * s
                for (var i = 0; i < count; i++) {
                    var x = i * step + 2 * s
                    // top row
                    ctx.beginPath()
                    ctx.moveTo(x, 3 * s)
                    ctx.lineTo(x + triSize, 3 * s)
                    ctx.lineTo(x + triSize/2, 3 * s + triSize)
                    ctx.fill()
                    
                    // bottom row
                    ctx.beginPath()
                    ctx.moveTo(x, 33 * s)
                    ctx.lineTo(x + triSize, 33 * s)
                    ctx.lineTo(x + triSize/2, 33 * s - triSize)
                    ctx.fill()
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: 14 * s
            text: root.items[root.sel].desc || ""
            font.family: root.fontName; font.pixelSize: 11 * s
            font.letterSpacing: 0.5; color: root.nierAccent
        }

        // Key hint chips
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right; anchors.rightMargin: 14 * s
            spacing: 12 * s

            Repeater {
                model: [
                    { k: "↑↓",    l: "Select"  },
                    { k: "Enter", l: "Confirm"  },
                    { k: "Esc",   l: "Back"     }
                ]
                Row {
                    spacing: 4 * s
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        height: 15 * s; width: chip.implicitWidth + 8 * s
                        radius: 4 * s
                        color: "#2c2a24"
                        border.color: root.nierBorder; border.width: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            id: chip
                            anchors.centerIn: parent
                            text: modelData.k
                            font.family: root.fontName; font.pixelSize: 9 * s
                            color: root.nierAccent
                        }
                    }
                    Text {
                        text: modelData.l
                        font.family: root.fontName; font.pixelSize: 10 * s
                        color: root.nierBorder
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // ── MAIN UI ──────────────────────────────────────────────────────────────
    Item {
        id: ui
        anchors.top:    topBar.bottom
        anchors.bottom: botBar.top
        anchors.left:   parent.left
        anchors.right:  parent.right
        opacity: root.uiOpacity

        Component.onCompleted: SequentialAnimation {
            PauseAnimation  { duration: 400 }
            ParallelAnimation {
                NumberAnimation { target: root; property: "uiOpacity"; from: 0; to: 1; duration: 1200; easing.type: Easing.OutExpo }
                NumberAnimation { target: root; property: "panelOffset"; from: 60 * s; to: 0; duration: 1400; easing.type: Easing.OutExpo }
                NumberAnimation { target: root; property: "brandReveal"; from: 0; to: 1; duration: 1800; easing.type: Easing.OutQuart }
            }
            ScriptAction { script: missionTypewriter.start() }
        }


        // ── LEFT COLUMN: Login & Mission ─────────────────────────────────────
        Item {
            id: leftPanel
            anchors.top:    parent.top;    anchors.topMargin:    20 * s
            anchors.bottom: parent.bottom; anchors.bottomMargin: 24 * s
            anchors.left:   parent.left;   anchors.leftMargin:   70 * s - root.panelOffset
            width: 330 * s; opacity: root.uiOpacity

            // Vertical label "SYSTEM ACCESS"
            Text {
                text: "SYSTEM ACCESS"
                font.family: root.fontName; font.pixelSize: 8 * s; font.letterSpacing: 2
                color: root.nierTextMid; rotation: -90
                anchors.right: parent.left; anchors.rightMargin: 15 * s
                anchors.top: parent.top; anchors.topMargin: 40 * s
            }

            // "LOGIN" heading
            Item {
                id: heading
                width: parent.width; height: 62 * s

                Text {
                    id: headMain
                    text: "SYSTEM"
                    font.family: root.fontName; font.pixelSize: 32 * s
                    font.letterSpacing: 4 * s
                    font.bold: true
                    color: root.nierText
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 1 * s
                    anchors.left: parent.left; anchors.leftMargin: 0
                }
                Rectangle {
                    anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                    height: 1; color: root.nierBorder
                }
            }

            // Small dot strip below heading
            Canvas {
                anchors.top:  heading.bottom; anchors.topMargin: 3 * s
                anchors.left: parent.left;    anchors.right: parent.right
                height: 4 * s
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = "#524e3e"
                    for (var i = 0; i < 55; i++)
                        ctx.fillRect(i * 6 * s, 1 * s, 2 * s, 2 * s)
                }
            }

            // Power options list
            ListView {
                id: optionList
                anchors.top:    heading.bottom; anchors.topMargin: 12 * s
                anchors.bottom: missionBlock.top; anchors.bottomMargin: 24 * s
                anchors.left:   parent.left;    anchors.leftMargin: 0
                anchors.right:  parent.right
                model: root.items
                currentIndex: root.sel
                clip: true; spacing: 6 * s
                interactive: false
                highlight: Item {}  // disable default highlight

                delegate: Item {
                    id: rowItem
                    required property int index
                    required property var modelData
                    width: optionList.width; height: 42 * s

                    property bool sel:     root.sel === index
                    property bool hovered: rowMa.containsMouse

                    Item {
                        anchors.fill: parent
                        // Lighter hover slide
                        x: (rowItem.sel || rowItem.hovered) ? 4 * s : 0
                        Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

                        Rectangle {
                            anchors.fill: parent
                            color: rowItem.sel ? root.nierSelected
                                 : rowItem.hovered ? "#312f29" : "transparent"
                            border.color: rowItem.hovered ? root.nierBorder : "transparent"
                            border.width: rowItem.hovered ? 1 : 0
                            Behavior on color { ColorAnimation { duration: 150 } }

                            // Power icon (original NieR power-menu glyph)
                            Text {
                                text: rowItem.modelData.icon
                                font.family: "Symbols Nerd Font"; font.pixelSize: 15 * s
                                color: rowItem.sel || rowItem.hovered ? root.nierAccent : root.nierBorder
                                anchors.verticalCenter: parent.verticalCenter
                                x: 14 * s
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            // Label
                            Text {
                                text: rowItem.modelData.label.toUpperCase()
                                font.family: root.fontName; font.pixelSize: 14 * s
                                font.letterSpacing: 0.8
                                color: rowItem.sel || rowItem.hovered ? root.nierAccent : root.nierText
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left; anchors.leftMargin: 44 * s
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            // Separator
                            Rectangle {
                                anchors.bottom: parent.bottom; width: parent.width; height: 1
                                color: root.nierBorder; opacity: 0.35
                            }
                        }
                    }

                    MouseArea {
                        id: rowMa; anchors.fill: parent; hoverEnabled: true
                        onEntered: root.sel = rowItem.index
                        onClicked: root.runItem(rowItem.index)
                    }
                }
            }

            // Sliding NieR kite marking the selected option
            // (same component + movement animation as the old powermenu)
            SelectionKite {
                target: optionList.currentItem
                width: 24 * s; height: 13 * s
                gap: 12 * s
            }

            // ── BOTTOM LEFT: Mission & Data ───────────────────────────────────
            Item {
                id: missionBlock
                anchors.bottom: parent.bottom; anchors.bottomMargin: 14 * s
                width: parent.width; height: 210 * s

                Rectangle {
                    width: parent.width; height: 1; color: root.nierBorder; opacity: 0.4
                    anchors.top: parent.top
                }

                // Global Scanner Line - outside the layout column to avoid anchor conflicts
                Rectangle {
                    width: parent.width; height: 1
                    color: root.nierAccent; opacity: 0.15
                    y: 20 * s + (root.scanPos * 140 * s)
                }

                // Main Info Column
                Column {
                    anchors.top: parent.top; anchors.topMargin: 22 * s
                    anchors.left: parent.left; anchors.right: parent.right
                    spacing: 16 * s

                    // Title Section
                    Column {
                        width: parent.width; spacing: 4 * s
                        Text {
                            text: "CURRENT LOCATION: CITY RUINS [SECTOR 0-1]"
                            font.family: root.fontName; font.pixelSize: 8 * s
                            font.letterSpacing: 2; color: root.nierTextMid
                        }
                    }

                    // Objective Section
                    Column {
                        width: parent.width; spacing: 6 * s
                        Text {
                            text: "MISSION STATUS: ACTIVE"
                            font.family: root.fontName; font.pixelSize: 9 * s
                            font.letterSpacing: 1.5; color: root.nierText
                        }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap
                            property string fullText: "Objective: Eliminate the machine lifeforms and establish secure link to the Bunker."
                            text: ""
                            font.family: root.fontName; font.pixelSize: 10 * s; color: root.nierTextMid; lineHeight: 1.4

                            Timer {
                                id: missionTypewriter
                                interval: 15; repeat: true
                                property int charIdx: 0
                                onTriggered: {
                                    parent.text += parent.fullText[charIdx]
                                    charIdx++
                                    if (charIdx >= parent.fullText.length) stop()
                                }
                            }
                        }
                    }

                    // Pod Status Section
                    Column {
                        width: parent.width; spacing: 4 * s
                        Text {
                            text: "SYSTEM SYNCHRONIZATION: OPERATIONAL"
                            font.family: root.fontName; font.pixelSize: 7 * s; color: root.nierTextMid
                        }
                        Text {
                            text: "POD 042 / 153 SYNC: 98.4%"
                            font.family: root.fontName; font.pixelSize: 12 * s; color: "#4a8a4a"
                        }
                    }
                }
            }
        }

        // ── RIGHT COLUMN: Status (decorative only) ───────────────────────────
        Item {
            id: rightPanel
            anchors.top:    parent.top;    anchors.topMargin:    20 * s
            anchors.bottom: parent.bottom; anchors.bottomMargin: 24 * s
            anchors.right:  parent.right;  anchors.rightMargin:  70 * s - root.panelOffset
            width: 300 * s; opacity: root.uiOpacity

            // ── Status panel (static decoration) ──────────────────────────────
            Rectangle {
                id: statusBox
                anchors.top: parent.top; anchors.topMargin: 32 * s
                anchors.left: parent.left; anchors.right: parent.right
                height: 180 * s
                color: "transparent"; border.color: root.nierBorder; border.width: 1

                // Header
                Rectangle {
                    id: statusHdr; width: parent.width; height: 22 * s; color: root.nierDark
                    Text { anchors.left: parent.left; anchors.leftMargin: 12 * s; anchors.verticalCenter: parent.verticalCenter; text: "Status"; font.family: root.fontName; font.pixelSize: 13 * s; font.letterSpacing: 1.5; color: root.nierAccent }
                    Text { anchors.right: parent.right; anchors.rightMargin: 12 * s; anchors.verticalCenter: parent.verticalCenter; text: "Lv: 52"; font.family: root.fontName; font.pixelSize: 11 * s; color: root.nierAccent }
                }

                // Unit Profile Silhouette
                Rectangle {
                    id: unitIcon; anchors.top: statusHdr.bottom; anchors.topMargin: 10 * s; anchors.left: parent.left; anchors.leftMargin: 10 * s
                    width: 44 * s; height: 54 * s; color: "#312f29"; border.color: root.nierBorder; border.width: 1
                    Text { anchors.centerIn: parent; text: "2B"; font.family: root.fontName; font.pixelSize: 18 * s; color: root.nierAccent; opacity: 0.6 }
                }

                Column {
                    anchors.top: statusHdr.bottom; anchors.topMargin: 4 * s; anchors.left: unitIcon.right; anchors.leftMargin: 12 * s; anchors.right: parent.right; anchors.rightMargin: 12 * s; spacing: 0
                    Repeater {
                        model: [ { label: "Unit", value: "2 Type B" }, { label: "Funds", value: "682,847" }, { label: "EXP", value: "235,554" }, { label: "Auth", value: "Ok" } ]
                        Item {
                            width: parent.width; height: 18 * s
                            Text { text: modelData.label; font.family: root.fontName; font.pixelSize: 9 * s; color: root.nierTextMid; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: modelData.value; font.family: root.fontName; font.pixelSize: 9 * s; color: root.nierText; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right }
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.nierBorder; opacity: 0.2 }
                        }
                    }
                }

                // HP bar row
                Item {
                    anchors.bottom: noErr.top; anchors.bottomMargin: 8 * s; anchors.left: parent.left; anchors.leftMargin: 10 * s; anchors.right: parent.right; anchors.rightMargin: 10 * s; height: 26 * s
                    Text { text: "HP:"; font.family: root.fontName; font.pixelSize: 10 * s; color: root.nierTextMid; anchors.verticalCenter: parent.verticalCenter }
                    Text { anchors.right: hpTrack.left; anchors.rightMargin: 8 * s; anchors.verticalCenter: parent.verticalCenter; text: "3,950/ 3,950"; font.family: root.fontName; font.pixelSize: 9 * s; color: root.nierText }
                    Rectangle { id: hpTrack; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.45; height: 6 * s; color: "#2a2820"; border.color: root.nierBorder; border.width: 1; Rectangle { width: parent.width - 2; height: parent.height - 2; x: 1; y: 1; color: root.nierAccent; opacity: 0.8 } }
                }
                Text { id: noErr; anchors.bottom: parent.bottom; anchors.bottomMargin: 7 * s; anchors.horizontalCenter: parent.horizontalCenter; text: "SYSTEM STATE: NO ERROR"; font.family: root.fontName; font.pixelSize: 8 * s; font.letterSpacing: 2.5; color: root.nierBorder; opacity: 0.7 }
            }

            // ── BOTTOM TECHNICAL GROUP (decorative) ────────────────────────────
            Item {
                anchors.bottom: parent.bottom; anchors.bottomMargin: 15 * s
                anchors.right: parent.right
                width: 140 * s; height: 110 * s

                Column {
                    anchors.top: parent.top; anchors.right: parent.right
                    spacing: 12 * s

                    // ── HARDWARE MONITOR ───────────────────────────────────────────
                    Item {
                        id: hwMonitor; width: 140 * s; height: 50 * s
                        Column {
                            anchors.right: parent.right; spacing: 5 * s
                            Repeater {
                                model: [ { label: "CPU", val: "34%", bar: 0.34 }, { label: "MEM", val: "58%", bar: 0.58 }, { label: "HDD", val: "92%", bar: 0.92 } ]
                                Row {
                                    spacing: 8 * s; anchors.right: parent.right
                                    Text { text: modelData.label; font.family: root.fontName; font.pixelSize: 7 * s; color: root.nierTextMid; anchors.verticalCenter: parent.verticalCenter }
                                    Rectangle { width: 40 * s; height: 3 * s; color: "#2c2a24"; anchors.verticalCenter: parent.verticalCenter; Rectangle { width: parent.width * modelData.bar; height: parent.height; color: root.nierBorder } }
                                    Text { text: modelData.val; font.family: root.fontName; font.pixelSize: 7 * s; color: root.nierText; width: 22 * s; horizontalAlignment: Text.AlignRight }
                                }
                            }
                        }
                    }

                    // ── SATELLITE LINK MODULE ──────────────────────────────────────
                    Rectangle {
                        id: satelliteModule; width: 140 * s; height: 38 * s; color: "transparent"; border.color: root.nierBorder; border.width: 1

                        Column {
                            anchors.fill: parent; anchors.margins: 4 * s; spacing: 3 * s
                            Text { text: "SATELLITE LINK [BUNKER]"; font.family: root.fontName; font.pixelSize: 6 * s; color: root.nierTextMid; font.letterSpacing: 1 }
                            Row {
                                spacing: 8 * s
                                Rectangle { width: 26 * s; height: 16 * s; color: "#2c2a24"; Text { anchors.centerIn: parent; text: "LINK"; font.family: root.fontName; font.pixelSize: 7 * s; color: root.nierAccent } }
                                Text { text: "SECURE CH-04"; font.family: root.fontName; font.pixelSize: 7 * s; color: root.nierText; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                }
            }
        }


        // ── CENTER BRAND ────────────────────────────────────────────────────
        Item {
            id: centerBrand
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -30 * s
            width: 320 * s; height: 320 * s

            // Decorative rotating outer ring
            Rectangle {
                anchors.centerIn: parent
                width: 300 * s; height: 300 * s
                radius: width/2; color: "transparent"
                border.color: root.nierBorder; border.width: 1; opacity: 0.15
                
                Timer {
                    interval: 50; running: true; repeat: true
                    onTriggered: parent.rotation += 0.2
                }
            }
            
            // Counter-rotating Inner support ring
            Canvas {
                anchors.centerIn: parent
                width: 270 * s; height: 270 * s
                opacity: 0.1
                
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = root.nierBorder
                    ctx.lineWidth = 1
                    ctx.setLineDash([2 * s, 10 * s])
                    ctx.beginPath()
                    ctx.arc(width/2, height/2, width/2 - 0.5, 0, Math.PI*2)
                    ctx.stroke()
                }

                Timer {
                    interval: 50; running: true; repeat: true
                    onTriggered: parent.rotation -= 0.4
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top; anchors.topMargin: 10 * s
                spacing: 2 * s

                // ── CENTERED CLOCK ──
                Text {
                    text: "SYSTEM TIME // DATA SYNC"
                    font.family: root.fontName; font.pixelSize: 7 * s
                    color: root.nierAccent; font.letterSpacing: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: 0.6 * root.brandReveal
                }
                Text {
                    id: clockMainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.currentTime
                    font.family: root.clockFont; font.pixelSize: 42 * s
                    font.letterSpacing: 2; color: root.nierText;
                    opacity: 0.9 * root.brandReveal
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.currentDate
                    font.family: root.clockFont; font.pixelSize: 11 * s
                    font.letterSpacing: 4; color: root.nierTextMid
                    opacity: 0.7 * root.brandReveal
                }
                
                Item { width: 1; height: 16 * s } // Spacer

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "[ NieR:Automata ]"
                    font.family: root.fontName; font.pixelSize: 22 * s
                    font.letterSpacing: 6; color: root.nierText; opacity: root.brandReveal * 0.85
                    
                    // Left/Right Bracket flash — unfolding effect
                    Rectangle { 
                        anchors.left: parent.left; anchors.leftMargin: -30 * s + (18 * s * root.brandReveal)
                        anchors.verticalCenter: parent.verticalCenter; width: 4 * s; height: 12 * s * root.brandReveal; color: root.nierAccent; opacity: 0.3 
                    }
                    Rectangle { 
                        anchors.right: parent.right; anchors.rightMargin: -30 * s + (18 * s * root.brandReveal)
                        anchors.verticalCenter: parent.verticalCenter; width: 4 * s; height: 12 * s * root.brandReveal; color: root.nierAccent; opacity: 0.3 
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "YoRHa Operating System"
                    font.family: root.fontName; font.pixelSize: 9 * s
                    font.letterSpacing: 2.5; color: root.nierTextMid
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 200 * s; height: 1
                    color: root.nierBorder; opacity: 0.5
                }
            }

            // ── YoRHa emblem — SVG frame-by-frame animation (frames in YoRHa_logo/) ──
            // Double-buffered ping-pong player: two stacked images take turns loading
            // the next frame. The current frame stays visible until the next one is
            // fully Ready, so there is never a blank frame → no flicker. Under load it
            // drops frames instead of flashing.
            Item {
                id: emblem
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8 * s
                height: 130 * s
                width: height * 244 / 305   // frame aspect ratio (244 x 305)
                // Fade in with the rest of the UI; kept faint like the old compass
                opacity: 0.55 * root.brandReveal

                property int frame: 1
                readonly property int frameCount: 784
                readonly property int fps: 48
                property bool showA: true

                function frameUrl(f) {
                    return shell.themeUrl + "YoRHa_logo/frame_" + ("000" + f).slice(-4) + ".svg"
                }

                Image {
                    id: imgA
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    smooth: true; cache: true; asynchronous: true
                    sourceSize.height: 260
                    // opacity (not visible) so the layer FBO is never torn down/rebuilt
                    opacity: emblem.showA ? 1 : 0
                    layer.enabled: true
                    layer.effect: ColorOverlay { color: root.nierText }
                    // reveal myself once the frame I loaded while hidden is Ready
                    onStatusChanged: if (status === Image.Ready && !emblem.showA) emblem.showA = true
                }
                Image {
                    id: imgB
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    smooth: true; cache: true; asynchronous: true
                    sourceSize.height: 260
                    opacity: emblem.showA ? 0 : 1
                    layer.enabled: true
                    layer.effect: ColorOverlay { color: root.nierText }
                    onStatusChanged: if (status === Image.Ready && emblem.showA) emblem.showA = false
                }

                Component.onCompleted: imgA.source = frameUrl(frame)

                Timer {
                    interval: 1000 / emblem.fps
                    running: true; repeat: true
                    onTriggered: {
                        emblem.frame = emblem.frame % emblem.frameCount + 1
                        // load the next frame into whichever image is currently hidden
                        if (emblem.showA) imgB.source = emblem.frameUrl(emblem.frame)
                        else              imgA.source = emblem.frameUrl(emblem.frame)
                    }
                }
            }

            /* ── ORIGINAL: pulsing compass circle — kept for easy revert ──────────
            // YoRHa emblem — pulsing compass circle
            Canvas {
                id: emblem
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8 * s
                width: 110 * s; height: 110 * s

                property real pulse: 0
                SequentialAnimation on pulse {
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 1; duration: 2400; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1; to: 0; duration: 2400; easing.type: Easing.InOutSine }
                }
                onPulseChanged: requestPaint()

                // Slow rotation via transform
                property real rot: 0
                SequentialAnimation on rot {
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 360; duration: 40000; easing.type: Easing.Linear }
                }
                transform: Rotation {
                    origin.x: emblem.width / 2; origin.y: emblem.height / 2
                    angle: emblem.rot
                }

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    var cx  = width / 2
                    var cy  = height / 2
                    var r   = width * 0.40
                    var a   = 0.28 + emblem.pulse * 0.32

                    ctx.save()
                    ctx.strokeStyle = "rgba(42,40,32," + a + ")"
                    ctx.lineWidth   = 1

                    // Outer ring
                    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI*2); ctx.stroke()
                    // Middle ring
                    ctx.beginPath(); ctx.arc(cx, cy, r * 0.62, 0, Math.PI*2); ctx.stroke()
                    // Inner ring
                    ctx.beginPath(); ctx.arc(cx, cy, r * 0.28, 0, Math.PI*2); ctx.stroke()

                    // Crosshair lines
                    ctx.beginPath()
                    ctx.moveTo(cx - r * 1.1, cy); ctx.lineTo(cx + r * 1.1, cy)
                    ctx.moveTo(cx, cy - r * 1.1); ctx.lineTo(cx, cy + r * 1.1)
                    ctx.stroke()

                    // Tick marks (8)
                    for (var i = 0; i < 8; i++) {
                        var ang = (i / 8) * Math.PI * 2
                        var inner = i % 2 === 0 ? r - 7 : r - 4
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(ang) * inner, cy + Math.sin(ang) * inner)
                        ctx.lineTo(cx + Math.cos(ang) * r,     cy + Math.sin(ang) * r)
                        ctx.stroke()
                    }

                    // Center dot
                    ctx.fillStyle = "rgba(42,40,32," + (0.5 + emblem.pulse * 0.5) + ")"
                    ctx.beginPath(); ctx.arc(cx, cy, 3, 0, Math.PI*2); ctx.fill()

                    ctx.restore()
                }
            }
            ──────────────────────────────────────────────────────────────────── */
        }
    }

    }   // Rectangle root
    }   // PanelWindow win
}       // ShellRoot
