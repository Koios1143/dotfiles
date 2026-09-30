// Deterministic frame dumper: steps NierIntro to an exact time and writes a
// PNG, so the result can be diffed against the source footage without any
// compositor or recording jitter in the way.
//
// Needs a GPU scene graph (the offscreen platform falls back to the software
// renderer, which draws nothing for ShaderEffect). A headless weston works:
//
//   weston --backend=headless --renderer=gl --width=1920 --height=1080 \
//          --socket=wayland-cap &
//   WAYLAND_DISPLAY=wayland-cap QT_QPA_PLATFORM=wayland \
//     qml6 Capture.qml -- <outDir> <backdrop.png> [fps]
//
// With no fps it captures exactly the source frames n=20..52 at 23.976fps and
// names them Qnnn.png to line up with the reference frames; with an fps it
// captures the whole transition at that rate as C%04d.png.

import QtQuick

Window {
    id: win
    visible: true
    width: 1920
    height: 1080
    color: "#000000"

    readonly property var argv: Qt.application.arguments
    readonly property real fps: {
        var last = argv[argv.length - 1]
        var n = parseFloat(last)
        return (!isNaN(n) && n > 0 && last.indexOf("/") < 0) ? n : 0
    }
    readonly property int argBase: fps > 0 ? argv.length - 3 : argv.length - 2
    readonly property string outDir: argv[argBase]
    readonly property string backdrop: argv[argBase + 1]

    // source-aligned mode captures n=20..52; fps mode covers the whole duration
    readonly property int frameCount: fps > 0
        ? Math.ceil(intro.duration / 1000 * fps) + 1
        : 33

    property int i: 0
    property bool busy: false

    Item {
        id: stage
        width: 1920
        height: 1080

        NierBackdrop {
            anchors.fill: parent
            amount: intro.latticeProgress
            Image {
                anchors.fill: parent
                source: "file://" + win.backdrop
                fillMode: Image.Stretch
            }
        }

        NierIntro { id: intro; anchors.fill: parent }
    }

    function timeFor(i) { return win.fps > 0 ? i * 1000 / win.fps : i * intro.frameMs }
    function nameFor(i) {
        return win.fps > 0
            ? win.outDir + "/C" + ("000" + i).slice(-4) + ".png"
            : win.outDir + "/Q" + ("00" + (i + 20)).slice(-3) + ".png"
    }

    Timer {
        interval: 120
        repeat: true
        running: true
        onTriggered: {
            if (win.busy) return
            if (win.i >= win.frameCount) { Qt.quit(); return }
            win.busy = true
            intro.seek(win.timeFor(win.i))
            settle.restart()
        }
    }

    // give the Canvases a couple of frames to actually paint before grabbing
    Timer {
        id: settle
        interval: 80
        onTriggered: {
            stage.grabToImage(function (res) {
                res.saveToFile(win.nameFor(win.i))
                win.i++
                win.busy = false
            }, Qt.size(1920, 1080))
        }
    }
}
