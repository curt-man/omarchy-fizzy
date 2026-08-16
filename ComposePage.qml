import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The full composer: title, notes, destination, tags, people — one Create.
Item {
  id: root
  property var panel: null

  readonly property bool editorFocused: titleField.activeFocus || notesField.activeFocus

  property string destination: "maybe"      // "maybe" or a column id
  property var pickedTags: []               // tag titles
  property var pickedPeople: []             // user ids

  function reset(prefillTitle) {
    titleField.text = prefillTitle || ""
    notesField.text = ""
    destination = "maybe"
    pickedTags = []
    pickedPeople = []
    flick.contentY = 0
    titleField.forceActiveFocus()
  }

  function togglePick(list, value) {
    var next = list.slice()
    var at = next.indexOf(value)
    if (at >= 0) next.splice(at, 1)
    else next.push(value)
    return next
  }

  function submit() {
    if (String(titleField.text).trim() === "") return
    panel.createFullCard({
      title: String(titleField.text).trim(),
      description: String(notesField.text).trim(),
      columnId: destination === "maybe" ? "" : destination,
      tagTitles: pickedTags,
      assigneeIds: pickedPeople
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

    Column {
      id: body
      width: flick.width
      spacing: Style.space(14)

      TextField {
        id: titleField
        width: parent.width
        placeholderText: "Card title"
        foreground: panel.ink
        font.family: panel.fontFamily
        font.pixelSize: Style.font.body
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            notesField.forceActiveFocus()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            panel.popPage()
            event.accepted = true
          }
        }
      }

      Rectangle {
        width: parent.width
        height: Style.space(84)
        radius: Style.cornerRadius
        color: notesField.activeFocus
          ? Style.focusFillFor(panel.ink, panel.accent)
          : Style.normalFillFor(panel.ink, panel.accent)
        border.width: notesField.activeFocus ? Style.focusBorderWidth : 0
        border.color: Style.focusBorderFor(panel.ink, panel.accent)

        Behavior on color { ColorAnimation { duration: 80 } }
        Behavior on border.width { NumberAnimation { duration: 80 } }

        ScrollView {
          anchors.fill: parent
          anchors.margins: Style.space(4)

          TextArea {
            id: notesField
            placeholderText: "Notes (optional)"
            placeholderTextColor: panel.dim
            color: panel.ink
            font.family: panel.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: TextArea.Wrap
            background: null
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                panel.popPage()
                event.accepted = true
              }
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)

        PanelSectionHeader { text: "ADD TO"; foreground: panel.ink; fontFamily: panel.fontFamily }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Chip {
            label: "Maybe?"
            active: root.destination === "maybe"
            accent: panel.accent
            foreground: panel.ink
            onClicked: root.destination = "maybe"
          }

          Repeater {
            model: panel.columns
            delegate: Chip {
              required property var modelData
              label: modelData.name
              showDot: true
              dot: Model.columnColor(modelData, panel.lightTheme)
              active: root.destination === String(modelData.id)
              accent: Model.columnColor(modelData, panel.lightTheme)
              foreground: panel.ink
              onClicked: root.destination = String(modelData.id)
            }
          }
        }
      }

      Column {
        visible: panel.tags.length > 0
        width: parent.width
        spacing: Style.space(6)

        PanelSectionHeader { text: "TAGS"; foreground: panel.ink; fontFamily: panel.fontFamily }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: panel.tags
            delegate: Chip {
              required property var modelData
              label: "#" + modelData.title
              active: root.pickedTags.indexOf(modelData.title) >= 0
              accent: panel.accent
              foreground: panel.ink
              onClicked: root.pickedTags = root.togglePick(root.pickedTags, modelData.title)
            }
          }
        }
      }

      Column {
        visible: panel.users.length > 0
        width: parent.width
        spacing: Style.space(6)

        PanelSectionHeader { text: "PEOPLE"; foreground: panel.ink; fontFamily: panel.fontFamily }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: panel.users
            delegate: Chip {
              required property var modelData
              label: modelData.name
              active: root.pickedPeople.indexOf(modelData.id) >= 0
              accent: panel.accent
              foreground: panel.ink
              onClicked: root.pickedPeople = root.togglePick(root.pickedPeople, modelData.id)
            }
          }
        }
      }

      Row {
        spacing: Style.space(8)

        Button {
          text: panel.composeBusy ? "Creating…" : "Create card"
          accent: panel.accent
          selected: true
          focusable: false
          onClicked: root.submit()
        }

        Button {
          text: "Cancel"
          foreground: panel.dim
          focusable: false
          onClicked: panel.popPage()
        }
      }
    }
  }
}
