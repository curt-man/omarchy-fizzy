import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root
  property var panel: null

  readonly property bool editorFocused: quickAdd.activeFocus

  // Filters synthetic hover churn while the list scrolls under a resting
  // pointer, so keyboard and mouse never fight over the cursor.
  property PointerMoveGate gate: PointerMoveGate { referenceItem: cardList }
  function resetGate() { gate.reset() }

  function focusComposer() { quickAdd.forceActiveFocus() }

  Column {
    anchors.fill: parent
    spacing: Style.space(10)

    // Filter chips: Maybe? · columns · Not Now · Done
    Flickable {
      id: chipScroller
      width: parent.width
      height: chipRow.implicitHeight
      contentWidth: chipRow.implicitWidth
      contentHeight: height
      clip: true
      interactive: contentWidth > width
      boundsBehavior: Flickable.StopAtBounds

      // h/l and 1-9 can activate a chip that sits scrolled out of view;
      // glide the row so the active filter is always on screen.
      function revealActive() {
        for (var i = 0; i < chipRepeater.count; i++) {
          var chip = chipRepeater.itemAt(i)
          if (!chip || !chip.active) continue
          var target = contentX
          if (chip.x < contentX) target = chip.x
          else if (chip.x + chip.width > contentX + width) target = chip.x + chip.width - width
          revealAnim.to = Math.max(0, Math.min(target, contentWidth - width))
          revealAnim.restart()
          return
        }
      }

      NumberAnimation {
        id: revealAnim
        target: chipScroller
        property: "contentX"
        duration: 160
        easing.type: Easing.OutCubic
      }

      Connections {
        target: root.panel
        function onActiveFilterKeyChanged() { chipScroller.revealActive() }
      }

      Row {
        id: chipRow
        spacing: Style.space(6)
        height: parent.height

        Repeater {
          id: chipRepeater
          model: panel.filters
          delegate: Chip {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            label: modelData.label
            count: modelData.count
            dot: modelData.dot || "transparent"
            showDot: modelData.dot !== ""
            active: modelData.key === panel.activeFilterKey
            // A column's chip glows in its own Fizzy color when active.
            accent: modelData.dot !== "" ? modelData.dot : panel.accent
            foreground: panel.ink
            onClicked: panel.selectFilter(modelData.key)
          }
        }
      }
    }

    // Card list fills the fixed body; empty states live inside it.
    Item {
      width: parent.width
      height: parent.height - y - composerRow.height - Style.space(20)

      ListView {
        id: cardList
        anchors.fill: parent
        clip: true
        spacing: Style.space(6)
        model: panel.visibleCards
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        cacheBuffer: Style.space(120)
        reuseItems: true

        // Keep the keyboard cursor on screen; Contain only scrolls when the
        // row is actually clipped. Imperative rather than a currentIndex
        // binding — ListView writes currentIndex internally on model resets,
        // which would silently sever the binding.
        Connections {
          target: root.panel
          function onCardCursorChanged() {
            if (root.panel.cardCursor >= 0)
              cardList.positionViewAtIndex(root.panel.cardCursor, ListView.Contain)
          }
        }

        add: Transition {
          NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
          NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 160; easing.type: Easing.OutCubic }
        }
        // Filter switches replace the whole model; rows cascade in with a
        // tiny stagger instead of blinking into place.
        populate: Transition {
          id: populateTransition
          SequentialAnimation {
            PropertyAction { property: "opacity"; value: 0 }
            PauseAnimation { duration: Math.min(populateTransition.ViewTransition.index, 6) * 25 }
            NumberAnimation { property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutCubic }
          }
        }
        displaced: Transition {
          NumberAnimation { properties: "x,y"; duration: 160; easing.type: Easing.OutCubic }
        }
        remove: Transition {
          NumberAnimation { property: "opacity"; to: 0; duration: 140; easing.type: Easing.OutCubic }
          NumberAnimation { property: "scale"; to: 0.96; duration: 140; easing.type: Easing.OutCubic }
        }

        delegate: CardRow {
          required property var modelData
          required property int index
          width: cardList.width
          panel: root.panel
          card: modelData
          rowIndex: index
          gate: root.gate
          onOpenRequested: panel.openCard(modelData)
        }
      }

      // Empty state: the brand's bubbles drifting over one dim line naming
      // the cause (and the fix when there is one); spinner while loading.
      Column {
        anchors.centerIn: parent
        visible: panel.visibleCards.length === 0
        spacing: Style.space(12)

        FizzyIcon {
          anchors.horizontalCenter: parent.horizontalCenter
          iconSize: Style.font.displayLarge
          mark: panel.iconMark
          brand: panel.brandIcon
          tint: panel.dim
          animate: parent.visible && panel.opened && !panel.loadingCards
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Text {
            visible: panel.loadingCards
            anchors.verticalCenter: parent.verticalCenter
            text: "󰦖"
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body

            RotationAnimator on rotation {
              running: panel.loadingCards && panel.visibleCards.length === 0
              from: 0
              to: 360
              duration: 800
              loops: Animation.Infinite
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: panel.loadingCards ? "Loading cards…"
              : panel.offline ? "Can't reach Fizzy — press r to retry"
              : panel.activeFilterKey === "maybe" ? "Maybe? is empty — nice"
              : panel.activeFilterKey === "closed" ? "Nothing done yet"
              : panel.activeFilterKey === "not_now" ? "Nothing waiting for later"
              : "No cards in this column"
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }

    // Quick capture: one full-width field; the composer affordance lives
    // inside its right edge, so nothing floats beside the input.
    Item {
      id: composerRow
      width: parent.width
      height: quickAdd.implicitHeight

      TextField {
        id: quickAdd
        anchors.fill: parent
        placeholderText: "Add to Maybe? …"
        foreground: panel.ink
        font.family: panel.fontFamily
        rightPadding: moreButton.width + Style.space(10)
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            var title = quickAdd.text
            quickAdd.text = ""
            panel.createQuickCard(title, function(ok) {
              // Offline capture must not eat the title — hand it back.
              if (!ok && quickAdd.text === "") quickAdd.text = title
            })
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            quickAdd.text = ""
            panel.focusKeys()
            event.accepted = true
          }
        }
      }

      PanelActionButton {
        id: moreButton
        anchors.right: parent.right
        anchors.rightMargin: Style.space(3)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅂"
        tooltipText: "Full composer — notes, column, tags, people"
        foreground: panel.dim
        onClicked: panel.openCompose(quickAdd.text)
      }
    }
  }
}
