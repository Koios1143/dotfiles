// =============================================================================
//  SelectionKite.qml  —  the sliding NieR cursor, reusable across menus.
//
//  Parent it to the container that holds your option rows (it needs room to the
//  LEFT of the rows to sit in), and bind `target` to the currently-selected row
//  Item. It slides to track that row's vertical centre and parks its point just
//  left of the row's leading edge.
//
//  kite.svg must sit next to this file.
//
//  Wiring examples (inside the options container):
//    ListView:            SelectionKite { target: optionList.currentItem }
//    Repeater + index:    SelectionKite { target: optionRepeater.itemAt(root.selectedIndex) }
// =============================================================================

import QtQuick

Image {
    id: kite

    property Item target: null      // the currently-selected row Item
    property real gap: 8            // space between the kite's point and the row

    source: Qt.resolvedUrl("kite.svg")
    width: 34; height: 18
    smooth: true
    z: 10
    visible: target !== null

    // track the target's mapped rect within this kite's parent
    x: target ? target.mapToItem(parent, 0, 0).x - width - gap : x
    y: target ? target.mapToItem(parent, 0, 0).y + target.height / 2 - height / 2 : y

    Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
}
