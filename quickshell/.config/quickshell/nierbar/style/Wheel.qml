pragma Singleton
import QtQuick

// Shared scroll-wheel normalisation for the whole bar.
//
// Touchpads differ from mouse wheels in two ways:
//   1. they emit many tiny events instead of discrete 120-unit notches, so
//      reacting to every event makes a value rocket on a single swipe;
//   2. with natural scrolling (Wayland) the sign is already negated, so a
//      "two fingers up" gesture arrives as a NEGATIVE angleDelta.
//
// `norm()` returns a signed delta that is POSITIVE for a physical "up" gesture
// (two fingers up / wheel up) on any device. Callers accumulate it and fire one
// step every `step` units — see StatusItem/WorkspaceStrip/VolumePopup.
QtObject {
  // One discrete step per this many accumulated units (a mouse notch = 120).
  // Lower it for faster touchpad stepping.
  readonly property real step: 120

  // Set false if you turn off touchpad natural_scroll in Hyprland.
  property bool touchpadNaturalScroll: true

  function norm(wheel) {
    const ad = wheel.angleDelta.y
    if (ad === 0) return 0
    // a mouse wheel reports zero pixelDelta and an exact multiple of 120
    const touchpad = wheel.pixelDelta.y !== 0 || (ad % 120) !== 0
    if (touchpad)
      return touchpadNaturalScroll ? -ad : ad
    return ad
  }
}
