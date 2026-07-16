import QtQuick
import Quickshell
import Quickshell.Wayland
import "../style"

// Bottom-centre HUD that pops up when the volume or brightness *changes* (from
// the keyboard XF86 keys, the scroll wheel, or the click sliders) and fades out
// a moment later. Horizontal bar: octagon frame + solid fill, left icon, a
// status track, and the percent on the right.
//
// It shares the bar's SystemService (`sys`), so the value, the icon thresholds
// and the percent are always identical to what nier-bar itself shows — no second
// Pipewire tracker / brightness monitor. State is reactive: sys.volume follows
// the default sink live, sys.brightness follows the backlight udev monitor, so
// a change from *any* source lands here with sub-frame latency.
//
// Frame + base colours are nier-launcher's octagon palette (per request); the
// white damage-grid the launcher draws inside its octagon is intentionally left
// out here.
PanelWindow {
  id: osd

  property var sys
  // suppressed while a click-slider popup is open, so we don't double up with it
  property bool suppress: false

  // --- nier-launcher octagon palette -------------------------------------
  readonly property color frameCol: "#5b5649"
  readonly property color fillTop:  "#1a1813"
  readonly property color fillBot:  "#131210"
  readonly property int   chamfer:  10

  // "volume" | "brightness" — which reading triggered this show
  property string mode: "volume"
  property int level: 0
  property int maxLevel: 100

  property bool shown: false
  property bool armed: false   // gate so populating initial values doesn't pop us

  // stay mapped until the fade-out finishes; unmapped (click-through) while idle
  visible: shown || card.opacity > 0.01

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "nierbar-osd"
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  // bottom edge only -> the compositor centres us horizontally
  anchors { bottom: true }
  margins { bottom: 72 }
  implicitWidth: 300
  implicitHeight: 54

  // ignore the change burst during startup (initial sink bind + first
  // brightness read) so the OSD only shows for real user changes
  Timer { id: armTimer; interval: 1200; running: true; onTriggered: osd.armed = true }
  Timer { id: hideTimer; interval: 1600; onTriggered: osd.shown = false }

  function popup(kind) {
    if (!osd.armed || osd.suppress) return
    osd.mode = kind
    osd.shown = true
    hideTimer.restart()
  }

  // icon thresholds mirror SystemCluster / the popups (nier-bar consistency)
  function volIcon() {
    if ((osd.sys && osd.sys.muted) || osd.level <= 0) return "󰝟"   // zero volume reads as muted
    if (osd.level <= 50) return "󰖀"
    return "󰕾"
  }
  function brIcon() {
    if (osd.level <= 40) return String.fromCodePoint(0xF00DE)   // small sun (dim)
    return String.fromCodePoint(0xF00E0)                        // full sun
  }
  function icon() { return osd.mode === "volume" ? osd.volIcon() : osd.brIcon() }

  Connections {
    target: osd.sys
    function onVolumeChanged() {
      var v = Number(osd.sys.volume)
      if (isNaN(v)) return
      osd.maxLevel = osd.sys.maxVolume
      osd.level = v
      osd.popup("volume")
    }
    function onMutedChanged() {
      var v = Number(osd.sys.volume)
      if (isNaN(v)) return
      osd.maxLevel = osd.sys.maxVolume
      osd.level = v
      osd.popup("volume")
    }
    function onBrightnessChanged() {
      var v = Number(osd.sys.brightness)
      if (isNaN(v)) return
      osd.maxLevel = 100
      osd.level = v
      osd.popup("brightness")
    }
  }

  // -------------------------------------------------------------- the card
  Item {
    id: card
    anchors.fill: parent

    // rise + fade in on show, sink + fade out on hide
    opacity: osd.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    transform: Translate {
      y: osd.shown ? 0 : 8
      Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    // octagon frame + solid fill (no damage grid)
    Canvas {
      id: frame
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var c = getContext("2d"); c.clearRect(0, 0, width, height)
        var w = width, h = height, k = osd.chamfer
        c.beginPath()
        c.moveTo(k, 1); c.lineTo(w - k, 1); c.lineTo(w - 1, k)
        c.lineTo(w - 1, h - k); c.lineTo(w - k, h - 1); c.lineTo(k, h - 1)
        c.lineTo(1, h - k); c.lineTo(1, k); c.closePath()
        var g = c.createLinearGradient(0, 0, 0, h)
        g.addColorStop(0, osd.fillTop); g.addColorStop(1, osd.fillBot)
        c.fillStyle = g; c.fill()
        c.strokeStyle = osd.frameCol; c.lineWidth = 1.5; c.stroke()
      }
    }

    // content: [icon]  [====track====]  [NN%]
    Item {
      anchors.fill: parent
      anchors.leftMargin: 18
      anchors.rightMargin: 18

      // fixed-width slot so a wider glyph (e.g. the max-volume icon) can't push
      // the track's left edge to the right — the bar always starts at the same x
      Text {
        id: ic
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        horizontalAlignment: Text.AlignHCenter
        text: osd.icon()
        color: (osd.mode === "volume" && osd.sys && osd.sys.muted) ? Theme.muted : Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: 20
      }

      Text {
        id: pct
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 38
        horizontalAlignment: Text.AlignRight
        text: (osd.mode === "volume" && osd.sys && osd.sys.muted) ? "──" : (osd.level + "%")
        color: (osd.mode === "volume" && osd.level > 100) ? Theme.amber : Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: 12
      }

      SegmentBar {
        anchors.left: ic.right
        anchors.leftMargin: 12
        anchors.right: pct.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        height: 16
        value: osd.level
        step: 5
        segments: Math.round(osd.maxLevel / 5)   // 30 for volume (150), 20 for brightness (100)
        overThreshold: (osd.mode === "volume" && osd.maxLevel > 100) ? 100 : -1
      }
    }
  }
}
