import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Everything the widget can be told, on the page it belongs on. Writes go
// straight to the shell's settings store through panel.setSetting, so this,
// `omarchy bar set`, and the shell's own settings UI all edit one thing —
// nothing here keeps a second copy of the truth.
Item {
  id: root
  property var panel: null

  readonly property real rowWidth: width

  // A choice row: a caption and the options it picks between. Used for every
  // setting that isn't a yes or no.
  component ChoiceRow: Column {
    id: choice
    property string title: ""
    property string key: ""
    property var choices: []
    property string current: ""

    width: root.rowWidth
    spacing: Style.space(6)

    PanelSectionHeader {
      text: choice.title
      foreground: root.panel.ink
      fontFamily: root.panel.fontFamily
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: choice.choices
        delegate: Chip {
          required property var modelData
          label: modelData.label
          active: String(choice.current) === String(modelData.value)
          accent: root.panel.accent
          foreground: root.panel.ink
          fontFamily: root.panel.fontFamily
          onClicked: root.panel.setSetting(choice.key, modelData.value)
        }
      }
    }
  }

  component SettingToggle: Toggle {
    width: root.rowWidth
    foreground: root.panel.ink
    accent: root.panel.accent
    fontFamily: root.panel.fontFamily
    titleSize: Style.font.body
    descriptionSize: Style.font.caption
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

      // ---------------------------------------------------------- instance
      Column {
        width: parent.width
        spacing: Style.space(6)

        PanelSectionHeader {
          text: "INSTANCE"
          foreground: root.panel.ink
          fontFamily: root.panel.fontFamily
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - switchButton.width - Style.space(8)
            text: root.panel.instanceLabel
            color: root.panel.ink
            font.family: root.panel.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Button {
            id: switchButton
            anchors.verticalCenter: parent.verticalCenter
            text: "Switch…"
            accent: root.panel.accent
            focusable: false
            onClicked: root.panel.openConnectPage()
          }
        }
      }

      PanelSeparator { foreground: root.panel.ink }

      // -------------------------------------------------------- bar badge
      ChoiceRow {
        title: "BAR ICON"
        key: "barIcon"
        current: root.panel.barIcon
        choices: [
          { label: "Bubbles", value: "bubbles" },
          { label: "Fizzy logo", value: "logo" },
          { label: "Fizzy logo in color", value: "logo in color" }
        ]
      }

      SettingToggle {
        label: "Show the count"
        description: "A number beside the mark in the bar."
        checked: root.panel.showBadge
        onClicked: root.panel.setSetting("showBadge", !root.panel.showBadge)
      }

      ChoiceRow {
        title: "WHAT IT COUNTS"
        key: "badgeSource"
        current: root.panel.badgeSource
        choices: [
          { label: "Maybe?", value: "maybe" },
          { label: "Assigned to me", value: "assigned to me" },
          { label: "In play", value: "in play" },
          { label: "All open", value: "all open" }
        ]
      }

      SettingToggle {
        label: "Tint while cards wait"
        description: "Colors the widget while cards sit in triage, the way unread mail tints its own."
        checked: root.panel.tintOnTriage
        onClicked: root.panel.setSetting("tintOnTriage", !root.panel.tintOnTriage)
      }

      ChoiceRow {
        title: "THE PLUGIN'S COLOR"
        key: "tintColor"
        current: root.panel.tintColor
        choices: [
          { label: "Bar's active", value: "bar active" },
          { label: "Theme accent", value: "accent" },
          { label: "Theme urgent", value: "urgent" }
        ]
      }

      ChoiceRow {
        // A brand-colored mark paints its own gradients, so the tint has
        // nothing left to color but the number.
        visible: root.panel.tintOnTriage && !root.panel.brandIcon
        title: "WHAT THE TINT COLORS"
        key: "tintTarget"
        current: root.panel.tintTarget
        choices: [
          { label: "Icon and count", value: "icon and count" },
          { label: "Count", value: "count" },
          { label: "Icon", value: "icon" }
        ]
      }

      PanelSeparator { foreground: root.panel.ink }

      // ------------------------------------------------------------ panel
      SettingToggle {
        label: "Show people's avatars"
        description: "Draws each person's Fizzy avatar instead of their initials. "
          + "Off, nothing is ever fetched from " + root.panel.instanceLabel + " but the API."
        checked: root.panel.showAvatars
        onClicked: root.panel.setSetting("showAvatars", !root.panel.showAvatars)
      }

      ChoiceRow {
        title: "BACKGROUND REFRESH"
        key: "refreshIntervalSec"
        current: String(root.panel.refreshIntervalSec)
        choices: [
          { label: "1 min", value: 60 },
          { label: "5 min", value: 300 },
          { label: "10 min", value: 600 },
          { label: "30 min", value: 1800 }
        ]
      }
    }
  }
}
