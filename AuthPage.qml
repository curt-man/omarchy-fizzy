import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var panel: null

  readonly property bool editorFocused: tokenField.activeFocus

  // Keyboard-first everywhere else, so land ready to paste. Escape still
  // closes the panel from inside the field.
  readonly property bool active: panel && panel.page === "auth"
  onActiveChanged: if (active) Qt.callLater(function() { tokenField.forceActiveFocus() })
  Component.onCompleted: if (active) tokenField.forceActiveFocus()

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: Style.space(8)
    spacing: Style.space(12)

    Text {
      width: parent.width
      text: "Bring your boards to the bar"
      color: panel.ink
      font.family: panel.fontFamily
      font.pixelSize: Style.font.subtitle
      font.weight: Font.DemiBold
      wrapMode: Text.Wrap
    }

    Text {
      width: parent.width
      text: "Fizzy needs a personal access token with read + write. In Fizzy, open Settings → API Tokens, create one, and paste it below. It lives only on this machine, in a file no other user can read."
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      lineHeight: 1.25
    }

    Button {
      text: "Open Fizzy settings  ↗"
      accent: panel.accent
      focusable: false
      onClicked: Qt.openUrlExternally("https://app.fizzy.do")
    }

    PanelSeparator { foreground: panel.ink }

    TextField {
      id: tokenField
      width: parent.width
      placeholderText: "Paste your access token"
      password: true
      foreground: panel.ink
      font.family: panel.fontFamily
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          panel.connectWithToken(tokenField.text)
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          panel.close()
          event.accepted = true
        }
      }
    }

    Row {
      spacing: Style.space(8)

      Button {
        text: panel.busy ? "Connecting…" : "Connect"
        accent: panel.accent
        selected: true
        focusable: false
        onClicked: panel.connectWithToken(tokenField.text)
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: panel.notice !== ""
        text: panel.notice
        color: panel.busy ? panel.dim : panel.urgent
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
