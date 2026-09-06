import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

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

  // Cards waiting in Maybe? tint the widget, the way unread mail or messages
  // tint the other bar widgets. The color is the bar's own activeColor, not a
  // choice this plugin makes, so a themed bar stays one palette.
  readonly property bool tintOnTriage: setting("tintOnTriage", true) !== false
  readonly property string tintTarget: String(setting("tintTarget", "icon and count"))
  readonly property bool triageWaiting: tintOnTriage && badgeCount > 0
  readonly property bool tintIcon: triageWaiting && tintTarget !== "count"
  readonly property bool tintCount: triageWaiting && tintTarget !== "icon"

  // Which mark sits in the bar. "bubbles" is this plugin's own drawing and
  // tints like every other bar glyph; the logo options are Fizzy's real icon,
  // and "logo in color" keeps its own gradients — which means the triage tint
  // then has only the count left to color.
  // Same setting the panel reads, resolved the same way, so the mark in the
  // bar and the panel it opens are one color.
  readonly property string tintColor: String(setting("tintColor", "bar active"))
  readonly property color tintPaint: Model.themeColor(
    tintColor, root.bar ? root.bar.urgent : Color.urgent, Color.accent, Color.urgent)

  readonly property string barIcon: String(setting("barIcon", "bubbles"))
  readonly property bool brandIcon: barIcon === "logo in color"
  readonly property string iconMark: barIcon === "bubbles" ? "bubbles" : "logo"

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
    // WidgetButton defaults this to the bar's active color; the setting can
    // point it at another of the theme's tokens instead.
    activeColor: root.tintPaint
    // The mark is the plugin's own FizzyIcon (no font dependence); the
    // count cell beside it animates independently inside a reserved slot.
    text: ""
    labelVisible: false
    hasVisualContent: true
    // A brand-colored mark can't carry the tint, so the pill would be the only
    // thing reacting: leave it to the count in that mode.
    active: root.triageWaiting && root.tintTarget === "icon and count" && !root.brandIcon
    fixedWidth: root.vertical ? -1
      : Math.round(content.implicitWidth + Style.spaceReal(8.5) * 2)
    readonly property string badgeLabel:
      panelLoader.item ? panelLoader.item.badgeLabel : "in Maybe?"
    tooltipText: (root.badgeCount > 0 && root.showBadge
      ? root.badgeCount + " card" + (root.badgeCount === 1 ? "" : "s") + " " + badgeLabel
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
        mark: root.iconMark
        brand: root.brandIcon
        tint: root.tintIcon ? button.activeColor : button.foreground
        animate: false

        Behavior on tint { ColorAnimation { duration: 180 } }
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
          // The count sits a shade back from the mark when it is plain status
          // text; tinted, it carries the full color like any other alert.
          color: root.tintCount ? button.activeColor : Qt.darker(button.foreground, 1.25)
          font.family: button.fontFamily
          font.pixelSize: button.fontSize

          // The count cell also animates its width open at the same moment;
          // easing the color keeps the two from arriving out of step.
          Behavior on color { ColorAnimation { duration: 180 } }

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
