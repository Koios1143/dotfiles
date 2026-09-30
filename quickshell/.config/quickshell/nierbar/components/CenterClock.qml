import QtQuick
import "../style"

Item {
  id: root
  implicitWidth: 240
  implicitHeight: Theme.barHeight

  property date now: new Date()
  property var onClockClick: null
  // shared MusicEffectService (from Bar). When it's active the side decorations
  // become audio visualisers; otherwise they show the calm breathing tick.
  property var music
  readonly property bool viz: !!(root.music && root.music.active)

  // calm breathing phase the side ticks read when not visualising. Follows the
  // shared idle pulse, falling back to a local one if the service isn't wired up.
  readonly property real breath: root.music ? root.music.idleBreath : root.idleBreath
  property real idleBreath: 0
  SequentialAnimation on idleBreath {
    loops: Animation.Infinite
    running: true
    NumberAnimation { from: 0; to: 1; duration: 900;  easing.type: Easing.InOutSine }
    NumberAnimation { from: 1; to: 0; duration: 1300; easing.type: Easing.InOutSine }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: { if (root.onClockClick) root.onClockClick(root.mapToItem(null, 0, 0).x, root.width) }
  }

  // one side decoration: a thin line pinned at its inner (clock) edge that
  // grows outward as `breath` rises, with a diamond riding the outer end that
  // both drifts further out and swells slightly. `flip` mirrors it for the
  // right-hand side.
  component BreatheTick: Item {
    id: tick
    property bool flip: false
    implicitHeight: Theme.tinyText
    implicitWidth: line.width + 14

    Rectangle {
      id: line
      height: 1
      color: Theme.line
      width: 34 + 7 * root.breath
      anchors.verticalCenter: parent.verticalCenter
      anchors.left:  tick.flip ? parent.left  : undefined
      anchors.right: tick.flip ? undefined    : parent.right
    }

    Text {
      text: "◇"
      color: Theme.line
      font.family: Theme.fontFamily
      font.pixelSize: Theme.tinyText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left:        tick.flip ? line.right : undefined
      anchors.leftMargin:  tick.flip ? 1 : 0
      anchors.right:       tick.flip ? undefined  : line.left
      anchors.rightMargin: tick.flip ? 0 : 1
      scale: 1 + 0.22 * root.breath
    }
  }

  // audio visualiser that replaces a side tick while music plays: a row of bars
  // fed by cava. Each bar grows symmetrically UP and DOWN from the centre line
  // (mirror style) instead of only upward. `flip` mirrors bar order so the
  // lowest band sits nearest the clock on both sides.
  component AudioViz: Row {
    id: viz
    property bool flip: false
    property var levels: (root.music && root.music.bars) ? root.music.bars : []
    property int count: 12
    spacing: 2
    height: 26
    layoutDirection: viz.flip ? Qt.LeftToRight : Qt.RightToLeft

    Repeater {
      model: viz.count
      delegate: Item {
        id: cell
        required property int index
        width: 3
        height: viz.height
        readonly property real lvl: cell.index < viz.levels.length ? viz.levels[cell.index] : 0

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter   // mirror around centre
          width: parent.width
          height: Math.max(2, viz.height * cell.lvl)       // total height, centred
          radius: 1
          // tinted with the track art's dominant colour; fades on track change
          color: root.music ? root.music.accentColor : Theme.line
          Behavior on color { ColorAnimation { duration: 400 } }
          Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutSine } }
        }
      }
    }
  }

  Column {
    id: clockBlock
    anchors.centerIn: parent
    spacing: -1
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDateTime(root.now, "HH:mm")
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.timeText
      font.letterSpacing: 2
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDateTime(root.now, "yyyy / MM / dd  ddd").toUpperCase()
      color: Theme.fg
      opacity: 0.86
      font.family: Theme.fontFamily
      font.pixelSize: Theme.smallText
      font.letterSpacing: 1
    }
  }

  // --- left side: breathing tick <-> visualiser (cross-faded on music mode) --
  BreatheTick {
    flip: false
    anchors.right: clockBlock.left
    anchors.rightMargin: 14
    anchors.verticalCenter: clockBlock.verticalCenter
    opacity: root.viz ? 0 : 1
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220 } }
  }
  AudioViz {
    flip: false
    anchors.right: clockBlock.left
    anchors.rightMargin: 14
    anchors.verticalCenter: clockBlock.verticalCenter
    opacity: root.viz ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220 } }
  }

  // --- right side ------------------------------------------------------------
  BreatheTick {
    flip: true
    anchors.left: clockBlock.right
    anchors.leftMargin: 14
    anchors.verticalCenter: clockBlock.verticalCenter
    opacity: root.viz ? 0 : 1
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220 } }
  }
  AudioViz {
    flip: true
    anchors.left: clockBlock.right
    anchors.leftMargin: 14
    anchors.verticalCenter: clockBlock.verticalCenter
    opacity: root.viz ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 220 } }
  }
}
