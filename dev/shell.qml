import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// No `import qs.Ui` here, deliberately: the shell's Ui module also exports a
// type called Panel, and importing it would shadow this plugin's Panel.qml —
// the harness would then quietly build the base class instead of the widget it
// is supposed to be photographing.

// Development harness: the real panel, on fixture data.
//
//   dev/run.sh                 # start it
//   dev/shot.sh out.png        # photograph what it is drawing
//   dev/showcase.sh            # the README images, in one pass
//
// This loads Panel.qml itself rather than a copy of its parts, so what is
// being looked at is the panel the shell would host — the same layout, the
// same key handling, the same requests. Two things differ: the bar underneath
// it is a stub declared here, and `demo` is on, which makes fizzy-fetch answer
// every read from fizzy-demo.json and refuse every write.
//
// It is its own Quickshell instance. Your bar, your shell.json and your Fizzy
// account are not involved at any point — the panel cannot reach them, because
// in demo mode it neither reads nor writes the config file and never opens a
// connection to any instance.
ShellRoot {
  id: harness

  // The panel is anchored to a bar widget it does not have here. This stands
  // in for one: enough surface for KeyboardPanel to place and coordinate a
  // popup, and nothing that reaches a real bar.
  PanelWindow {
    id: stageWindow
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; left: true; right: true }
    implicitHeight: 1

    // The anchor: a zero-size item near the middle of the top edge, which is
    // where a bar widget would be.
    Item {
      id: anchor
      width: 1
      height: 1
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
    }
  }

  QtObject {
    id: stubBar

    readonly property string position: "top"
    readonly property int barSize: 1
    readonly property color foreground: Color.foreground
    readonly property color barForeground: Color.bar.text
    readonly property color urgent: Color.bar.active
    readonly property string fontFamily: Style.font.family
    readonly property var clickTargets: []
    property var activePopout: null

    function requestPopout(key) { activePopout = key }
    function releasePopout(key) { if (activePopout === key) activePopout = null }
    function targetBelongsToWindow() { return false }
    function switchPanelFrom() { return false }
  }

  Panel {
    id: panel

    bar: stubBar
    anchorItem: anchor
    demo: true

    // The settings the bar entry would carry. Avatars on and the logo mark
    // chosen, because those are the parts of the widget a picture has to show;
    // nobody in the fixtures has a photo, so every seat is still an initials
    // disc drawn locally.
    settings: ({
      showAvatars: true,
      showBadge: true,
      barIcon: "logo",
      tintColor: "bar active",
      tintOnTriage: true
    })

    // Demo config stands in for the file the panel would normally read: an
    // account slug so requests are addressed, and the board to land on.
    Component.onCompleted: {
      panel.config = {
        token: "demo",
        account_slug: "1",
        base_url: "https://fizzy.example",
        board_id: "demo-board-1",
        user_id: "demo-user-1"
      }
      panel.configLoaded = true
      panel.open()
    }
  }

  IpcHandler {
    id: dev
    target: "dev"

    function tree(): string {
      var out = []
      harness.walk(panel, 0, out)
      return out.join("\n")
    }

    function state(): string {
      var item = harness.cardItem()
      return panel.page + " opened=" + panel.opened
        + " cards=" + panel.visibleCards.length
        + " card=" + (item ? Math.round(item.width) + "x" + Math.round(item.height) : "none")
    }

    // Photograph the panel's card — the rounded surface, not the full-screen
    // layer under it, which is transparent and would grab as a mostly empty
    // image the size of the display.
    function shot(path: string): string {
      var item = harness.cardItem()
      if (!item) return "no card"
      item.grabToImage(function(result) { result.saveToFile(path) })
      return "ok"
    }

    function open(number: string): string {
      var cards = panel.visibleCards
      for (var i = 0; i < cards.length; i++) {
        if (String(cards[i].number) === String(number)) {
          panel.openCard(cards[i])
          return "ok"
        }
      }
      return "no card " + number
    }

    function page(name: string): string {
      if (name === "boards") { panel.page = "boards"; panel.loadBoards() }
      else if (name === "settings") panel.openSettingsPage()
      else if (name === "compose") panel.openCompose("")
      else panel.page = name
      return panel.page
    }

    function filter(key: string): string {
      panel.activeFilterKey = key
      panel.cardCursor = 0
      return key
    }

    function cursor(index: string): string {
      panel.cardCursor = parseInt(index, 10)
      return String(panel.cardCursor)
    }

    // Card pages are taller than the panel; a screenshot of the comments
    // needs the page scrolled to them first.
    function scroll(steps: string): string {
      var n = parseInt(steps, 10) || 0
      for (var i = 0; i < Math.abs(n); i++) panel.scrollCardBy(n > 0 ? 1 : -1)
      return steps
    }

    function help(on: string): string {
      panel.helpVisible = on !== "off"
      return String(panel.helpVisible)
    }

    function setting(key: string, value: string): string {
      var next = ({})
      for (var have in panel.settings) next[have] = panel.settings[have]
      next[key] = value === "true" ? true : value === "false" ? false : value
      panel.settings = next
      return key + "=" + value
    }
  }

  // The grabbed item is found by walking down from the panel rather than by
  // name: KeyboardPanel keeps its card private, and not reaching into that
  // file's internals is what lets it change without breaking the harness.
  //
  // The walk goes through `data`, not `children`: the panel's window is not an
  // Item, so it does not appear in `children` at all, and a search that only
  // looks there finds nothing however deep it goes.
  function cardItem() {
    return harness.findCard(panel, 0, 0)
  }

  function walk(node, depth, out) {
    if (!node || depth > 5) return
    var label = ""
    try { label = node.toString() } catch (e) { label = "?" }
    var size = ""
    try { size = (node.width !== undefined ? Math.round(node.width) + "x" + Math.round(node.height) : "") } catch (e) {}
    var rad = ""
    try { rad = (node.radius !== undefined ? " r=" + node.radius : "") } catch (e) {}
    out.push(Array(depth + 1).join("  ") + label.split("(")[0] + " " + size + rad)
    var next = []
    try { if (node.contentItem) next.push(node.contentItem) } catch (e) {}
    var kids = null
    try { kids = node.data !== undefined ? node.data : node.children } catch (e) {}
    if (kids) for (var i = 0; i < kids.length; i++) next.push(kids[i])
    for (var j = 0; j < next.length; j++) harness.walk(next[j], depth + 1, out)
  }

  function findCard(node, depth, limit) {
    if (!node || depth > 8) return null

    var w = 0, h = 0
    try { w = node.width || 0; h = node.height || 0 } catch (e) {}

    // The card is the first item inside the full-screen layer surface that is
    // meaningfully smaller than it: the surface spans the display, the card is
    // the rounded panel drawn inside it. Matching on geometry rather than on a
    // type name keeps this working when KeyboardPanel's internals change — and
    // a radius test does not, because a theme is free to set corners to 0.
    if (limit > 0 && w > 120 && h > 120 && w < limit * 0.9)
      return node

    var next = []
    try { if (node.contentItem) next.push(node.contentItem) } catch (e) {}
    var kids = null
    try { kids = node.data !== undefined ? node.data : node.children } catch (e) {}
    if (kids) for (var i = 0; i < kids.length; i++) next.push(kids[i])

    var inner = w > limit ? w : limit
    for (var j = 0; j < next.length; j++) {
      var found = harness.findCard(next[j], depth + 1, inner)
      if (found) return found
    }
    return null
  }
}
