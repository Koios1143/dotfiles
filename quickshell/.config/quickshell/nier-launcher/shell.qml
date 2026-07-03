// =============================================================================
//  NieR:Automata launcher  —  Quickshell (standalone, real data)
//    - reads real .desktop entries via DesktopEntries, themed colour icons
//    - Enter / click launches the app; Esc or click-outside closes
//    - calc mode (expr or "=expr") evaluated via qalc, debounced
//  Resident daemon, toggled via IPC. Install as a named config:
//      ~/.config/quickshell/nier-launcher/shell.qml   (+ kite.svg beside it)
//  Run (Hyprland autostart):  exec-once = qs -c nier-launcher
//  Toggle (Hyprland keybind): qs -c nier-launcher ipc call launcher toggle
//  Closes on: Esc, click-outside, or focus loss. Each open resets search +
//  selection; per-app usage counts persist across opens and reboots.
//  Deps:  qalc (libqalculate) for the calculator; wl-clipboard for copy;
//         an icon theme for app icons
//
//  Icons use the Qt platform theme by default (matches your other Qt apps).
//  To pin a colour theme, add at the very top of this file:
//      //@ pragma IconTheme Papirus     (any installed theme name)
// =============================================================================

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: root

    // ---- theme (dark NieR, matches nier-clipboard) -------------------------
    readonly property string face:    "FOT-Rodin Pro"
    readonly property color  bg:        "#1a1813"
    readonly property color  bg2:       "#131210"
    readonly property color  rowBg:     "#211e18"
    readonly property color  sel:       "#2d2920"
    readonly property color  selLine:   "#d99b45"
    readonly property color  selInk:    "#ece6da"
    readonly property color  ink:       "#d7d0c4"
    readonly property color  muted:     "#8a8377"
    readonly property color  rail:      "#5b5649"
    readonly property color  accent:    "#d99b45"
    readonly property color  frame:     "#5b5649"
    readonly property color  frameSoft: Qt.rgba(91/255, 86/255, 73/255, 0.55)

    // content side inset: the mockup centres a 760px column inside the 800px
    // card (~20px each side) so the left rails breathe away from the border
    readonly property int    inset:   20
    // row block height (taller = roomier) and the gap that floats the selected
    // row's top/bottom lines away from the coloured block (mockup: 6px padding)
    readonly property int    rowH:    50
    readonly property int    rowPad:  6

    // latest qalc result (filled async by calcProc); "" while pending/idle
    property string calcResult: ""

    // ---- usage frequency (persisted): { appKey: launchCount } -------------
    property var usage: ({})
    function appKey(a)   { return (a && (a.id || a.name)) || ""; }
    function usageOf(a)  { return root.usage[root.appKey(a)] || 0; }
    function parseUsage(t) {
        try { var o = JSON.parse(t || "{}"); return (o && typeof o === "object") ? o : ({}); }
        catch (e) { return ({}); }
    }
    function bumpUsage(a) {
        var k = root.appKey(a); if (!k) return;
        var u = Object.assign({}, root.usage);   // new ref so bindings re-run
        u[k] = (u[k] || 0) + 1;
        root.usage = u;
        usageFile.setText(JSON.stringify(u));
    }
    FileView {
        id: usageFile
        path: Quickshell.statePath("nier-launcher-usage.json")
        blockLoading: true
        printErrors: false
        onLoaded: root.usage = root.parseUsage(usageFile.text())
    }

    // ---- calc detection: "=expr", or a number-led arithmetic expression ----
    function calcExpr(q) {
        q = (q || "").trim();
        if (q.charAt(0) === "=") return { isCalc: true, expr: q.slice(1).trim() };
        if (q.length > 0 && /^[\d.(]/.test(q) && /[-+*/%^]/.test(q))
            return { isCalc: true, expr: q };
        return { isCalc: false, expr: "" };
    }

    // ---- fuzzy scorer: -Infinity if not a subsequence, else higher=better -
    function fuzzyScore(needle, hay) {            // both already lower-cased
        if (needle.length === 0) return 0;
        var score = 0, hi = 0, prev = -2, consec = 0;
        for (var ni = 0; ni < needle.length; ni++) {
            var ch = needle[ni], found = -1;
            for (var hj = hi; hj < hay.length; hj++) {
                if (hay[hj] === ch) { found = hj; break; }
            }
            if (found === -1) return -Infinity;            // not a subsequence
            var pts = 1;
            if (found === 0) pts += 6;                      // very start
            else {
                var p = hay[found - 1];
                if (p === " " || p === "-" || p === "_" || p === "." || p === "/")
                    pts += 4;                               // word boundary
            }
            if (found === prev + 1) { consec++; pts += 2 + consec; } else consec = 0;
            pts -= (found - hi) * 0.15;                     // gap penalty
            score += pts; prev = found; hi = found + 1;
        }
        return score - hay.length * 0.02;                   // slight short-name bias
    }

    // ---- model: calc row, OR fuzzy-filtered apps sorted by usage then score
    function buildList(q) {
        var c = root.calcExpr(q);
        if (c.isCalc && c.expr.length > 0) {
            return [{ calc: true, expr: c.expr,
                      name: c.expr + "   =   " + (root.calcResult.length ? root.calcResult : "…") }];
        }
        var apps = DesktopEntries.applications.values;
        var ql = (q || "").trim().toLowerCase();
        var scored = [];
        for (var i = 0; i < apps.length; i++) {
            var a = apps[i], nm = (a.name || ""), sc = 0;
            if (ql !== "") {
                sc = root.fuzzyScore(ql, nm.toLowerCase());
                if (sc === -Infinity) continue;             // drop non-candidates
            }
            scored.push({ app: a, score: sc, used: root.usageOf(a), name: nm.toLowerCase() });
        }
        scored.sort(function (x, y) {
            if (y.used !== x.used)   return y.used - x.used;        // 1) usage desc
            if (ql === "")           return x.name.localeCompare(y.name);   // empty -> alpha
            if (y.score !== x.score) return y.score - x.score;     // 2) fzy desc
            return x.name.localeCompare(y.name);                   // final tiebreak
        });
        return scored.map(function (s) { return s.app; });
    }

    // ---- resident open/close: each open starts fresh, usage persists -------
    property bool armed: false        // ignore focus changes briefly after open
    Timer { id: armTimer; interval: 150; onTriggered: root.armed = true }

    // cyclenext (and other programmatic focus moves) don't clear the focus grab,
    // so also close when Hyprland's active window changes while we're open.
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            if (win.visible && root.armed) root.hide();
        }
    }

    function show() {
        search.text = "";              // don't keep last query
        root.calcResult = "";
        list.currentIndex = 0;         // focus back to the top entry
        list.positionViewAtBeginning();
        root.armed = false;            // skip the open-transition focus change
        armTimer.restart();
        win.visible = true;            // becoming visible replays the intro (see onVisibleChanged)
        grab.active = true;            // arm focus-loss dismissal
        Qt.callLater(function () { search.forceActiveFocus(); });
    }
    function hide() {
        root.armed = false;
        grab.active = false;
        win.visible = false;
    }
    function toggle() { if (win.visible) root.hide(); else root.show(); }

    // called from Hyprland: `qs -c nier-launcher ipc call launcher toggle`
    IpcHandler {
        target: "launcher"
        function toggle(): void { root.toggle(); }
        function show():   void { root.show(); }
        function hide():   void { root.hide(); }
    }

    function activate(idx) {
        var m = list.model[idx];
        if (!m) return;
        if (m.calc) {                                   // Enter on calc row -> copy
            if (root.calcResult.length)
                Quickshell.execDetached(["wl-copy", "--", root.calcResult]);
            root.hide();
            return;
        }
        root.bumpUsage(m);                              // record launch
        m.execute();                                    // launch the app
        root.hide();                                    // just hide; daemon stays
    }

    // ---- qalc bridge: debounced, terse output ------------------------------
    Process {
        id: calcProc
        stdout: StdioCollector { onStreamFinished: root.calcResult = this.text.trim() }
    }
    Timer {
        id: calcDebounce
        interval: 140
        onTriggered: {
            var c = root.calcExpr(search.text);
            if (c.isCalc && c.expr.length > 0) {
                root.calcResult = "";                       // show "…" until result
                calcProc.command = ["qalc", "-t", c.expr];
                calcProc.running = true;
            } else {
                root.calcResult = "";
            }
        }
    }

    // ========================================================================
    PanelWindow {
        id: win
        visible: false                 // resident: start hidden, toggled via IPC
        color: "transparent"
        // replay the open animations every time the window becomes visible
        onVisibleChanged: if (visible) card.playIntro()
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        // OnDemand (not Exclusive): the focus grab routes the keyboard here while
        // open, but focus can still move away (e.g. cyclenext) — which clears the
        // grab and closes us. Exclusive would monopolise the keyboard and block that.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "nier-launcher"

        // close when the compositor takes focus away (workspace switch, another
        // window/keybind stealing focus, etc.). Esc and click-outside also close.
        HyprlandFocusGrab {
            id: grab
            windows: [win]
            onCleared: root.hide()
        }

        // click-outside to dismiss (card swallows its own clicks below)
        MouseArea { anchors.fill: parent; onClicked: root.hide() }

        // -------------------------------------------------------------- card
        Rectangle {
            id: card
            width: 800
            height: 556
            anchors.centerIn: parent
            color: "transparent"
            MouseArea { anchors.fill: parent }   // absorb clicks on the card

            // ---- open-intro state (re-played on every show()) --------------
            property real intro: 0                       // octagon frame draw-on
            readonly property real lineProg:             // straight lines, slight delay
                Math.max(0, Math.min(1, (intro - 0.2) / 0.8))
            property real railIn: 0                      // left axis slide-in (0 = off-left)
            property real kiteFade: 0                    // kite arrow fade-in
            property string titleText: "APPLICATIONS"    // decoded title (reveals L->R)
            property real titleDecode: 0                 // animated 0->len, drives lock progression
            property int titleLocked: 0                  // chars settled so far (= floor(titleDecode))

            NumberAnimation { id: introAnim; target: card; property: "intro"
                              from: 0; to: 1; duration: 480; easing.type: Easing.OutCubic }
            NumberAnimation { id: railAnim;  target: card; property: "railIn"
                              from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic }
            SequentialAnimation {
                id: kiteAnim
                PauseAnimation { duration: 150 }         // let the axis arrive first
                NumberAnimation { target: card; property: "kiteFade"
                                  from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
            }

            // title decode: a single flickering cursor walks left->right. Chars
            // behind it are locked to APPLICATIONS, chars ahead aren't shown yet.
            // Everything is driven off this one animation (titleDecode 0->len): it's
            // paced by the frame clock, so both the reveal AND the flicker advance by
            // real elapsed time and stay even even while the open animations hog the
            // event loop. (A plain Timer gets starved during the intro and snaps.)
            readonly property string glyphs: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            NumberAnimation {
                id: decodeAnim; target: card; property: "titleDecode"
                from: 0; to: 12; duration: 780; easing.type: Easing.Linear
            }
            onTitleDecodeChanged: {
                var full = "APPLICATIONS";
                card.titleLocked = Math.min(full.length, Math.floor(card.titleDecode));
                if (card.titleLocked >= full.length) {
                    card.titleText = full;                 // fully decoded
                } else {
                    // locked prefix + one flickering random A-Z / a-z / 0-9 glyph;
                    // fires once per frame, so the active char shimmers smoothly
                    var g = card.glyphs[Math.floor(Math.random() * card.glyphs.length)];
                    card.titleText = full.substring(0, card.titleLocked) + g;
                }
            }

            function playIntro() {
                card.intro = 0; card.railIn = 0; card.kiteFade = 0;
                introAnim.restart(); railAnim.restart(); kiteAnim.restart();
                card.titleDecode = 0; card.titleLocked = 0; card.titleText = "";
                decodeAnim.restart();
            }

            // octagon panel: dark fill + clipped damage grid + the #5b5649 frame
            Canvas {
                anchors.fill: parent
                property int ch: 16
                property real prog: card.intro          // frame draw-on progress
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onProgChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d"); c.clearRect(0, 0, width, height);
                    var w = width, h = height, k = ch;
                    function oct() {
                        c.beginPath();
                        c.moveTo(k, 1); c.lineTo(w - k, 1); c.lineTo(w - 1, k);
                        c.lineTo(w - 1, h - k); c.lineTo(w - k, h - 1); c.lineTo(k, h - 1);
                        c.lineTo(1, h - k); c.lineTo(1, k); c.closePath();
                    }
                    var g = c.createLinearGradient(0, 0, 0, h);
                    g.addColorStop(0, root.bg); g.addColorStop(1, root.bg2);
                    oct(); c.fillStyle = g; c.fill();
                    c.save(); oct(); c.clip();
                    function grid(step, a) {
                        c.strokeStyle = "rgba(215,208,196," + a + ")"; c.lineWidth = 1; c.beginPath();
                        for (var x = 0; x <= w; x += step) { c.moveTo(x + 0.5, 0); c.lineTo(x + 0.5, h); }
                        for (var y = 0; y <= h; y += step) { c.moveTo(0, y + 0.5); c.lineTo(w, y + 0.5); }
                        c.stroke();
                    }
                    grid(6, "0.02"); grid(24, "0.035");
                    c.restore();
                    // frame draws on: reveal a single growing dash from the start point
                    var per = 2 * (w - 2 * k) + 2 * (h - 2 * k) + 4 * (k - 1) * Math.SQRT2;
                    c.setLineDash([per * prog, per + 2]);
                    oct(); c.strokeStyle = root.frame; c.lineWidth = 1.5; c.stroke();
                    c.setLineDash([]);
                }
            }

            // -------------------------------------------------- header (title)
            Item {   // YoRHa emblem: manual sprite-sheet loop (we drive the wrap, so no AnimatedSprite blank flicker)
                id: logo
                x: root.inset + 4; y: 10
                height: 42; width: height * 58/72
                clip: true
                property int frame: 0
                readonly property int cols: 7        // yorha_anim.png is a 7x49 grid of 58x72 cells (343 frames)
                readonly property int rows: 49
                readonly property int frames: 343
                readonly property int step: 2        // advance 2 frames/tick: real 30fps motion at only 15 repaints/sec
                Image {                              // atlas decoded once; translated under the clip to show one cell
                    source: Qt.resolvedUrl("yorha_anim.png")
                    sourceSize: Qt.size(406, 3528)
                    width: logo.width * logo.cols; height: logo.height * logo.rows
                    x: -(logo.frame % logo.cols) * logo.width
                    y: -Math.floor(logo.frame / logo.cols) * logo.height
                    smooth: true
                }
                // Each repaint redraws the whole overlay, so CPU scales with the tick rate, not the motion speed.
                // 15 ticks/sec ~3% of one core (only while open; 0 when hidden); step keeps the motion at full 30fps speed.
                Timer {
                    interval: 1000 / 15; repeat: true; running: win.visible
                    onTriggered: logo.frame = (logo.frame + logo.step) % logo.frames
                }
            }
            Rectangle {   // divider
                x: root.inset + 44; y: 15; width: 1; height: 30 * card.lineProg; color: root.frameSoft
            }
            Text {   // shadow
                x: root.inset + 60.5; y: 19.5
                text: card.titleText; font.family: root.face; font.weight: Font.DemiBold
                font.pixelSize: 23; font.letterSpacing: 1.5
                color: Qt.rgba(0, 0, 0, 0.45)
            }
            Text {   // ink
                id: title
                x: root.inset + 59; y: 18
                text: card.titleText; font.family: root.face; font.weight: Font.DemiBold
                font.pixelSize: 23; font.letterSpacing: 1.5; color: root.ink
            }
            Text {   // live count
                anchors.left: title.right; anchors.leftMargin: 13
                anchors.baseline: title.baseline
                text: list.count + " entries"
                font.family: root.face; font.pixelSize: 11; font.letterSpacing: 1.5
                color: root.muted
            }

            // header underline
            Rectangle { x: root.inset; y: 56; width: (card.width - 2 * root.inset) * card.lineProg; height: 1; color: root.frameSoft }

            // ----------------------------------------------------- search box
            Rectangle {
                id: searchBox
                x: root.inset + 46; y: 70
                width: card.width - 2 * root.inset - 46 - 42; height: 40
                color: "#23201a"; border.color: root.frameSoft; border.width: 1

                // single caret = the TextInput's own cursor, sitting at the left;
                // typing flows from it (no second blinking cursor)
                Text {
                    visible: search.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    x: search.x
                    text: "Search apps or type a calculation…"
                    color: root.muted; font.family: root.face; font.pixelSize: 14
                }

                TextInput {
                    id: search
                    anchors.verticalCenter: parent.verticalCenter
                    x: 14
                    width: parent.width - x - 13
                    focus: true; clip: true
                    color: root.ink; font.family: root.face; font.pixelSize: 14
                    selectionColor: root.accent

                    onTextChanged: { list.currentIndex = 0; calcDebounce.restart() }
                    Keys.onEscapePressed: root.hide()
                    Keys.onUpPressed:   list.currentIndex = Math.max(0, list.currentIndex - 1)
                    Keys.onDownPressed: list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1)
                    Keys.onReturnPressed: root.activate(list.currentIndex)
                    Keys.onEnterPressed:  root.activate(list.currentIndex)

                    // thin accent caret with a hard-step blink (~steps(1))
                    cursorDelegate: Rectangle {
                        width: 2; color: root.accent
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { to: 1; duration: 0 }
                            PauseAnimation  { duration: 530 }
                            NumberAnimation { to: 0; duration: 0 }
                            PauseAnimation  { duration: 530 }
                        }
                    }
                }
            }

            // ----------------------------------------------------- list region
            Item {
                id: listRegion
                clip: true                         // axis rails slide in from the left edge
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: searchBox.bottom; anchors.topMargin: 12
                anchors.bottom: parent.bottom; anchors.bottomMargin: 26

                // top / bottom rules
                Rectangle { x: root.inset + 46; width: (parent.width - 2 * root.inset - 88) * card.lineProg; height: 1; color: root.rail; anchors.top: parent.top }
                Rectangle { x: root.inset + 46; width: (parent.width - 2 * root.inset - 88) * card.lineProg; height: 1; color: root.rail; anchors.bottom: parent.bottom }

                // left rails (thick + thin) — the kite's fixed axis; slides in from the left
                Rectangle { x: (root.inset + 8)  - (1 - card.railIn) * 70; width: 8; color: root.rail
                            anchors.top: parent.top; anchors.bottom: parent.bottom
                            anchors.topMargin: 4; anchors.bottomMargin: 4 }
                Rectangle { x: (root.inset + 23) - (1 - card.railIn) * 70; width: 2; color: root.rail
                            anchors.top: parent.top; anchors.bottom: parent.bottom
                            anchors.topMargin: 4; anchors.bottomMargin: 4 }

                // the rows
                ListView {
                    id: list
                    anchors.fill: parent
                    anchors.leftMargin: root.inset + 46; anchors.rightMargin: root.inset + 42
                    anchors.topMargin: 12; anchors.bottomMargin: 12
                    clip: true
                    spacing: 5
                    model: root.buildList(search.text)
                    currentIndex: 0
                    boundsBehavior: Flickable.StopAtBounds
                    // selected row grows/shrinks (reflow), so defer positioning
                    // until that height change has applied; snap fully at the edges
                    function ensureVisible() {
                        if (currentIndex <= 0)            positionViewAtBeginning();
                        else if (currentIndex >= count-1) positionViewAtEnd();
                        else positionViewAtIndex(currentIndex, ListView.Contain);
                    }
                    onCurrentIndexChanged: Qt.callLater(ensureVisible)
                    onCountChanged: if (currentIndex >= count) currentIndex = Math.max(0, count - 1)

                    // mouse-wheel scrolling (row MouseAreas would otherwise swallow it)
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        property real speed: 0.6      // <1 = slower scrolling
                        onWheel: function (event) {
                            const max = Math.max(0, list.contentHeight - list.height);
                            list.contentY = Math.max(0, Math.min(max, list.contentY - event.angleDelta.y * speed));
                        }
                    }

                    delegate: Item {
                        id: rowRoot
                        required property var modelData
                        required property int index
                        readonly property bool isSel: ListView.isCurrentItem
                        width: ListView.view ? ListView.view.width : 0
                        // selected row grows by rowPad on each side so its lines
                        // float above/below the coloured block
                        // constant height (reserve the pad whether selected or not) so
                        // moving the selection never reflows neighbouring rows
                        height: root.rowH + 2 * root.rowPad

                        // floating top & bottom black lines (only when selected)
                        Rectangle { visible: rowRoot.isSel; anchors.top: parent.top
                                    width: parent.width; height: 2; color: root.selLine }
                        Rectangle { visible: rowRoot.isSel; anchors.bottom: parent.bottom
                                    width: parent.width; height: 2; color: root.selLine }

                        // the coloured block, centred so the lines sit rowPad away
                        Rectangle {
                            id: fill
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: root.rowH
                            color: rowRoot.isSel ? root.sel : root.rowBg
                            border.width: rowRoot.isSel ? 0 : 1
                            border.color: Qt.rgba(215/255, 208/255, 196/255, 0.10)

                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                onEntered: list.currentIndex = rowRoot.index
                                onClicked: root.activate(rowRoot.index)
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 16; anchors.rightMargin: 16
                                spacing: 13
                                // icon slot: calc row = accent '=' chip, app row = themed icon
                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 26; height: 26
                                    Rectangle {
                                        visible: rowRoot.modelData.calc === true
                                        anchors.fill: parent; radius: 4; color: root.sel
                                        Text {
                                            anchors.centerIn: parent; text: "="
                                            color: root.selInk; font.family: root.face
                                            font.pixelSize: 14; font.bold: true
                                        }
                                    }
                                    Image {
                                        visible: rowRoot.modelData.calc !== true
                                        anchors.fill: parent
                                        asynchronous: true; smooth: true
                                        fillMode: Image.PreserveAspectFit
                                        sourceSize.width: 52; sourceSize.height: 52
                                        source: Quickshell.iconPath(
                                                    rowRoot.modelData.icon || "application-x-executable",
                                                    "application-x-executable")
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: fill.width - 16 - 16 - 26 - 13
                                    text: rowRoot.modelData.name
                                    color: rowRoot.isSel ? root.selInk : root.ink
                                    font.family: root.face; font.pixelSize: 15
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // -------- THE KITE: slides to the current row ----------------
                Image {
                    id: kite
                    source: Qt.resolvedUrl("kite.svg")
                    width: 34; height: 18; smooth: true
                    opacity: card.kiteFade              // fades in once the axis has slid in
                    // ring (local x~9) lands in the gap between thick rail
                    // (inset+8..16) and thin rail (inset+23) so neither bisects it
                    x: root.inset + 10
                    visible: list.count > 0 && list.currentItem !== null
                    y: {
                        var _dep = list.contentY;            // re-eval on scroll
                        if (!list.currentItem) return kite.y;
                        var p = list.currentItem.mapToItem(listRegion, 0, 0);
                        return p.y + list.currentItem.height / 2 - height / 2;
                    }
                    Behavior on y { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                }

                // ---------------- scrollbar (handle tracks visibleArea) ------
                Item {
                    id: sb
                    width: 6
                    anchors.right: parent.right; anchors.rightMargin: root.inset + 23
                    anchors.top: parent.top; anchors.bottom: parent.bottom
                    anchors.topMargin: 14; anchors.bottomMargin: 14
                    Rectangle {
                        width: parent.width; color: root.muted
                        height: Math.max(24, sb.height * list.visibleArea.heightRatio)
                        y: list.visibleArea.yPosition * sb.height
                    }
                }
                Rectangle { width: 6; height: 6; radius: 3; color: root.muted
                            anchors.right: parent.right; anchors.rightMargin: root.inset + 23; anchors.top: parent.top }
                Rectangle { width: 6; height: 6; radius: 3; color: root.muted
                            anchors.right: parent.right; anchors.rightMargin: root.inset + 23; anchors.bottom: parent.bottom }
            }
        }
    }
}
