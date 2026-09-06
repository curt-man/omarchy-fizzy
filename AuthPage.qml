import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root
  property var panel: null

  readonly property bool editorFocused: addressField.activeFocus || tokenField.activeFocus

  // What "Open Fizzy ↗" and Connect act on: whatever is in the field, cleaned
  // up, falling back to the saved instance while the field is mid-edit.
  readonly property string typedAddress: Model.normalizeBaseUrl(addressField.text)
  readonly property string openAddress: typedAddress !== "" ? typedAddress : panel.baseUrl

  // Keyboard-first everywhere else, so land ready to paste. Escape still
  // closes the panel from inside the field.
  readonly property bool active: panel && panel.page === "auth"
  onActiveChanged: if (active) reset()
  Component.onCompleted: if (active) reset()

  // The address is nearly always right already (it is the saved one, or the
  // default), so the token field is where the cursor belongs.
  function reset() {
    addressField.text = panel.baseUrl
    Qt.callLater(function() { tokenField.forceActiveFocus() })
  }

  function submit() {
    panel.connectWithToken(tokenField.text, addressField.text)
  }

  function dismiss() {
    if (panel.authPagePinned) panel.leaveConnectPage()
    else panel.close()
  }

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: Style.space(8)
    spacing: Style.space(10)

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

    PanelSeparator { foreground: panel.ink }

    Column {
      width: parent.width
      spacing: Style.space(6)

      PanelSectionHeader { text: "FIZZY ADDRESS"; foreground: panel.ink; fontFamily: panel.fontFamily }

      TextField {
        id: addressField
        width: parent.width
        placeholderText: panel.defaultBaseUrl
        foreground: panel.ink
        font.family: panel.fontFamily
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            tokenField.forceActiveFocus()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          }
        }
      }

      Text {
        width: parent.width
        text: "Your own instance, or app.fizzy.do. https:// is assumed."
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(6)

      PanelSectionHeader { text: "ACCESS TOKEN"; foreground: panel.ink; fontFamily: panel.fontFamily }

      TextField {
        id: tokenField
        width: parent.width
        placeholderText: "Paste your access token"
        password: true
        foreground: panel.ink
        font.family: panel.fontFamily
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.submit()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          }
        }
      }

      // A token authenticates against one host, so moving instances means a
      // new token — reusing the old one would hand it to a different server.
      Text {
        visible: panel.authPagePinned
        width: parent.width
        text: "Tokens belong to one instance — paste one created on the address above."
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }
    }

    Button {
      text: "Open " + Model.baseUrlLabel(root.openAddress) + "  ↗"
      accent: panel.accent
      focusable: false
      onClicked: Qt.openUrlExternally(root.openAddress)
    }

    Row {
      spacing: Style.space(8)

      Button {
        text: panel.busy ? "Connecting…" : "Connect"
        accent: panel.accent
        selected: true
        focusable: false
        onClicked: root.submit()
      }

      Button {
        visible: panel.authPagePinned
        text: "Cancel"
        foreground: panel.dim
        focusable: false
        onClicked: panel.leaveConnectPage()
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: panel.notice !== ""
        text: panel.notice
        color: panel.busy ? panel.dim : panel.urgent
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
        width: Math.max(0, root.width - x)
        wrapMode: Text.Wrap
      }
    }
  }
}
