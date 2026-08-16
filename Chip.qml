import QtQuick
import qs.Commons

// Pill chip used for filters, movers, tags, and people. Fizzy column colors
// arrive via `dot`; `active` renders the shell's selected state, so themes
// control the fill alpha and whether a selected border exists at all.
Rectangle {
  id: root

  property string label: ""
  property color dot: "transparent"
  property bool showDot: false
  property int count: -1
  property bool active: false
  property bool dimmed: false
  property color accent: Color.accent
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal clicked()

  height: Math.ceil(content.implicitHeight) + Style.space(8)
  width: content.implicitWidth + Style.space(18)
  radius: Style.cornerRadius > 0 ? height / 2 : 0
  color: active ? Style.selectedFillFor(foreground, accent)
    : area.containsMouse ? Style.hoverFillFor(foreground, accent)
    : Style.normalFillFor(foreground, accent)
  border.width: active ? Style.selectedBorderWidth
    : area.containsMouse ? Style.hoverBorderWidth : 0
  border.color: active ? Style.selectedBorderFor(foreground, accent)
    : Style.hoverBorderFor(foreground, accent)
  opacity: dimmed ? 0.45 : 1.0

  Behavior on color { ColorAnimation { duration: 60 } }
  Behavior on opacity { NumberAnimation { duration: 120 } }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(5)

    Rectangle {
      visible: root.showDot
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(7)
      height: width
      radius: width / 2
      color: root.dot
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      color: root.active ? root.foreground : Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.weight: root.active ? Font.DemiBold : Font.Normal
    }

    Text {
      id: countText
      visible: root.count >= 0
      anchors.verticalCenter: parent.verticalCenter
      text: String(root.count)
      color: Qt.darker(root.foreground, root.active ? 1.2 : 1.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption

      // Counts change as cards move — dip-fade instead of snapping.
      Behavior on text {
        SequentialAnimation {
          NumberAnimation { target: countText; property: "opacity"; to: 0; duration: 70; easing.type: Easing.InQuad }
          PropertyAction { }
          NumberAnimation { target: countText; property: "opacity"; to: 1; duration: 110; easing.type: Easing.OutQuad }
        }
      }
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
