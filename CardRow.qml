import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One card in the board list: column-color spine, title, meta line, avatars.
CursorSurface {
  id: root

  property var panel: null
  property var card: null
  property int rowIndex: 0
  property var gate: null

  signal openRequested()

  readonly property var mates: (card && card.assignees) ? card.assignees : []

  // A card can carry any number of people. Three seats is what the row has
  // width for next to a two-line title, so the rest become a count: dropping
  // them silently would make a crowded card look like a quiet one.
  //
  // Fizzy truncates the list itself on a busy card and says so in
  // has_more_assignees — so a number would be a guess there, and the seat says
  // "more" instead of inventing one.
  readonly property int seatLimit: 3
  readonly property bool moreThanListed: card && card.has_more_assignees === true
  readonly property int overflow: Math.max(0, mates.length - seatLimit)
  readonly property bool showOverflow: overflow > 0 || moreThanListed
  readonly property string overflowLabel: moreThanListed ? "…" : "+" + overflow
  readonly property real seatSize: Style.space(20)

  hasCursor: panel && panel.page === "board" && panel.cardCursor === rowIndex
  foreground: panel ? panel.ink : Color.foreground
  accent: panel ? panel.accent : Color.accent
  implicitHeight: Math.ceil(body.implicitHeight) + Style.space(16)

  // Cards read as cards: keep a resting surface under the cursor states.
  // Golden cards rest on a faint accent wash so they read at a glance.
  readonly property color restFill: card && card.golden === true
    ? Util.alpha(accent, 0.10)
    : Style.normalFillFor(foreground, accent)
  color: hasCursor ? fill : restFill

  // Column-color spine, echoing Fizzy's card accents; it thickens a touch
  // under the cursor, so the highlight has a color of its own.
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(5)
    width: root.hasCursor ? Style.space(5) : Style.space(3)
    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    radius: width / 2
    color: root.card && root.card.column
      ? Model.columnColor(root.card.column, root.panel.lightTheme)
      : root.panel.hairline
  }

  Column {
    id: body
    anchors.left: parent.left
    anchors.right: avatarStack.left
    anchors.leftMargin: Style.space(14)
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Text {
      width: parent.width
      text: (root.card && root.card.golden ? "★ " : "") + (root.card ? (root.card.title || "Untitled") : "")
      color: root.panel.ink
      font.family: root.panel.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }

    Row {
      spacing: Style.space(6)

      Text {
        text: root.card ? ("#" + root.card.number) : ""
        color: root.panel.dim
        font.family: root.panel.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: root.card && (root.card.tags || []).length > 0
        text: root.card ? (root.card.tags || []).map(function(tag) {
          return "#" + Model.tagTitle(tag)
        }).join(" ") : ""
        color: root.panel.accent
        font.family: root.panel.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: Math.min(implicitWidth, Style.space(150))
      }

      Text {
        text: root.card ? Model.relativeTime(root.card.last_active_at, root.panel.nowTick) : ""
        color: root.panel.dim
        font.family: root.panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Row {
    id: avatarStack
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: -Style.space(5)

    Repeater {
      model: root.mates.slice(0, root.seatLimit)
      delegate: Avatar {
        required property var modelData
        user: modelData
        photoUrl: root.panel.avatarUrlFor(modelData)
        panel: root.panel
        size: root.seatSize
        initialsScale: 0.44
        // The stack overlaps by design; the ring is what keeps three seats
        // legible as three.
        borderWidth: 1
        borderColor: Color.popups ? Color.popups.background : Color.background
      }
    }

    // Same disc, same ring, so the count reads as one more seat rather than
    // as a label that wandered into the stack.
    Rectangle {
      visible: root.showOverflow
      width: root.seatSize
      height: root.seatSize
      radius: width / 2
      color: Style.normalFillFor(root.panel.ink, root.panel.accent)
      border.width: 1
      border.color: Color.popups ? Color.popups.background : Color.background

      Text {
        anchors.centerIn: parent
        text: root.overflowLabel
        color: root.panel.dim
        font.family: root.panel.fontFamily
        font.pixelSize: Math.round(root.seatSize * 0.44)
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // Gate-filtered: only deliberate pointer motion moves the cursor, so
    // keyboard scrolling can't be hijacked by rows sliding under the mouse.
    onPositionChanged: function(mouse) {
      if (root.panel && (!root.gate || root.gate.moved(root, mouse)))
        root.panel.cardCursor = root.rowIndex
    }
    onClicked: root.openRequested()
  }
}
