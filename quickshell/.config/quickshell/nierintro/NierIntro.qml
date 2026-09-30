// NieR:Automata style menu-open transition.
//
// Drop this over whatever the menu is opening on top of. It carves the screen
// with a diagonal lattice, floods it with beige triangles, wipes in the two
// ruler rails, and then hands the caller `tabsShown` / `bodyProgress` so the
// actual UI can build itself on the same beat.
//
// The triangle order is not random: it was read frame-by-frame out of the
// source footage and baked into fillorder.js, so every run looks identical and
// no run can draw an ugly distribution.

import QtQuick
import "fillorder.js" as Fill

Item {
    id: root

    // ── timeline ────────────────────────────────────────────────────────────
    // t=0 is the frame the HUD is cleared. Every constant is the source frame
    // number minus 20, in 23.976fps frames, which is what the footage does.
    readonly property real frameMs: 1000 / 23.976          // 41.708
    function _f(n) { return n * frameMs }

    readonly property real tLatticeEnd: _f(7)              // n=20..26 lines carve
    readonly property real tFillStart:  _f(7)              // n=27     first triangles
    readonly property real tFillEnd:    _f(15)             // n=35     last triangle
    readonly property real tRailStart:  _f(13)             // n=33     rails wipe in
    readonly property real tRailEnd:    _f(19)             // n=39     (overlaps the last triangles)
    readonly property real tTabStart:   _f(22)             // n=42     tabs pop in, one per frame
    readonly property real tTabEnd:     _f(28)             // n=48
    readonly property real tBodyStart:  _f(28)             // n=48     title/list/footer
    readonly property real tBodyEnd:    _f(31)             // n=51
    readonly property real duration:    tBodyEnd           // 1293ms

    // ── look ────────────────────────────────────────────────────────────────
    property color beige: "#c5c0a4"                        // sampled from the footage
    property color ink:   "#4a452f"
    property color latticeColor: "#e8e8e4"
    property real  latticeOpacity: 0.55
    property int   tabCount: 7

    // Turn the ruler rails off when the caller has chrome of its own at the
    // top and bottom; drive that chrome from railProgress instead.
    property bool  showRails: true

    // ── playback ────────────────────────────────────────────────────────────
    property real elapsed: 0
    property bool playing: false
    signal finished()

    // The first rendered frame pays for shader pipelines, FBOs and the first
    // Canvas paint - around 90ms cold. prepare() gets that out of the way; if
    // the caller hasn't, start() absorbs it by throwing away the first tick
    // instead of letting the transition begin mid-stall.
    property bool _warmed: false
    property bool _warming: false

    function prepare() {
        lattice.requestPaint()
        tri.requestPaint()
        _warmed = true
    }

    function start() {
        _warming = !_warmed
        clock.reset()
        elapsed = 0
        playing = true
    }
    function stop()       { playing = false }
    function seek(ms)     { playing = false; elapsed = ms }   // deterministic capture
    function skipToEnd()  { playing = false; elapsed = duration }

    FrameAnimation {
        id: clock
        running: root.playing
        onTriggered: {
            if (root._warming) { root._warming = false; root._warmed = true; reset(); return }
            var e = elapsedTime * 1000
            if (e >= root.duration) { root.elapsed = root.duration; root.playing = false; root.finished() }
            else root.elapsed = e
        }
    }

    // ── derived progress (read by this item and by the caller) ──────────────
    function _p(a, b) { return Math.max(0, Math.min(1, (elapsed - a) / (b - a))) }

    readonly property real latticeProgress: _p(0, tLatticeEnd)
    readonly property int  fillStep: elapsed < tFillStart
        ? -1 : Math.min(Fill.STEPS - 1, Math.floor((elapsed - tFillStart) / frameMs))
    // The rails do not wipe linearly - the footage eases them out.
    readonly property real railProgress: 1 - Math.pow(1 - _p(tRailStart, tRailEnd), 1.6)
    readonly property int  tabsShown: elapsed < tTabStart
        ? 0 : Math.min(tabCount, Math.floor((elapsed - tTabStart) / frameMs) + 1)
    readonly property real bodyProgress: _p(tBodyStart, tBodyEnd)

    // geometry shared by the lattice and the triangles: 9 rows, cell = H/9
    readonly property real cell: height / Fill.ROWS
    readonly property int  slots: Math.ceil(width / cell) + 1

    // ── 1. lattice ──────────────────────────────────────────────────────────
    // A subset of the triangle grid's own diagonals plus the two horizontals
    // that the rails will later land on, each extending from one end.
    Canvas {
        id: lattice
        anchors.fill: parent
        opacity: root.latticeOpacity * (1 - Math.max(0, root.fillStep + 1) / Fill.STEPS)
        visible: opacity > 0.01
        renderStrategy: Canvas.Cooperative

        // Baked so every run is identical: [family, index, delay 0..1].
        // family 1 = "\" (x = idx*cell + y), -1 = "/" (x = idx*cell - y).
        // Indices are even so the lines land on the triangle grid's own edges;
        // 4 and 12 are the pair that makes the big X through the middle, and
        // they go first, exactly as the footage does.
        readonly property var diagonals: [
            [ 1,   4, 0.00], [-1,  12, 0.00],
            [ 1,  -2, 0.16], [-1,  18, 0.20],
            [ 1,  10, 0.36], [-1,   8, 0.40],
            [ 1,  -8, 0.56], [-1,  24, 0.60],
            [ 1,  14, 0.72], [-1,   2, 0.76]
        ]

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = root.latticeColor
            ctx.lineWidth = Math.max(1, Math.round(height / 1080))
            var c = root.cell, p = root.latticeProgress

            // the two horizontals, drawn first and from opposite ends
            var rails = [[height * 0.100, 1], [height * 0.9389, -1]]
            for (var i = 0; i < rails.length; i++) {
                var g = Math.max(0, Math.min(1, p / 0.55))
                if (g <= 0) continue
                var y = Math.round(rails[i][0]) + 0.5
                ctx.beginPath()
                if (rails[i][1] > 0) { ctx.moveTo(0, y); ctx.lineTo(width * g, y) }
                else { ctx.moveTo(width, y); ctx.lineTo(width * (1 - g), y) }
                ctx.stroke()
            }

            // Diagonals grow along the part of the line that is actually on
            // screen, so one whose x-intercept sits off the left or right edge
            // still draws over the whole window of time instead of snapping in
            // at the very end.
            for (var d = 0; d < diagonals.length; d++) {
                var fam = diagonals[d][0], x0 = diagonals[d][1] * c, delay = diagonals[d][2]
                var g2 = Math.max(0, Math.min(1, (p - delay) / 0.30))
                if (g2 <= 0) continue
                var yIn, yOut
                if (fam > 0) { yIn = Math.max(0, -x0);         yOut = Math.min(height, width - x0) }
                else         { yIn = Math.max(0, x0 - width);  yOut = Math.min(height, x0) }
                if (yOut <= yIn) continue
                var yEnd = yIn + (yOut - yIn) * g2
                ctx.beginPath()
                ctx.moveTo(x0 + fam * yIn, yIn)
                ctx.lineTo(x0 + fam * yEnd, yEnd)
                ctx.stroke()
            }
        }
        Component.onCompleted: requestPaint()
        Connections {
            target: root
            function onLatticeProgressChanged() { if (lattice.visible) lattice.requestPaint() }
        }
    }

    // ── 2. triangles ────────────────────────────────────────────────────────
    // Painted incrementally: each step only adds its own shapes, so a step
    // costs 8..43 small fills rather than a full-screen repaint.
    Canvas {
        id: tri
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        property int painted: -1

        function rebuild() { painted = -1; requestPaint() }
        onWidthChanged: rebuild()
        onHeightChanged: rebuild()

        onPaint: {
            var ctx = getContext("2d")
            if (root.fillStep < painted) { ctx.reset(); painted = -1 }
            if (root.fillStep === painted) return

            var c = root.cell
            ctx.fillStyle = root.beige
            ctx.strokeStyle = root.beige          // closes the 1px AA seam
            ctx.lineWidth = 1

            for (var st = painted + 1; st <= root.fillStep; st++) {
                for (var r = 0; r < Fill.ROWS; r++) {
                    var yt = r * c, yb = yt + c
                    for (var s = 0; s < root.slots; s++) {
                        if (Fill.stepAt(r, s % Fill.SLOTS) !== st) continue
                        var xc = s * c
                        ctx.beginPath()
                        if ((r + s) % 2 === 0) {        // apex up
                            ctx.moveTo(xc, yt); ctx.lineTo(xc - c, yb); ctx.lineTo(xc + c, yb)
                        } else {                         // apex down
                            ctx.moveTo(xc - c, yt); ctx.lineTo(xc + c, yt); ctx.lineTo(xc, yb)
                        }
                        ctx.closePath()
                        ctx.fill()
                        ctx.stroke()
                    }
                }
            }
            painted = root.fillStep
        }
        Connections {
            target: root
            function onFillStepChanged() { tri.requestPaint() }
        }
    }

    // ── 3. vignette ─────────────────────────────────────────────────────────
    // Black with a baked alpha ramp lifted straight off the footage; sits over
    // both the beige and whatever is still showing through.
    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/vignette.png")
        fillMode: Image.Stretch
        smooth: true
        opacity: root.fillStep >= 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 80 } }
    }

    // ── 4. rails ────────────────────────────────────────────────────────────
    // Top rail wipes right-to-left, bottom rail left-to-right.
    Repeater {
        model: root.showRails ? [{ y: 0.100, ltr: false }, { y: 0.9389, ltr: true }] : []
        delegate: Item {
            id: railClip
            required property var modelData
            readonly property real k: root.height / 1080

            x: modelData.ltr ? 0 : root.width * (1 - root.railProgress)
            y: root.height * modelData.y - 4 * k
            width: root.width * root.railProgress
            height: 34 * k
            clip: true
            visible: root.railProgress > 0
            onVisibleChanged: if (visible) railCanvas.requestPaint()

            Canvas {
                id: railCanvas
                x: railClip.modelData.ltr ? 0 : -(root.width - railClip.width)
                width: root.width
                height: railClip.height
                renderStrategy: Canvas.Cooperative
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var u = railClip.k                           // 1 unit = 1px at 1080p
                    var ly = 4 * u                               // line sits 4u into the strip
                    ctx.fillStyle = root.ink

                    ctx.fillRect(0, ly - u, width, 2 * u)        // the hairline

                    var m = 72 * u                               // first/last dash inset
                    var n = Math.max(2, Math.round((width - 2 * m) / (77.17 * u)) + 1)
                    var pitch = (width - 2 * m) / (n - 1)
                    for (var i = 0; i < n; i++) {
                        var cx = m + i * pitch
                        ctx.fillRect(cx - 6 * u, ly - 2 * u, 12 * u, 6 * u)   // dash on the line
                        if (i === n - 1) continue
                        var gx = cx + pitch / 2                               // dot group between dashes
                        ctx.fillRect(gx - 11 * u, ly + 8 * u, 7 * u, 7 * u)
                        ctx.fillRect(gx + 4 * u, ly + 8 * u, 7 * u, 7 * u)
                        ctx.fillRect(gx - 3 * u, ly + 20 * u, 6 * u, 6 * u)
                    }
                }
                Component.onCompleted: requestPaint()
            }
        }
    }
}
