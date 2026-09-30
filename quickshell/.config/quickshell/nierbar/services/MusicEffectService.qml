import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../style"

// "Music effect": when enabled (toggled from SUPER+W) AND something is actually
// playing, the clock's two side decorations turn into a cava-style audio
// visualiser (see CenterClock). The HUD frame is intentionally NOT affected by
// music any more — it keeps its calm idle breath (and corner-tick pulse) in
// every mode.
//
// Created once in shell.qml and shared by every screen's Bar.
Item {
  id: root

  // --- user toggle (flipped via IPC from the SUPER+W keybind) --------------
  property bool enabled: false
  function toggle() { root.enabled = !root.enabled }
  function on()     { root.enabled = true }
  function off()    { root.enabled = false }

  // --- active MPRIS player -------------------------------------------------
  // Prefer a player that is actually Playing; otherwise fall back to the first.
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    var ps = root.players
    for (var i = 0; i < ps.length; i++)
      if (ps[i].playbackState === MprisPlaybackState.Playing) return ps[i]
    return ps.length ? ps[0] : null
  }
  readonly property bool playing:
    !!root.player && root.player.playbackState === MprisPlaybackState.Playing
  readonly property string artUrl: root.player ? root.player.trackArtUrl : ""

  // master gate: the effect is on AND audio is playing
  readonly property bool active: root.enabled && root.playing
  onActiveChanged: {
    if (!root.active) root.bars = []   // clear the meter at rest
    root._maybeExtract()
  }

  // --- accent colour from album / thumbnail art ----------------------------
  // The visualiser bars are tinted with the art's dominant colour (see
  // scripts/album_color.sh). Defaults to the theme line colour until resolved.
  property color accentColor: Theme.line
  property string _resolvedArt: ""

  onArtUrlChanged: root._maybeExtract()
  function _maybeExtract() {
    if (root.active && root.artUrl.length && root.artUrl !== root._resolvedArt) {
      colorProc.command = [Quickshell.shellDir + "/scripts/album_color.sh", root.artUrl]
      colorProc.running = true
    }
  }

  Process {
    id: colorProc
    stdout: StdioCollector {
      onStreamFinished: {
        var hex = ("" + this.text).trim()
        if (/^#[0-9a-fA-F]{6}$/.test(hex)) {
          root.accentColor = hex
          root._resolvedArt = root.artUrl
        }
      }
    }
  }

  // --- live spectrum via cava (mono) --------------------------------------
  // Each entry is one bar's magnitude, normalised 0..1. The visualiser mirrors
  // each bar around the centre line, so only magnitudes are needed here.
  property var bars: []
  property real vizGain: 1.2          // scale raw bar height before clamping

  function _parseCava(line) {
    var parts = ("" + line).split(";")
    var out = []
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] === "") continue
      var v = parseInt(parts[i], 10)
      if (isNaN(v)) v = 0
      out.push(Math.max(0, Math.min(1, v / 1000 * root.vizGain)))   // ascii_max_range = 1000
    }
    root.bars = out
  }

  Process {
    id: cava
    running: root.active
    command: ["cava", "-p", Quickshell.shellDir + "/scripts/cava.conf"]
    stdout: SplitParser { onRead: line => root._parseCava(line) }
  }

  // --- idle breathing (always running, cheap) ------------------------------
  // Shared calm pulse read by the frame (opacity + corner ticks) and the clock
  // side ticks whenever they're not visualising.
  property real idleBreath: 0
  SequentialAnimation on idleBreath {
    loops: Animation.Infinite
    running: true
    NumberAnimation { from: 0; to: 1; duration: 900;  easing.type: Easing.InOutSine }
    NumberAnimation { from: 1; to: 0; duration: 1300; easing.type: Easing.InOutSine }
  }
}
