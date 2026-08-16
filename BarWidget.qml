import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "ryanyogan.fizzy"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh(true)
  }

  // Shape contract for shell.summon/hide/toggle routing.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property int badgeCount: panelLoader.item ? panelLoader.item.badgeCount : 0
  readonly property bool showBadge: setting("showBadge", true) === true
  readonly property bool badgeActive: showBadge && badgeCount > 0
  readonly property string badgeText: badgeCount > 99 ? "99+" : String(badgeCount)

  // Right-click persists the toggle through the bar CLI; shell.json
  // hot-reloads, so the count cell animates open or closed in place.
  // Util.execDetached wants a single shell string, not an argv array.
  function toggleBadgeSetting() {
    Util.execDetached("omarchy-bar set " + Util.shellQuote(root.moduleName)
      + " showBadge " + (root.showBadge ? "false" : "true") + " --json")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The bar's open-panel pill should track the painted glyph+count, not the slot.
  readonly property real openPanelIndicatorWidth: content.visible ? content.width : 0

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The mark is the plugin's own FizzyIcon (no font dependence); the
    // count cell beside it animates independently inside a reserved slot.
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1
      : Math.round(content.implicitWidth + Style.spaceReal(8.5) * 2)
    tooltipText: (root.badgeCount > 0 && root.showBadge
      ? root.badgeCount + " card" + (root.badgeCount === 1 ? "" : "s") + " in Maybe?"
      : "Fizzy") + " — right-click toggles the count"

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton) root.toggleBadgeSetting()
      else root.togglePanel()
    }

    TextMetrics {
      id: countMetrics
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      text: root.badgeText
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: 0

      FizzyIcon {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: Style.bar.iconCanvas
        tint: button.foreground
        animate: false
      }

      // Count cell: measured, gap included, so it collapses to nothing in one
      // smooth motion at zero and never nudges neighbors between digits.
      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: root.badgeActive ? Math.ceil(countMetrics.advanceWidth) + Style.space(5) : 0
        height: countText.implicitHeight
        clip: true
        visible: width > 0 && !root.vertical

        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Text {
          id: countText
          anchors.right: parent.right
          text: root.badgeText
          color: Qt.darker(button.foreground, 1.25)
          font.family: button.fontFamily
          font.pixelSize: button.fontSize

          // Qt's documented fade idiom: dip out, swap the value, fade in.
          Behavior on text {
            SequentialAnimation {
              NumberAnimation { target: countText; property: "opacity"; to: 0; duration: 70; easing.type: Easing.InQuad }
              PropertyAction { }
              NumberAnimation { target: countText; property: "opacity"; to: 1; duration: 110; easing.type: Easing.OutQuad }
            }
          }
        }
      }
    }
  }
}
