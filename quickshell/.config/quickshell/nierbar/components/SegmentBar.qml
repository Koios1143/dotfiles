import QtQuick
import "../style"

// Segmented level meter: a row of thin, right-leaning parallelograms, one per
// `step` of value. A segment lights only once its value is actually reached
// (5, 10, 15, …), so `value == 0` leaves every segment dark.
//
// Lit segments are white; for volume the part above 100% (`overThreshold`)
// switches to brass. Whenever a segment *newly* lights up (value increasing) it
// gets a brief "poked from behind" pop — scales up, then settles back — while
// unlighting (value decreasing) and the initial populate stay silent.
Item {
  id: root

  // ---- inputs -------------------------------------------------------------
  property real  value: 0            // current reading
  property real  step: 5             // value represented by one segment
  property int   segments: 30        // total segment count
  property real  overThreshold: -1   // value above which `overColor` is used (-1 = never)

  property color litColor: "#ffffff"
  property color overColor: Theme.amber
  property color offColor: Theme.dim

  property real  gap: 3              // space between segments (px)
  property real  lean: 5            // top-edge shift of each parallelogram (px, leans right)

  implicitHeight: 16

  // number of lit segments (floor: a segment lights only when its value is met)
  readonly property int litCount:
    Math.max(0, Math.min(segments, Math.floor(value / step + 0.0001)))

  // gate so the first populate (open / initial read) doesn't fire the poke
  property bool armed: false
  Component.onCompleted: armed = true

  Row {
    anchors.fill: parent
    spacing: root.gap

    Repeater {
      model: root.segments

      delegate: Item {
        id: cell
        required property int index
        width: (root.width - (root.segments - 1) * root.gap) / root.segments
        height: root.height

        readonly property bool lit: cell.index < root.litCount
        readonly property bool over: root.overThreshold >= 0
                                     && (cell.index + 1) * root.step > root.overThreshold

        Rectangle {
          id: bar
          anchors.fill: parent
          antialiasing: true
          color: cell.lit ? (cell.over ? root.overColor : root.litColor)
                          : root.offColor
          // ease colour flips so lighting / unlighting isn't an abrupt jump
          Behavior on color { ColorAnimation { duration: 130 } }

          // right-leaning parallelogram: shear the top edge right, bottom left,
          // centred so it doesn't drift sideways (x' = x - lean/h * y + lean/2)
          transform: Matrix4x4 {
            matrix: Qt.matrix4x4(1, -root.lean / bar.height, 0, root.lean / 2,
                                 0, 1, 0, 0,
                                 0, 0, 1, 0,
                                 0, 0, 0, 1)
          }

          // "poked from behind": pop toward the viewer, then settle with a
          // little overshoot so it reads as a physical nudge
          transformOrigin: Item.Center
          SequentialAnimation {
            id: poke
            NumberAnimation { target: bar; property: "scale"
                              to: 1.55; duration: 90;  easing.type: Easing.OutQuad }
            NumberAnimation { target: bar; property: "scale"
                              to: 1.0;  duration: 240; easing.type: Easing.OutBack
                              easing.overshoot: 3.0 }
          }
        }

        // poke only on a fresh light-up, and only after the meter has settled;
        // lift the whole cell so the pop draws over its neighbours
        onLitChanged: if (cell.lit && root.armed) { cell.z = 1; poke.restart() }
      }
    }
  }
}
