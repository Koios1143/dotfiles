import QtQuick
import "../style"

Item {
  id: root
  implicitWidth: 240
  implicitHeight: Theme.barHeight

  property date now: new Date()
  property var onClockClick: null

  // shared breathing phase: eases out to 1, then slowly settles back to 0,
  // forever. Both side ticks read it so they inhale/exhale in sync.
  property real breath: 0
  SequentialAnimation on breath {
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

  BreatheTick {
    flip: false
    anchors.right: clockBlock.left
    anchors.rightMargin: 14
    anchors.verticalCenter: clockBlock.verticalCenter
  }

  BreatheTick {
    flip: true
    anchors.left: clockBlock.right
    anchors.leftMargin: 14
    anchors.verticalCenter: clockBlock.verticalCenter
  }
}
