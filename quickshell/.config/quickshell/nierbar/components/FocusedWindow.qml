import QtQuick
import "../style"

Item {
  id: root
  property string title: "Desktop"
  property string windowClass: ""
  property int maxTitleWidth: 360

  // map the focused window's class to a Nerd Font glyph (browser -> globe, etc.)
  function appIcon(cls) {
    const c = (cls || "").toLowerCase()
    if (/zen|firefox|chrom|brave|browser|web|edge|epiphany/.test(c)) return String.fromCodePoint(0xF059F) // globe
    if (/kitty|foot|alacritty|wezterm|term|tmux/.test(c)) return String.fromCodePoint(0xF018D)            // console
    if (/code|cursor|zed|nvim|vim|jetbrains|idea/.test(c)) return String.fromCodePoint(0xF0174)           // code-tags
    if (/discord|vesktop/.test(c)) return String.fromCodePoint(0xF066F)                                   // discord
    if (/file|nautilus|dolphin|thunar|nemo/.test(c)) return String.fromCodePoint(0xF024B)                 // folder
    return "◉"
  }

  implicitWidth: Math.min(maxTitleWidth, row.implicitWidth + 12)
  implicitHeight: Theme.itemHeight

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.color: Theme.dim
    border.width: 1
    opacity: 0.7
  }

  Row {
    id: row
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: 8
    spacing: 6

    Text {
      text: root.appIcon(root.windowClass)
      color: Theme.fg
      font.family: Theme.fontFamily
      font.pixelSize: Theme.iconText
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: titleText
      width: Math.min(root.maxTitleWidth - 28, implicitWidth)
      text: root.title
      color: Theme.fg
      elide: Text.ElideRight
      font.family: Theme.fontFamily
      font.pixelSize: Theme.normalText
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }

  Tooltip {
    x: Math.min(0, root.width / 2 - width / 2)
    y: Theme.barHeight + 6
    text: root.title
    shown: mouse.containsMouse && root.title.length > 0 && titleText.truncated
  }
}
