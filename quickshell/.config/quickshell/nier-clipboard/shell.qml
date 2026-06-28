// =============================================================================
//  NieR:Automata clipboard history  —  Quickshell (standalone)
//    - compact octagon panel anchored at the cursor's bottom-right
//    - dark NieR palette, YoRHa emblem, type icons, image thumbnails, timestamps
//    - keys: ↑/↓ move · Enter paste · s pin · d/Del delete · Esc close
//    - history via cliphist; timestamps via clip-stamp.sh; paste via wtype
//  Toggle: qs -c nier-clipboard ipc call clipboard toggle
// =============================================================================

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: root

    // ---- palette (dark NieR) -----------------------------------------------
    readonly property string faceHead: "FOT-Rodin Pro"
    readonly property string faceMono: "JetBrainsMono Nerd Font"

    readonly property color panelBg:   "#1a1813"
    readonly property color panelBg2:  "#131210"
    readonly property color rowBg:     "#211e18"
    readonly property color rowBgSel:  "#2d2920"
    readonly property color frame:     "#5b5649"          // the one ring
    readonly property color frameSoft: Qt.rgba(91/255, 86/255, 73/255, 0.55)
    readonly property color innerLine: Qt.rgba(215/255,208/255,196/255,0.10)
    readonly property color ink:       "#d7d0c4"
    readonly property color ink2:      "#cfc8ba"
    readonly property color muted:     "#8a8377"
    readonly property color dim:       "#5a544b"
    readonly property color accent:    "#d99b45"

    // ---- geometry ----------------------------------------------------------
    readonly property int cardW:   360
    readonly property int rowH:    64
    readonly property int rowGap:  6
    readonly property int maxRows: 5
    readonly property int headerH: 40
    readonly property int footerH: 30
    readonly property int chamfer: 13

    readonly property int pasteDelay: 180
    readonly property string cacheDir: "/home/koios/.cache/nier-clipboard"

    // ---- state -------------------------------------------------------------
    property var  items:   []
    property var  pinned:  ({})
    property var  stamps:  ({})
    property real cursorX: 0
    property real cursorY: 0
    property bool ready:   false
    property string targetClass: ""

    // ---- parsing -----------------------------------------------------------
    function parseList(text) {
        var out = [], lines = (text || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            var ln = lines[i]; if (ln.length === 0) continue;
            var tab = ln.indexOf("\t"); if (tab < 0) continue;
            out.push(root.classify(ln.slice(0, tab), ln.slice(tab + 1)));
        }
        return out;
    }
    function classify(id, preview) {
        var p = (preview || "");
        var isImage = p.indexOf("[[ binary data") === 0;
        var meta = "", kind = "text";
        if (isImage) {
            kind = "image";
            var parts = p.replace("[[ binary data", "").replace("]]", "").trim().split(/\s+/);
            if (parts.length >= 4) meta = parts[0] + " " + parts[1] + "  ·  " + parts[3];
        } else if (/^https?:\/\//.test(p.trim()))            kind = "url";
        else if (/^\/[^\n]+\.[A-Za-z0-9]+$/.test(p.trim()))  kind = "file";
        else if (/^\s*</.test(p) && /<\/?[a-zA-Z]/.test(p))  kind = "html";
        return { id: id, preview: p, isImage: isImage, kind: kind, meta: meta };
    }
    function cleanPreview(it) {
        if (it.kind === "image") return "Image";
        var p = it.preview;
        if (it.kind === "html") {
            p = p.replace(/<[^>]*>/g, " ")   // drop complete tags
                 .replace(/<[^>]*$/, "")     // drop a trailing truncated tag
                 .replace(/&[a-z]+;/gi, " ");
            p = p.replace(/\s+/g, " ").trim();
            return p.length ? p : "HTML snippet";
        }
        p = p.replace(/\s+/g, " ").trim();
        return p.length ? p : "(blank)";
    }
    function glyph(kind) {
        switch (kind) {
            case "url":   return "";   // nf-fa-link
            case "file":  return "";   // nf-fa-file
            case "image": return "";   // nf-fa-image (fallback under thumb)
            case "html":  return "";   // nf-fa-code
            default:      return "T";
        }
    }
    function thumbUrl(id) { return "file://" + root.cacheDir + "/t-" + id + ".png"; }

    function parseStamps(t) {
        var m = {}, lines = (t || "").split("\n");
        for (var i = 0; i < lines.length; i++) {
            var tab = lines[i].indexOf("\t"); if (tab < 0) continue;
            m[lines[i].slice(0, tab)] = lines[i].slice(tab + 1);
        }
        return m;
    }
    function fmtTime(id) {
        var e = root.stamps[id]; if (!e) return "";
        var d = new Date(parseInt(e, 10) * 1000);
        function z(n) { return (n < 10 ? "0" : "") + n; }
        return z(d.getHours()) + ":" + z(d.getMinutes()) + ":" + z(d.getSeconds());
    }

    function parsePins(t) {
        try { var o = JSON.parse(t || "{}"); return (o && typeof o === "object") ? o : ({}); }
        catch (e) { return ({}); }
    }
    function isPinned(id) { return root.pinned[id] === true; }
    function togglePin(id) {
        var u = Object.assign({}, root.pinned);
        if (u[id]) delete u[id]; else u[id] = true;
        root.pinned = u; pinFile.setText(JSON.stringify(u));
    }

    function buildList(src, pins) {
        var a = [], b = [];
        for (var i = 0; i < src.length; i++) { if (pins[src[i].id]) a.push(src[i]); else b.push(src[i]); }
        return a.concat(b);
    }

    // decode image entries to small cached thumbnails (idempotent)
    function ensureThumbs(src) {
        for (var i = 0; i < src.length; i++) {
            if (src[i].kind !== "image") continue;
            var id = src[i].id;
            Quickshell.execDetached(["sh", "-c",
                'd="' + root.cacheDir + '"; mkdir -p "$d"; f="$d/t-' + id + '.png"; ' +
                '[ -f "$f" ] || { printf "%s\\t" ' + id +
                ' | cliphist decode | magick - -thumbnail 160x160 "$f" 2>/dev/null; }']);
        }
    }

    // ---- backend -----------------------------------------------------------
    FileView {
        id: pinFile
        path: Quickshell.statePath("nier-clipboard-pins.json")
        blockLoading: true; printErrors: false
        onLoaded: root.pinned = root.parsePins(pinFile.text())
    }
    FileView {
        id: stampFile
        path: "/home/koios/.cache/cliphist/stamps"
        blockLoading: true; printErrors: false
        onLoaded: root.stamps = root.parseStamps(stampFile.text())
    }
    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: { root.items = root.parseList(this.text); root.ensureThumbs(root.items); }
        }
    }
    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { var o = JSON.parse(this.text); root.cursorX = o.x; root.cursorY = o.y; }
                catch (e) { root.cursorX = (win.width - root.cardW) / 2; root.cursorY = win.height * 0.25; }
                root.ready = true;
                Qt.callLater(function () { kbd.forceActiveFocus(); });
            }
        }
    }
    Process {
        id: classProc
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.targetClass = (JSON.parse(this.text).class || "").toLowerCase(); }
                catch (e) { root.targetClass = ""; }
            }
        }
    }
    function isTerminal(cls) {
        if (!cls) return false;
        if (cls.indexOf("term") >= 0) return true;
        return ["kitty","alacritty","foot","footclient","wezterm","st","ghostty",
                "com.mitchellh.ghostty","konsole","urxvt","rxvt","hyper","wave"].indexOf(cls) >= 0;
    }

    function copyById(id) {
        Quickshell.execDetached(["sh","-c","printf '%s\\t' " + id + " | cliphist decode | wl-copy"]);
    }
    Timer {
        id: pasteTimer
        interval: root.pasteDelay
        onTriggered: {
            if (root.isTerminal(root.targetClass))
                Quickshell.execDetached(["wtype","-M","ctrl","-M","shift","v","-m","shift","-m","ctrl"]);
            else
                Quickshell.execDetached(["wtype","-M","ctrl","v","-m","ctrl"]);
        }
    }
    function deleteById(id) {
        Quickshell.execDetached(["sh","-c","printf '%s\\t' " + id + " | cliphist delete"]);
        var arr = root.items.slice();
        for (var i = 0; i < arr.length; i++) if (arr[i].id === id) { arr.splice(i, 1); break; }
        root.items = arr;
    }
    function deleteCurrent() {
        var idx = list.currentIndex;
        var m = list.model[idx]; if (!m) return;
        root.deleteById(m.id);
        // model is rebuilt (which resets currentIndex to 0) — restore focus to the
        // same slot so the next item slides up; clamp when the last row was removed.
        Qt.callLater(function () {
            if (list.count > 0) list.currentIndex = Math.min(idx, list.count - 1);
        });
    }
    function pinCurrent()    { var m = list.model[list.currentIndex]; if (m) root.togglePin(m.id); }
    function clearAll() {
        Quickshell.execDetached(["sh","-c","cliphist wipe; rm -f " + root.cacheDir + "/t-*.png"]);
        root.items = [];
    }

    // ---- open / close ------------------------------------------------------
    property bool armed: false
    Timer { id: armTimer; interval: 150; onTriggered: root.armed = true }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { if (win.visible && root.armed) root.hide(); }
    }
    function show() {
        root.ready = false;
        listProc.running = true;
        stampFile.reload();
        cursorProc.running = true;
        classProc.running = true;
        list.currentIndex = 0;
        root.armed = false; armTimer.restart();
        win.visible = true;
        grab.active = true;
    }
    function hide() { root.armed = false; grab.active = false; win.visible = false; }
    function toggle() { if (win.visible) root.hide(); else root.show(); }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggle(); }
        function open():   void { root.show(); }
        function dismiss(): void { root.hide(); }
    }

    function activate(idx) {
        var m = list.model[idx]; if (!m) return;
        root.copyById(m.id); root.hide(); pasteTimer.restart();
    }

    // ========================================================================
    PanelWindow {
        id: win
        visible: false
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore      // cover the whole output (under the bar too)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "nier-clipboard"

        HyprlandFocusGrab { id: grab; windows: [win]; onCleared: root.hide() }
        MouseArea { anchors.fill: parent; onClicked: root.hide() }

        // --------------------------------------------------------------- card
        FocusScope {
            id: kbd
            visible: root.ready
            width: root.cardW
            readonly property int visRows: Math.min(Math.max(list.count, 1), root.maxRows)
            readonly property int listH: visRows * root.rowH + (visRows - 1) * root.rowGap
            height: 14 + root.headerH + 14 + listH + 14 + root.footerH + 12
            // top-left corner sits exactly at the cursor's bottom-right
            x: Math.max(4, Math.min(root.cursorX + 2, win.width  - width  - 4))
            y: Math.max(4, Math.min(root.cursorY + 2, win.height - height - 4))

            Keys.onEscapePressed: root.hide()
            Keys.onUpPressed:    list.currentIndex = Math.max(0, list.currentIndex - 1)
            Keys.onDownPressed:  list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1)
            Keys.onReturnPressed: root.activate(list.currentIndex)
            Keys.onEnterPressed:  root.activate(list.currentIndex)
            Keys.onDeletePressed: root.deleteCurrent()
            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_D)      { root.deleteCurrent(); event.accepted = true; }
                else if (event.key === Qt.Key_S) { root.pinCurrent();    event.accepted = true; }
            }

            MouseArea { anchors.fill: parent }    // swallow clicks on the card

            // octagon panel: fill + clipped damage grid + the single #5b5649 frame
            Canvas {
                id: panel
                anchors.fill: parent
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var c = getContext("2d"); c.clearRect(0, 0, width, height);
                    var w = width, h = height, k = root.chamfer;
                    function octagon() {
                        c.beginPath();
                        c.moveTo(k, 1); c.lineTo(w - k, 1); c.lineTo(w - 1, k);
                        c.lineTo(w - 1, h - k); c.lineTo(w - k, h - 1); c.lineTo(k, h - 1);
                        c.lineTo(1, h - k); c.lineTo(1, k); c.closePath();
                    }
                    // fill
                    var g = c.createLinearGradient(0, 0, 0, h);
                    g.addColorStop(0, root.panelBg); g.addColorStop(1, root.panelBg2);
                    octagon(); c.fillStyle = g; c.fill();
                    // damage grid, clipped to the octagon
                    c.save(); octagon(); c.clip();
                    c.strokeStyle = "rgba(215,208,196,0.025)"; c.lineWidth = 1; c.beginPath();
                    for (var x = 0; x <= w; x += 7) { c.moveTo(x + 0.5, 0); c.lineTo(x + 0.5, h); }
                    for (var y = 0; y <= h; y += 7) { c.moveTo(0, y + 0.5); c.lineTo(w, y + 0.5); }
                    c.stroke(); c.restore();
                    // the one ring
                    octagon(); c.strokeStyle = root.frame; c.lineWidth = 1.5; c.stroke();
                }
            }

            // ---------------------------------------------------- header
            Item {
                id: header
                anchors { top: parent.top; left: parent.left; right: parent.right }
                anchors.topMargin: 12; anchors.leftMargin: 16; anchors.rightMargin: 14
                height: root.headerH

                Image {
                    id: logo
                    source: Qt.resolvedUrl("yorha.svg")
                    anchors.verticalCenter: parent.verticalCenter
                    height: 30; width: 30 * 197/232
                    fillMode: Image.PreserveAspectFit; smooth: true; sourceSize.height: 60
                }
                Rectangle { id: hdiv; anchors.left: logo.right; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 1; height: 22; color: root.frameSoft }
                Text {
                    anchors.left: hdiv.right; anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "CLIPBOARD"; color: root.ink
                    font.family: root.faceHead; font.weight: Font.DemiBold
                    font.pixelSize: 16; font.letterSpacing: 3
                }
                Text {
                    id: counter
                    anchors.right: cdiv.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: (list.count ? (list.currentIndex + 1) : 0) + " / " + list.count
                    color: root.muted; font.family: root.faceMono; font.pixelSize: 12
                }
                Rectangle { id: cdiv; anchors.right: closeBtn.left; anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 1; height: 22; color: root.frameSoft }
                Text {
                    id: closeBtn
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: closeMa.containsMouse ? root.accent : root.muted
                    font.family: root.faceMono; font.pixelSize: 15
                    MouseArea { id: closeMa; anchors.fill: parent; anchors.margins: -8
                                hoverEnabled: true; onClicked: root.hide() }
                }
            }

            // header rule with diamond nodes
            Item {
                id: topRule
                anchors { left: parent.left; right: parent.right; top: header.bottom }
                anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.topMargin: 8
                height: 6
                Rectangle { anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 1; color: root.frameSoft }
                Repeater {
                    model: [0.0, 0.5, 1.0]
                    Rectangle { width: 4; height: 4; x: modelData * (parent.width - 4)
                        anchors.verticalCenter: parent.verticalCenter; color: root.frame; rotation: 45 }
                }
            }

            // ---------------------------------------------------- list
            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: topRule.bottom }
                anchors.leftMargin: 14; anchors.rightMargin: 14; anchors.topMargin: 8
                height: kbd.listH
                clip: true
                spacing: root.rowGap
                model: root.buildList(root.items, root.pinned)
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds
                onCountChanged: if (currentIndex >= count) currentIndex = Math.max(0, count - 1)
                onCurrentIndexChanged: Qt.callLater(function () {
                    if (currentIndex <= 0) positionViewAtBeginning();
                    else if (currentIndex >= count - 1) positionViewAtEnd();
                    else positionViewAtIndex(currentIndex, ListView.Contain);
                })

                delegate: Item {
                    id: rowRoot
                    required property var modelData
                    required property int index
                    readonly property bool isSel: ListView.isCurrentItem
                    width: ListView.view ? ListView.view.width : 0
                    height: root.rowH

                    Rectangle {
                        anchors.fill: parent
                        color: rowRoot.isSel ? root.rowBgSel : root.rowBg
                        border.width: 1
                        border.color: rowRoot.isSel ? root.frame : root.innerLine

                        Rectangle { visible: rowRoot.isSel; width: 2; height: parent.height - 12
                                    anchors.left: parent.left; anchors.leftMargin: 3
                                    anchors.verticalCenter: parent.verticalCenter; color: root.accent }

                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onEntered: list.currentIndex = rowRoot.index
                            onClicked: root.activate(rowRoot.index)
                        }

                        // icon / thumbnail box
                        Rectangle {
                            id: iconBox
                            anchors.left: parent.left; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40; height: 40; radius: 2; clip: true
                            color: Qt.rgba(215/255,208/255,196/255,0.04)
                            border.width: 1; border.color: root.frameSoft

                            Text {
                                anchors.centerIn: parent
                                visible: rowRoot.modelData.kind !== "image" || thumb.status !== Image.Ready
                                text: root.glyph(rowRoot.modelData.kind)
                                color: rowRoot.isSel ? root.ink : root.muted
                                font.family: rowRoot.modelData.kind === "text" ? root.faceHead : root.faceMono
                                font.pixelSize: rowRoot.modelData.kind === "text" ? 18 : 16
                                font.bold: true
                            }
                            Image {
                                id: thumb
                                visible: rowRoot.modelData.kind === "image" && status === Image.Ready
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                cache: false; asynchronous: true; smooth: true
                                sourceSize.width: 80; sourceSize.height: 80
                                source: rowRoot.modelData.kind === "image" ? root.thumbUrl(rowRoot.modelData.id) : ""
                                property int tries: 0
                                onStatusChanged: if (status === Image.Error && tries < 10) retry.start()
                                Timer {
                                    id: retry; interval: 300
                                    onTriggered: { thumb.tries++; var s = thumb.source; thumb.source = ""; thumb.source = s; }
                                }
                            }
                        }

                        Column {
                            anchors.left: iconBox.right; anchors.leftMargin: 13
                            anchors.right: star.left; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text {
                                width: parent.width
                                text: root.cleanPreview(rowRoot.modelData)
                                color: rowRoot.isSel ? root.ink : root.ink2
                                font.family: root.faceMono; font.pixelSize: 13
                                elide: Text.ElideRight; maximumLineCount: 1
                            }
                            Text {
                                width: parent.width; visible: text.length > 0
                                text: {
                                    var t = root.fmtTime(rowRoot.modelData.id);
                                    if (rowRoot.modelData.kind === "image" && rowRoot.modelData.meta)
                                        return (t ? t + "   " : "") + rowRoot.modelData.meta;
                                    return t;
                                }
                                color: root.dim; font.family: root.faceMono; font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        // star (pin) only
                        Text {
                            id: star
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.isPinned(rowRoot.modelData.id) ? "★" : "☆"
                            color: root.isPinned(rowRoot.modelData.id) ? root.accent
                                    : (starMa.containsMouse ? root.ink : root.dim)
                            font.family: root.faceMono; font.pixelSize: 15
                            MouseArea { id: starMa; anchors.fill: parent; anchors.margins: -6
                                        hoverEnabled: true; onClicked: root.togglePin(rowRoot.modelData.id) }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent; visible: list.count === 0
                    text: "NO CLIPBOARD HISTORY"
                    color: root.dim; font.family: root.faceHead
                    font.pixelSize: 12; font.letterSpacing: 2
                }
            }

            // footer rule
            Item {
                id: botRule
                anchors { left: parent.left; right: parent.right; top: list.bottom }
                anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.topMargin: 8
                height: 6
                Rectangle { anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 1; color: root.frameSoft }
            }

            // ---------------------------------------------------- footer
            Item {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.bottomMargin: 8
                height: root.footerH
                Row {
                    anchors.centerIn: parent; spacing: 8
                    Rectangle { width: 5; height: 5; rotation: 45; color: root.muted
                                anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "CLEAR ALL"; color: clearMa.containsMouse ? root.accent : root.muted
                        font.family: root.faceHead; font.pixelSize: 12; font.letterSpacing: 2
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { id: clearMa; anchors.fill: parent; anchors.margins: -6
                                    hoverEnabled: true; onClicked: root.clearAll() }
                    }
                    Rectangle { width: 5; height: 5; rotation: 45; color: root.muted
                                anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }
}
