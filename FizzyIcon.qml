import QtQuick
import qs.Commons

// Fizzy's namesake: three bubbles drifting up. The drift only runs while
// `animate` is true (panel open) so the shell stays idle otherwise.
Item {
  id: root

  property color tint: Color.accent
  property real iconSize: Style.font.display
  property bool animate: false

  implicitWidth: iconSize
  implicitHeight: iconSize

  component Bubble: Rectangle {
    id: bubble
    property real size: 6
    property real travel: 10
    property real lag: 0
    property real baseY: 0
    property real centerX: 0

    width: size
    height: size
    radius: size / 2
    color: "transparent"
    border.width: Math.max(1, size / 5)
    border.color: root.tint
    x: centerX - size / 2
    y: baseY
    opacity: 0.9

    SequentialAnimation on y {
      running: root.animate
      loops: Animation.Infinite

      PauseAnimation { duration: bubble.lag }
      NumberAnimation {
        from: bubble.baseY; to: bubble.baseY - bubble.travel
        duration: 2600; easing.type: Easing.InOutSine
      }
      NumberAnimation {
        from: bubble.baseY - bubble.travel; to: bubble.baseY
        duration: 2600; easing.type: Easing.InOutSine
      }
    }
  }

  Bubble { size: root.iconSize * 0.42; centerX: root.iconSize * 0.36; baseY: root.iconSize * 0.46; travel: root.iconSize * 0.10 }
  Bubble { size: root.iconSize * 0.26; centerX: root.iconSize * 0.72; baseY: root.iconSize * 0.30; travel: root.iconSize * 0.14; lag: 700 }
  Bubble { size: root.iconSize * 0.18; centerX: root.iconSize * 0.56; baseY: root.iconSize * 0.08; travel: root.iconSize * 0.08; lag: 1400 }
}
