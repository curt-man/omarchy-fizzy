import QtQuick
import qs.Commons

// The widget's mark, in one of two shapes.
//
//   "bubbles"  three outlined bubbles drifting up — the plugin's own drawing
//   "logo"     Fizzy's actual app icon: five capsules hanging from a common
//              top, each on a thin stem, at the lengths and colors the real
//              mark uses
//
// Either shape paints in a single `tint` by default, so the bar can color it
// like every other glyph up there (and go accent while cards wait). `brand`
// swaps in Fizzy's own gradients instead, for people who want the real thing.
Item {
  id: root

  property color tint: Color.accent
  property real iconSize: Style.font.display
  property bool animate: false

  // "bubbles" | "logo"
  property string mark: "bubbles"
  // Paint the mark in Fizzy's colors rather than in `tint`.
  property bool brand: false

  implicitWidth: iconSize
  implicitHeight: iconSize

  // ---------------------------------------------------------------- bubbles

  component Bubble: Rectangle {
    id: bubble
    property real size: 6
    property real travel: 10
    property real lag: 0
    property real baseY: 0
    property real centerX: 0
    property color stroke: root.tint

    width: size
    height: size
    radius: size / 2
    color: "transparent"
    border.width: Math.max(1, size / 5)
    border.color: stroke
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

  Item {
    anchors.fill: parent
    visible: root.mark !== "logo"

    // Brand mode borrows three of the five logo colors, so the two marks read
    // as the same family rather than as two unrelated pictures.
    Bubble {
      size: root.iconSize * 0.42; centerX: root.iconSize * 0.36
      baseY: root.iconSize * 0.46; travel: root.iconSize * 0.10
      stroke: root.brand ? "#12ACFF" : root.tint
    }
    Bubble {
      size: root.iconSize * 0.26; centerX: root.iconSize * 0.72
      baseY: root.iconSize * 0.30; travel: root.iconSize * 0.14; lag: 700
      stroke: root.brand ? "#FD47D9" : root.tint
    }
    Bubble {
      size: root.iconSize * 0.18; centerX: root.iconSize * 0.56
      baseY: root.iconSize * 0.08; travel: root.iconSize * 0.08; lag: 1400
      stroke: root.brand ? "#00DDED" : root.tint
    }
  }

  // ------------------------------------------------------------------- logo

  // Fizzy's mark, measured off the app icon and expressed as fractions of the
  // canvas, so it holds its proportions at bar size and at panel size.
  //
  // Every capsule hangs from the same top edge; what differs is how far down
  // it reaches. The stem below it is what makes the mark read as five
  // *hanging* things rather than as a bar chart.
  readonly property var logoBars: [
    { center: 0.227, bottom: 0.625, top: "#014EFF", low: "#1DCDFF" },
    { center: 0.359, bottom: 0.797, top: "#FC0DC1", low: "#FE69E5" },
    { center: 0.492, bottom: 0.719, top: "#FC5C00", low: "#FEE300" },
    { center: 0.625, bottom: 0.563, top: "#6D8000", low: "#E3E900" },
    { center: 0.758, bottom: 0.625, top: "#0098C8", low: "#00F1F7" }
  ]
  readonly property real logoTop: 0.188
  readonly property real logoWidth: 0.094
  readonly property real logoStemBottom: 0.86

  Item {
    anchors.fill: parent
    visible: root.mark === "logo"

    Repeater {
      model: root.logoBars

      delegate: Item {
        required property var modelData
        anchors.fill: parent

        // The stem is drawn first and runs the full drop, so the capsule
        // simply covers the part of it that should not show. At bar size the
        // stem lands under a pixel wide, hence the floor.
        Rectangle {
          width: Math.max(1, root.iconSize * 0.023)
          x: Math.round(root.iconSize * modelData.center - width / 2)
          y: root.iconSize * root.logoTop
          height: root.iconSize * (root.logoStemBottom - root.logoTop)
          radius: width / 2
          color: root.brand ? Qt.rgba(1, 1, 1, 0.35) : root.tint
          opacity: root.brand ? 1 : 0.45
        }

        Rectangle {
          width: Math.max(1, Math.round(root.iconSize * root.logoWidth))
          x: Math.round(root.iconSize * modelData.center - width / 2)
          y: root.iconSize * root.logoTop
          height: root.iconSize * (modelData.bottom - root.logoTop)
          radius: width / 2
          color: root.brand ? "transparent" : root.tint

          gradient: root.brand ? brandGradient : null

          Gradient {
            id: brandGradient
            GradientStop { position: 0.0; color: modelData.top }
            GradientStop { position: 1.0; color: modelData.low }
          }
        }
      }
    }
  }
}
