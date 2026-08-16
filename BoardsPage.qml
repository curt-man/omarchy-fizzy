import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root
  property var panel: null

  property PointerMoveGate gate: PointerMoveGate { referenceItem: boardList }
  function resetGate() { gate.reset() }

  Column {
    anchors.fill: parent
    spacing: Style.space(6)

    PanelSectionHeader {
      text: "BOARDS"
      foreground: panel.ink
      fontFamily: panel.fontFamily
    }

    Row {
      visible: panel.boards.length === 0
      spacing: Style.space(8)

      Text {
        visible: panel.busy
        anchors.verticalCenter: parent.verticalCenter
        text: "󰦖"
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.body

        RotationAnimator on rotation {
          running: panel.busy && panel.boards.length === 0
          from: 0
          to: 360
          duration: 800
          loops: Animation.Infinite
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: panel.busy ? "Loading boards…"
          : panel.offline ? "Can't reach Fizzy — press r to retry"
          : "No boards yet — make one in Fizzy"
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    ListView {
      id: boardList
      width: parent.width
      height: parent.height - y
      clip: true
      spacing: Style.space(6)
      model: panel.boards
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      reuseItems: true

      Connections {
        target: root.panel
        function onBoardCursorChanged() {
          if (root.panel.boardCursor >= 0)
            boardList.positionViewAtIndex(root.panel.boardCursor, ListView.Contain)
        }
      }

      delegate: CursorSurface {
        id: boardRow
        required property var modelData
        required property int index

        readonly property bool isCurrent: String(modelData.id) === panel.boardId

        width: boardList.width
        implicitHeight: Style.space(36)
        hasCursor: panel.page === "boards" && panel.boardCursor === index
        current: isCurrent
        foreground: panel.ink
        accent: panel.accent

        Row {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          spacing: Style.space(9)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(8)
            height: width
            radius: width / 2
            color: boardRow.isCurrent ? panel.accent : panel.hairline
            Behavior on color { ColorAnimation { duration: 120 } }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: boardRow.modelData.name || "Untitled"
            color: panel.ink
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
            font.bold: boardRow.isCurrent
            elide: Text.ElideRight
            width: Math.min(implicitWidth, boardList.width - Style.space(80))
          }
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: "󰅂"
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: function(mouse) {
            if (root.gate.moved(boardRow, mouse)) panel.boardCursor = boardRow.index
          }
          onClicked: panel.selectBoard(boardRow.modelData.id)
        }
      }
    }
  }
}
