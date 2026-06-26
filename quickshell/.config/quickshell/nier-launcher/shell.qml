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

    // ---- theme -------------------------------------------------------------
    readonly property string face:    "FOT-Rodin Pro"
    readonly property color  bg:      "#c7c3ab"
    readonly property color  rowBg:   "#d6d2bf"
    readonly property color  sel:     "#37352e"
    readonly property color  selLine: "#26241f"
    readonly property color  selInk:  "#dad6c1"
    readonly property color  ink:     "#43413a"
    readonly property color  muted:   "#6d6a59"
    readonly property color  rail:    "#9d9a85"
    readonly property color  accent:  "#b5933f"   // amber | teal #74a89c | red #b0432a

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
        win.visible = true;
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
            color: root.bg
            border.color: "#6f6c5a"
            border.width: 1
            MouseArea { anchors.fill: parent }   // absorb clicks on the card

            // mesh grid (6px fine + 24px coarse), inset 5px
            Canvas {
                anchors.fill: parent
                anchors.margins: 5
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    function grid(step, style) {
                        ctx.strokeStyle = style; ctx.lineWidth = 1;
                        ctx.beginPath();
                        for (var x = 0; x <= width;  x += step) { ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, height); }
                        for (var y = 0; y <= height; y += step) { ctx.moveTo(0, y + 0.5); ctx.lineTo(width, y + 0.5); }
                        ctx.stroke();
                    }
                    grid(6,  "rgba(67,65,58,0.03)");
                    grid(24, "rgba(67,65,58,0.05)");
                }
            }

            // inner border
            Rectangle {
                anchors.fill: parent; anchors.margins: 5
                color: "transparent"
                border.color: Qt.rgba(67/255, 65/255, 58/255, 0.32); border.width: 1
            }

            // four corner brackets
            component Corner: Item {
                width: 11; height: 11
                property bool rightSide: false
                property bool bottomSide: false
                Rectangle { width: 11; height: 1.5; color: Qt.rgba(67/255,65/255,58/255,0.55)
                            anchors.top: bottomSide ? undefined : parent.top
                            anchors.bottom: bottomSide ? parent.bottom : undefined }
                Rectangle { width: 1.5; height: 11; color: Qt.rgba(67/255,65/255,58/255,0.55)
                            anchors.left:  rightSide ? undefined : parent.left
                            anchors.right: rightSide ? parent.right : undefined }
            }
            Corner { x: 9;  y: 9 }
            Corner { y: 9;  anchors.right: parent.right; anchors.rightMargin: 9;  rightSide: true }
            Corner { x: 9;  anchors.bottom: parent.bottom; anchors.bottomMargin: 9; bottomSide: true }
            Corner { anchors.right: parent.right; anchors.rightMargin: 9
                     anchors.bottom: parent.bottom; anchors.bottomMargin: 9
                     rightSide: true; bottomSide: true }

            // -------------------------------------------------- header (title)
            Text {   // shadow
                x: root.inset + 27.5; y: 19.5
                text: "APPLICATIONS"; font.family: root.face; font.weight: Font.DemiBold
                font.pixelSize: 23; font.letterSpacing: 1.5
                color: Qt.rgba(125/255, 118/255, 95/255, 0.5)
            }
            Text {   // ink
                id: title
                x: root.inset + 26; y: 18
                text: "APPLICATIONS"; font.family: root.face; font.weight: Font.DemiBold
                font.pixelSize: 23; font.letterSpacing: 1.5; color: "#34322c"
            }
            Text {   // live count
                anchors.left: title.right; anchors.leftMargin: 13
                anchors.baseline: title.baseline
                text: list.count + " entries"
                font.family: root.face; font.pixelSize: 11; font.letterSpacing: 1.5
                color: root.muted
            }

            // header underline
            Rectangle { x: root.inset; y: 56; width: card.width - 2 * root.inset; height: 1; color: "#8d8a76" }

            // ----------------------------------------------------- search box
            Rectangle {
                id: searchBox
                x: root.inset + 46; y: 70
                width: card.width - 2 * root.inset - 46 - 42; height: 40
                color: "#bbb79f"; border.color: "#8d8a76"; border.width: 1

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
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: searchBox.bottom; anchors.topMargin: 12
                anchors.bottom: parent.bottom; anchors.bottomMargin: 26

                // top / bottom rules
                Rectangle { x: root.inset + 46; width: parent.width - 2 * root.inset - 88; height: 1; color: root.rail; anchors.top: parent.top }
                Rectangle { x: root.inset + 46; width: parent.width - 2 * root.inset - 88; height: 1; color: root.rail; anchors.bottom: parent.bottom }

                // left rails (thick + thin) — the cursor bar
                Rectangle { x: root.inset + 8;  width: 8; color: root.rail
                            anchors.top: parent.top; anchors.bottom: parent.bottom
                            anchors.topMargin: 4; anchors.bottomMargin: 4 }
                Rectangle { x: root.inset + 23; width: 2; color: root.rail
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

                    delegate: Item {
                        id: rowRoot
                        required property var modelData
                        required property int index
                        readonly property bool isSel: ListView.isCurrentItem
                        width: ListView.view ? ListView.view.width : 0
                        // selected row grows by rowPad on each side so its lines
                        // float above/below the coloured block
                        height: root.rowH + (isSel ? 2 * root.rowPad : 0)

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
                            border.color: Qt.rgba(67/255, 65/255, 58/255, 0.14)

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
                        width: parent.width; color: "#6f6c5a"
                        height: Math.max(24, sb.height * list.visibleArea.heightRatio)
                        y: list.visibleArea.yPosition * sb.height
                    }
                }
                Rectangle { width: 6; height: 6; radius: 3; color: "#6f6c5a"
                            anchors.right: parent.right; anchors.rightMargin: root.inset + 23; anchors.top: parent.top }
                Rectangle { width: 6; height: 6; radius: 3; color: "#6f6c5a"
                            anchors.right: parent.right; anchors.rightMargin: root.inset + 23; anchors.bottom: parent.bottom }
            }
        }
    }
}
