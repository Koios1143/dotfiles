pragma Singleton
import QtQuick

QtObject {
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property int barHeight: 40
  readonly property int sideMargin: 14
  readonly property int tinyText: 9
  readonly property int smallText: 10
  readonly property int normalText: 11
  readonly property int timeText: 17
  readonly property int iconText: 14

  readonly property color bg: "#11110f"
  readonly property color bgAlt: "#171714"
  readonly property color fg: "#d7d0c4"
  readonly property color muted: "#817b71"
  readonly property color dim: "#4d4942"
  readonly property color line: "#6e675b"
  readonly property color activeBg: "#d7d0c4"
  readonly property color activeFg: "#14130f"
  readonly property color amber: "#d99b45"
  readonly property color red: "#d06050"
  readonly property color blue: "#6d8fd6"

  readonly property int itemHeight: 30
  readonly property int itemRadius: 1
  readonly property int dividerHeight: 24
  readonly property int compactGap: 7
  readonly property int workspaceSize: 26
}
