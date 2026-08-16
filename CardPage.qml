import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Card detail: everything you'd open Fizzy for, in one scroll. Move it,
// tick steps, assign people, tag it, read and write comments.
Item {
  id: root
  property var panel: null

  readonly property bool editorFocused: commentField.activeFocus

  readonly property var card: panel ? panel.cardDetail : null
  readonly property var progress: Model.stepsProgress(card ? card.steps : [])
  readonly property string place: Model.cardPlace(card, panel ? panel.cardOriginKey : "")

  // The comment box lives at the bottom of the scroll; bring it on screen
  // before focusing, or typing lands in an invisible field.
  function focusComment() {
    scrollToEdge(1)
    commentField.forceActiveFocus()
  }

  // Fresh card, fresh page: reset scroll and drop any comment draft from the
  // previous card. cardDetail reassigns on every mutation, so key on number.
  property string shownCardNumber: ""
  onCardChanged: {
    var number = card ? String(card.number) : ""
    if (number === shownCardNumber) return
    shownCardNumber = number
    flick.contentY = 0
    commentField.text = ""
    pendingComment = ""
  }

  // j/k scroll the detail view when the key catcher has focus.
  function scrollBy(dy) {
    if (flick.dragging) return
    var target = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy * Style.space(120)))
    scrollAnim.to = target
    scrollAnim.restart()
  }

  // gg / G jump to the top or bottom of the card.
  function scrollToEdge(direction) {
    if (flick.dragging) return
    scrollAnim.to = direction < 0 ? 0 : Math.max(0, flick.contentHeight - flick.height)
    scrollAnim.restart()
  }

  // Comments render as a digest — the latest one plus a count — unless the
  // reader asks for the rest. Collapses again when a different card opens.
  property string expandedFor: ""
  readonly property bool showAllComments:
    card && String(expandedFor) === String(card.number)
  readonly property var visibleComments: showAllComments
    ? panel.cardComments
    : panel.cardComments.slice(-1)
  readonly property int earlierCount: panel.cardComments.length - 1

  // SmoothedAnimation splices re-targets mid-flight, so held or repeated
  // j/k reads as one continuous glide instead of restarting each press.
  SmoothedAnimation {
    id: scrollAnim
    target: flick
    property: "contentY"
    duration: 170
    velocity: -1
  }

  // A sent comment stays visible as a pending row until Fizzy confirms it;
  // on failure the text returns to the field instead of vanishing.
  property string pendingComment: ""

  function submitComment() {
    var text = String(commentField.text).trim()
    if (text === "" || pendingComment !== "") return
    pendingComment = text
    commentField.text = ""
    var forCard = shownCardNumber
    panel.addComment(text, function(ok) {
      // Restore a failed comment only if the same card is still open.
      if (!ok && root.shownCardNumber === forCard) commentField.text = text
      if (root.shownCardNumber === forCard) root.pendingComment = ""
    })
  }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: body.implicitHeight + Style.space(8)
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    onMovementStarted: scrollAnim.stop()   // the user's drag always wins

    Column {
      id: body
      width: flick.width
      spacing: Style.space(14)

      // Title row: the star sits with the thing it marks, on the title's
      // first line, instead of floating in the hero.
      Item {
        width: parent.width
        implicitHeight: Math.max(titleText.implicitHeight, starWrap.height)

        Text {
          id: titleText
          anchors.left: parent.left
          anchors.right: starWrap.left
          anchors.rightMargin: Style.space(8)
          anchors.top: parent.top
          text: root.card ? (root.card.title || "Untitled") : ""
          color: panel.ink
          font.family: panel.fontFamily
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
          wrapMode: Text.Wrap
        }

        Item {
          id: starWrap
          readonly property bool isGolden: root.card && root.card.golden === true
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.topMargin: -Style.space(2)
          width: goldenButton.width
          height: goldenButton.height

          // Soft accent bloom behind a golden star — MultiEffect's
          // zero-offset shadow is the documented glow technique.
          Text {
            id: glowSource
            anchors.centerIn: parent
            text: "★"
            color: panel.accent
            font.family: panel.fontFamily
            font.pixelSize: Style.font.icon
            visible: false
          }

          MultiEffect {
            source: glowSource
            anchors.fill: glowSource
            visible: starWrap.isGolden
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: panel.accent
            shadowBlur: 1.0
            blurMax: 16
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            shadowOpacity: 0.6
            opacity: 0.35

            SequentialAnimation on opacity {
              running: starWrap.isGolden && panel.opened
              loops: Animation.Infinite
              NumberAnimation { to: 1.0; duration: 1600; easing.type: Easing.InOutSine }
              NumberAnimation { to: 0.35; duration: 1600; easing.type: Easing.InOutSine }
            }
          }

          PanelActionButton {
            id: goldenButton
            iconText: starWrap.isGolden ? "★" : "☆"
            tooltipText: starWrap.isGolden ? "Golden — tap to unmark" : "Make it golden"
            foreground: starWrap.isGolden ? panel.accent : panel.dim
            onClicked: {
              panel.toggleGolden()
              goldenPop.restart()
            }

            SequentialAnimation {
              id: goldenPop
              NumberAnimation { target: goldenButton; property: "scale"; to: 1.35; duration: 90; easing.type: Easing.OutQuad }
              NumberAnimation { target: goldenButton; property: "scale"; to: 1.0; duration: 160; easing.type: Easing.OutBack }
            }
          }
        }
      }

      // Mover: where the card lives. Tapping a chip moves it, Fizzy-style.
      Flow {
        width: parent.width
        spacing: Style.space(6)

        Chip {
          label: "Maybe?"
          active: root.place === "maybe"
          accent: panel.accent
          foreground: panel.ink
          onClicked: if (root.place !== "maybe") panel.moveCard("maybe")
        }

        Repeater {
          model: panel.columns
          delegate: Chip {
            required property var modelData
            label: modelData.name
            showDot: true
            dot: Model.columnColor(modelData, panel.lightTheme)
            active: root.place === String(modelData.id)
            accent: Model.columnColor(modelData, panel.lightTheme)
            foreground: panel.ink
            onClicked: if (root.place !== String(modelData.id)) panel.moveCard(String(modelData.id))
          }
        }

        Chip {
          label: "Not Now"
          active: root.place === "not_now"
          accent: panel.accent
          foreground: panel.ink
          onClicked: if (root.place !== "not_now") panel.moveCard("not_now")
        }

        Chip {
          label: root.place === "closed" ? "Done ✓" : "Done"
          active: root.place === "closed"
          accent: panel.accent
          foreground: panel.ink
          onClicked: panel.moveCard(root.place === "closed" ? "reopen" : "closed")
        }
      }

      // ------------------------------------------------ description
      Column {
        visible: !!(root.card && root.card.description_html)
        width: parent.width
        spacing: Style.space(6)

        PanelSeparator { foreground: panel.ink }
        PanelSectionHeader { text: "NOTES"; foreground: panel.ink; fontFamily: panel.fontFamily }

        Text {
          width: parent.width
          text: root.card ? Model.stripImages(root.card.description_html) : ""
          textFormat: Text.RichText
          linkColor: panel.accent
          color: panel.ink
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          lineHeight: 1.3
          onLinkActivated: function(link) { Qt.openUrlExternally(link) }
        }
      }

      // ------------------------------------------------ steps
      Column {
        visible: !!(root.card && (root.card.steps || []).length > 0)
        width: parent.width
        spacing: Style.space(4)

        PanelSeparator { foreground: panel.ink }
        PanelSectionHeader {
          text: "STEPS · " + root.progress.done + "/" + root.progress.total
          foreground: panel.ink
          fontFamily: panel.fontFamily
        }

        // Quiet determinate progress — the shell's meter shape and 160ms fill.
        Rectangle {
          width: parent.width
          height: Style.space(4)
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          color: panel.hairline

          Rectangle {
            width: root.progress.total > 0
              ? Math.round(parent.width * root.progress.done / root.progress.total)
              : 0
            height: parent.height
            radius: parent.radius
            color: Style.selectedStateColor(panel.ink, panel.accent)
            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          }
        }

        Repeater {
          model: root.card ? (root.card.steps || []) : []

          // A plain hover surface, not CursorSurface: steps aren't part of
          // the keyboard cursor set, and the kit's contract forbids driving
          // hasCursor from containsMouse. Chip-style own-control hover.
          delegate: Rectangle {
            id: stepRow
            required property var modelData
            width: body.width
            implicitHeight: stepText.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: stepArea.containsMouse
              ? Style.hoverFillFor(panel.ink, panel.accent)
              : "transparent"

            Behavior on color { ColorAnimation { duration: 60 } }

            Rectangle {
              id: check
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(14)
              height: width
              radius: width / 2
              color: stepRow.modelData.completed
                ? Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.9)
                : "transparent"
              border.width: Math.max(1, Style.normalBorderWidth)
              border.color: stepRow.modelData.completed ? panel.accent : panel.dim

              Behavior on color { ColorAnimation { duration: 140 } }

              Text {
                anchors.centerIn: parent
                visible: stepRow.modelData.completed
                text: "✓"
                color: Color.background
                font.pixelSize: Style.space(9)
                font.bold: true
              }
            }

            Text {
              id: stepText
              anchors.left: check.right
              anchors.leftMargin: Style.space(9)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: stepRow.modelData.content || ""
              color: stepRow.modelData.completed ? panel.dim : panel.ink
              font.family: panel.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.strikeout: stepRow.modelData.completed
              wrapMode: Text.Wrap

              Behavior on color { ColorAnimation { duration: 140 } }
            }

            MouseArea {
              id: stepArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: panel.toggleStep(stepRow.modelData)
            }
          }
        }
      }

      // ------------------------------------------------ people
      Column {
        visible: panel.users.length > 0
        width: parent.width
        spacing: Style.space(6)

        PanelSeparator { foreground: panel.ink }
        PanelSectionHeader { text: "PEOPLE"; foreground: panel.ink; fontFamily: panel.fontFamily }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: panel.users
            delegate: Chip {
              required property var modelData
              label: modelData.name
              active: Model.hasAssignee(root.card, modelData.id)
              accent: panel.accent
              foreground: panel.ink
              onClicked: panel.toggleAssignee(modelData)
            }
          }
        }
      }

      // ------------------------------------------------ tags
      Column {
        visible: panel.tags.length > 0
        width: parent.width
        spacing: Style.space(6)

        PanelSeparator { foreground: panel.ink }
        PanelSectionHeader { text: "TAGS"; foreground: panel.ink; fontFamily: panel.fontFamily }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: panel.tags
            delegate: Chip {
              required property var modelData
              label: "#" + modelData.title
              active: Model.hasTag(root.card, modelData.title)
              accent: panel.accent
              foreground: panel.ink
              onClicked: panel.toggleTag(modelData)
            }
          }
        }
      }

      // ------------------------------------------------ comments
      Column {
        width: parent.width
        spacing: Style.space(8)

        PanelSeparator { foreground: panel.ink }
        PanelSectionHeader {
          text: "COMMENTS" + (panel.cardComments.length > 0 ? " · " + panel.cardComments.length : "")
          foreground: panel.ink
          fontFamily: panel.fontFamily
        }

        Text {
          visible: panel.cardComments.length === 0
          text: panel.commentsLoading ? "Loading comments…" : "No comments yet"
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Button {
          visible: root.earlierCount > 0
          text: root.showAllComments
            ? "Show latest only"
            : "Show " + root.earlierCount + " earlier comment" + (root.earlierCount === 1 ? "" : "s")
          foreground: panel.dim
          fontSize: Style.font.bodySmall
          focusable: false
          onClicked: root.expandedFor = root.showAllComments ? "" : String(root.card.number)
        }

        Repeater {
          model: root.visibleComments

          delegate: Row {
            id: commentRow
            required property var modelData
            width: body.width
            spacing: Style.space(9)

            Rectangle {
              width: Style.space(20)
              height: width
              radius: width / 2
              color: Util.alpha(
                Model.avatarColor(commentRow.modelData.creator ? commentRow.modelData.creator.name : "", panel.lightTheme),
                0.35)

              Text {
                anchors.centerIn: parent
                text: Model.initials(commentRow.modelData.creator ? commentRow.modelData.creator.name : "")
                color: panel.ink
                font.family: panel.fontFamily
                font.pixelSize: Math.round(Style.font.caption * 0.85)
              }
            }

            Column {
              width: parent.width - Style.space(29)
              spacing: Style.space(2)

              Row {
                spacing: Style.space(6)

                Text {
                  text: commentRow.modelData.creator ? commentRow.modelData.creator.name : ""
                  color: panel.ink
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                }

                Text {
                  text: Model.relativeTime(commentRow.modelData.created_at, panel.nowTick)
                  color: panel.dim
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                width: parent.width
                text: Model.commentHtml(commentRow.modelData)
                textFormat: Text.RichText
                linkColor: panel.accent
                color: panel.ink
                font.family: panel.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.Wrap
                lineHeight: 1.25
                onLinkActivated: function(link) { Qt.openUrlExternally(link) }
              }
            }
          }
        }

        Row {
          visible: root.pendingComment !== ""
          width: body.width
          spacing: Style.space(9)

          SequentialAnimation on opacity {
            running: root.pendingComment !== ""
            loops: Animation.Infinite
            NumberAnimation { to: 0.45; duration: 420; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
          }

          Rectangle {
            width: Style.space(20)
            height: width
            radius: width / 2
            color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.3)

            Text {
              anchors.centerIn: parent
              text: "…"
              color: panel.ink
              font.family: panel.fontFamily
              font.pixelSize: Math.round(Style.font.caption * 0.85)
            }
          }

          Column {
            width: parent.width - Style.space(29)
            spacing: Style.space(2)

            Text {
              text: "Sending…"
              color: panel.dim
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
              font.weight: Font.DemiBold
            }

            Text {
              width: parent.width
              text: root.pendingComment
              color: panel.ink
              font.family: panel.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
              lineHeight: 1.25
            }
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: commentField
            width: parent.width - sendButton.width - Style.space(6)
            placeholderText: "Write a comment…"
            foreground: panel.ink
            font.family: panel.fontFamily
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.submitComment()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                commentField.text = ""
                panel.focusKeys()
                event.accepted = true
              }
            }
          }

          Button {
            id: sendButton
            anchors.verticalCenter: commentField.verticalCenter
            text: "Send"
            accent: panel.accent
            focusable: false
            onClicked: root.submitComment()
          }
        }
      }

      // ------------------------------------------------ footer
      Button {
        text: "Open in Fizzy  ↗"
        foreground: panel.dim
        fontSize: Style.font.bodySmall
        focusable: false
        onClicked: if (root.card && root.card.url) Qt.openUrlExternally(root.card.url)
      }
    }
  }
}
