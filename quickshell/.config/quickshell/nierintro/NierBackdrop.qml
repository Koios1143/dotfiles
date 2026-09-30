// What the menu is opening on top of, with the transition's lens distortion
// applied: radial chromatic aberration plus a progressive defocus, both ramping
// in while the lattice is drawn.
//
// Put the content in as children (a wallpaper Image, a screenshot, anything)
// and drive `amount` from NierIntro.latticeProgress:
//
//   NierBackdrop {
//       anchors.fill: parent
//       amount: intro.latticeProgress
//       Image { anchors.fill: parent; source: wallpaper }
//   }

import QtQuick
import QtQuick.Effects

Item {
    id: root

    default property alias content: holder.data

    // 0 = untouched, 1 = fully distorted (reached as the lattice completes)
    property real amount: 0

    property real caStrength:     0.0120  // extra radial scale for red/blue
    property real radialStrength: 0.006   // scale spread of the zoom blur
    property real blurStrength:   0.75    // mild uniform defocus, fraction of blurMax

    readonly property real eased: Math.max(0, Math.min(1, amount))

    // Each stage is handed on as a texture. Note the pattern: the source item
    // stays visible and the ShaderEffectSource hides it via `hideSource`.
    // Setting visible:false + layer.enabled instead gives an empty texture,
    // because an invisible item never updates its layer.
    Item {
        id: holder
        anchors.fill: parent
    }

    ShaderEffectSource {
        id: rawTex
        anchors.fill: parent
        sourceItem: holder
        hideSource: true
        visible: false
    }

    ShaderEffect {
        id: ca
        anchors.fill: parent
        readonly property var source: rawTex
        readonly property real caAmount: root.eased * root.caStrength
        readonly property real radialAmount: root.eased * root.radialStrength
        fragmentShader: Qt.resolvedUrl("assets/ca.frag.qsb")
    }

    ShaderEffectSource {
        id: caTex
        anchors.fill: parent
        sourceItem: ca
        hideSource: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: caTex
        blurEnabled: root.eased > 0.002
        blurMax: 24
        blur: root.eased * root.blurStrength
    }
}
