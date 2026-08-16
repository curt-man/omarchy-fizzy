import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ryanyogan.fizzy"
  ipcTarget: "ryanyogan.fizzy"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---------------------------------------------------------------- lifecycle

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh(false)
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh(false)
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---------------------------------------------------------------- theming

  // lightTheme only picks which variant of Fizzy's own column palette to use;
  // every shell color below is a live binding to theme tokens.
  readonly property bool lightTheme:
    0.2126 * Color.background.r + 0.7152 * Color.background.g + 0.0722 * Color.background.b > 0.5
  readonly property color ink: root.bar ? root.bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(ink, 1.5)
  readonly property color hairline: Util.alpha(ink, 0.12)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // ---------------------------------------------------------------- config

  readonly property string configPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/fizzy.json"
  // resolvedUrl percent-encodes path segments; decode or a home dir with a
  // space yields a helper path that doesn't exist.
  readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("fizzy-fetch").toString().replace(/^file:\/\//, ""))

  property var config: ({})
  property bool configLoaded: false
  readonly property bool hasToken: !!(config && config.token)
  readonly property bool authed: hasToken && !!(config && config.account_slug)
  readonly property string boardId: config && config.board_id ? String(config.board_id) : ""
  readonly property string boardName: {
    for (var i = 0; i < boards.length; i++)
      if (String(boards[i].id) === boardId) return boards[i].name
    return ""
  }

  onConfigLoadedChanged: if (configLoaded) Qt.callLater(function() { root.refresh(false) })

  property FileView configFile: FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.config = Model.parseJson(text(), {})
      root.configLoaded = true
    }
    onLoadFailed: {
      root.config = ({})
      root.configLoaded = true
    }
  }

  property var pendingConfig: null
  property var afterSave: null

  // First write must not race file creation with default permissions: create
  // the file 0600 before FileView ever writes the token into it.
  Process {
    id: secureProc
    running: false
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0 && root.pendingConfig) {
        root.configFile.setText(JSON.stringify(root.pendingConfig, null, 2) + "\n")
        root.config = root.pendingConfig
        root.pendingConfig = null
        root.onConfigSaved()
      } else if (exitCode !== 0) {
        root.notice = "Could not write config file"
        root.pendingConfig = null
        root.afterSave = null
      }
    }
  }

  function saveConfig(values) {
    // Base on pendingConfig when a save is already in flight, so back-to-back
    // saves can't rebuild from stale state and drop the first save's keys.
    var base = pendingConfig || config
    var next = ({})
    for (var key in base) next[key] = base[key]
    for (var value in values) {
      if (values[value] === null) delete next[value]
      else next[value] = values[value]
    }
    pendingConfig = next
    secureProc.command = ["bash", "-c",
      'if [ -e "$1" ]; then chmod 600 -- "$1"; else install -D -m600 /dev/null "$1"; fi',
      "fizzy-config", configPath]
    secureProc.running = true
  }

  function onConfigSaved() {
    var callback = afterSave
    afterSave = null
    if (callback) callback()
  }

  // ---------------------------------------------------------------- api queue

  // Three workers let a board refresh's GETs land together. Anything that
  // writes (non-GET) runs alone after the queue drains, so an optimistic
  // mutation can never race a concurrent reload back to stale data.
  property var apiQueue: []
  // Mirrors apiQueue.length: mutating a var array never notifies bindings,
  // so `busy` tracks this int instead of the array.
  property int apiQueued: 0
  property int apiActive: 0
  property bool apiMutationRunning: false
  property bool busy: apiActive > 0 || apiQueued > 0
  property bool offline: false
  // Set when Fizzy rejects the token; gates refresh and the background poll
  // so a revoked token can't ping-pong between the board and auth pages.
  property bool tokenRejected: false

  // The activity sweep only appears for requests that outlast a blink, so
  // quick actions never flash it.
  property bool busyVisible: false
  Timer {
    id: busyDelay
    interval: 250
    onTriggered: root.busyVisible = root.busy
  }
  onBusyChanged: {
    if (busy) busyDelay.restart()
    else { busyDelay.stop(); busyVisible = false }
  }

  function api(method, path, body, paginate, callback) {
    apiQueue.push({ method: method, path: path, body: body, paginate: paginate, callback: callback })
    apiQueued = apiQueue.length
    pumpApi()
  }

  function pumpApi() {
    while (apiQueue.length > 0) {
      if (apiMutationRunning) return
      var isMutation = apiQueue[0].method !== "GET"
      if (isMutation && apiActive > 0) return
      var worker = workerA.idle ? workerA : (workerB.idle ? workerB : (workerC.idle ? workerC : null))
      if (!worker) return
      var request = apiQueue.shift()
      apiQueued = apiQueue.length
      apiMutationRunning = isMutation
      worker.start(request)
      if (isMutation) return
    }
  }

  function apiFinished(worker, exitCode, stdoutText, stderrText) {
    var request = worker.request
    if (!request) return   // watchdog already settled this worker
    worker.request = null
    apiActive--
    if (request.method !== "GET") apiMutationRunning = false
    if (exitCode === 0) offline = false
    else if (exitCode === 1) offline = true
    if (request.callback) request.callback(exitCode === 0, stdoutText, exitCode, stderrText)
    if (exitCode === 4) {
      root.tokenRejected = true
      root.notice = "Fizzy rejected the token — paste a new one"
      root.page = "auth"
    }
    // Next tick: the worker's `running` flag may not have settled inside
    // onExited, and pump must see it idle.
    Qt.callLater(root.pumpApi)
  }

  component ApiWorker: Process {
    id: worker
    property var request: null
    readonly property bool idle: request === null && !running
    running: false
    command: []
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }

    function start(req) {
      request = req
      root.apiActive++
      var cmd = [root.helperPath]
      if (req.paginate) cmd.push("--paginate")
      cmd.push(req.method, req.path)
      if (req.body) cmd.push(JSON.stringify(req.body))
      command = cmd
      running = true
    }

    onExited: function(exitCode) { root.apiFinished(worker, exitCode, stdout.text, stderr.text) }

    // curl caps at 15s; this only fires if the process never ran at all
    // (helper missing/unexecutable), which would otherwise wedge the pool.
    property Timer watchdog: Timer {
      interval: 30000
      running: worker.request !== null
      onTriggered: {
        worker.running = false
        root.apiFinished(worker, 1, "", "fizzy: request watchdog expired")
      }
    }
  }

  ApiWorker { id: workerA }
  ApiWorker { id: workerB }
  ApiWorker { id: workerC }

  // ---------------------------------------------------------------- data

  property var boards: []
  property var columns: []
  property var openCards: []
  property var notNowCards: []
  property var closedCards: []
  property var users: []
  property var tags: []
  property string activeFilterKey: "maybe"
  property string notice: ""
  property bool loadingCards: false

  property var cardDetail: null
  property var cardComments: []
  property string cardOriginKey: "maybe"
  property bool commentsLoading: false
  property bool composeBusy: false

  property int boardCursor: 0
  property int cardCursor: -1

  property real nowTick: Date.now()

  readonly property var grouped: Model.groupOpenCards(openCards)
  readonly property var filters: Model.buildFilters(columns, grouped, lightTheme)
  readonly property var visibleCards: Model.cardsForFilter(activeFilterKey, grouped, notNowCards, closedCards)
  readonly property int badgeCount: authed && boardId !== "" ? grouped.maybe.length : 0
  readonly property int inPlayCount: openCards.length - grouped.maybe.length

  Timer {
    interval: 60000
    running: root.opened
    repeat: true
    onTriggered: root.nowTick = Date.now()
  }

  // ---------------------------------------------------------------- navigation

  // Pages slide like a phone app: boards (root) → board → card / compose.
  property string page: "auth"
  property var pageStack: []
  property bool helpVisible: false
  onPageChanged: helpVisible = false

  function pageLevel(name) {
    if (name === "board") return 1
    if (name === "card" || name === "compose") return 2
    return 0
  }
  readonly property int currentLevel: pageLevel(page)

  function pushPage(name) {
    var stack = pageStack.slice()
    stack.push(page)
    pageStack = stack
    page = name
    // Opening a card by mouse can leave focus on a field in the now-hidden
    // page; hand keys back. Compose force-focuses its own title field.
    if (name === "card") Qt.callLater(focusKeys)
  }

  function popPage() {
    var stack = pageStack.slice()
    var previous = stack.pop()
    pageStack = stack
    page = previous || (boardId !== "" ? "board" : "boards")
    if (page === "board" || page === "boards") {
      cardDetail = null
      cardComments = []
    }
    // A page swap can leave focus on a field inside the now-hidden slot,
    // deadening every key including Escape — always hand it back.
    Qt.callLater(focusKeys)
  }

  function focusKeys() { keyCatcher.forceActiveFocus() }

  // Vim pending-key state: `g` waits briefly for a second `g`. Any other
  // interaction cancels it, so `g` `j` `g` can't be misread as `gg`.
  property string pendingVimKey: ""
  Timer {
    id: pendingKeyTimer
    interval: 600
    onTriggered: root.pendingVimKey = ""
  }

  function clearPendingVimKey() {
    pendingVimKey = ""
    pendingKeyTimer.stop()
  }

  function jumpToEdge(direction) {
    if (page === "board" && visibleCards.length > 0) {
      boardPageItem.resetGate()
      cardCursor = direction < 0 ? 0 : visibleCards.length - 1
    } else if (page === "boards" && boards.length > 0) {
      boardsPageItem.resetGate()
      boardCursor = direction < 0 ? 0 : boards.length - 1
    } else if (page === "card") {
      cardPageItem.scrollToEdge(direction)
    }
  }

  // Vim x: close the focused card straight from the list. Reversible in
  // Fizzy (Done → reopen), so no confirmation dialog.
  function closeCardAt(index) {
    if (activeFilterKey === "closed") return
    var card = visibleCards[index]
    if (!card) return
    // Reload on failure too: the optimistic removal below must not leave a
    // card vanished locally that never closed on the server.
    api("POST", "/{slug}/cards/" + card.number + "/closure", null, false,
      function(ok) { root.loadBoard() })
    mutationGen++
    lastCardsJson = ""
    openCards = openCards.filter(function(c) { return c.number !== card.number })
    notNowCards = notNowCards.filter(function(c) { return c.number !== card.number })
    if (cardCursor >= visibleCards.length) cardCursor = visibleCards.length - 1
  }

  // ---------------------------------------------------------------- loading

  function refresh(force) {
    if (!configLoaded) return
    if (!hasToken || tokenRejected) { page = "auth"; return }
    if (!authed) { resolveIdentity(); return }
    if (boards.length === 0 || force) loadBoards()
    if (page === "auth" || page === "") {
      page = boardId !== "" ? "board" : "boards"
      pageStack = []
      Qt.callLater(focusKeys)
    }
    if (boardId !== "") loadBoard()
    if (force && page === "card" && cardDetail) reloadCardDetail()
  }

  function resolveIdentity() {
    api("GET", "/my/identity", null, false, function(ok, out) {
      if (!ok) {
        // Leaving "Connecting…" up forever would read as a hang.
        root.notice = "Can't reach Fizzy — check your connection and try again"
        return
      }
      var accounts = Model.accountsFromIdentity(Model.parseJson(out, {}))
      if (accounts.length === 0) {
        root.notice = "No Fizzy accounts found for this token"
        return
      }
      root.afterSave = function() {
        root.notice = ""
        root.refresh(true)
      }
      root.saveConfig({ account_slug: accounts[0].slug })
    })
  }

  function loadBoards() {
    api("GET", "/{slug}/boards", null, true, function(ok, out) {
      if (ok) root.boards = Model.parseArray(out)
    })
  }

  // Raw response cache: skip the model reset (and its populate cascade)
  // when a background reload returns byte-identical data. Cleared by any
  // optimistic list edit so a failure-path reload always reasserts truth.
  property string lastCardsJson: ""

  function loadBoard() {
    if (boardId === "") return
    loadingCards = openCards.length === 0
    var gen = mutationGen
    api("GET", "/{slug}/boards/" + boardId + "/columns", null, true, function(ok, out) {
      if (ok) root.columns = Model.parseArray(out)
    })
    api("GET", "/{slug}/cards?board_ids%5B%5D=" + boardId, null, true, function(ok, out) {
      root.loadingCards = false
      // gen guard: a GET dispatched before an optimistic mutation must not
      // resurrect pre-mutation data after the local edit already applied.
      if (!ok || gen !== root.mutationGen) return
      if (out === root.lastCardsJson) return
      root.lastCardsJson = out
      root.openCards = Model.parseArray(out)
      if (root.cardCursor >= root.visibleCards.length)
        root.cardCursor = root.visibleCards.length - 1
    })
    loadDirectory()
    if (activeFilterKey === "not_now") loadNotNow()
    if (activeFilterKey === "closed") loadClosed()
  }

  function loadDirectory() {
    if (users.length === 0)
      api("GET", "/{slug}/users", null, true, function(ok, out) {
        if (ok) root.users = Model.parseArray(out).filter(function(user) { return user.active !== false })
      })
    if (tags.length === 0)
      api("GET", "/{slug}/tags", null, true, function(ok, out) {
        if (ok) root.tags = Model.parseArray(out)
      })
  }

  function loadNotNow() {
    var gen = mutationGen
    api("GET", "/{slug}/cards?board_ids%5B%5D=" + boardId + "&indexed_by=not_now", null, true, function(ok, out) {
      if (ok && gen === root.mutationGen) root.notNowCards = Model.parseArray(out)
    })
  }

  function loadClosed() {
    var gen = mutationGen
    api("GET", "/{slug}/cards?board_ids%5B%5D=" + boardId + "&indexed_by=closed", null, true, function(ok, out) {
      if (ok && gen === root.mutationGen) root.closedCards = Model.parseArray(out)
    })
  }

  function selectBoard(id) {
    root.afterSave = function() {
      root.openCards = []
      root.notNowCards = []
      root.closedCards = []
      root.columns = []
      root.activeFilterKey = "maybe"
      root.cardCursor = -1
      root.page = "board"
      root.pageStack = []
      root.loadBoard()
    }
    saveConfig({ board_id: String(id) })
  }

  function selectFilter(key) {
    activeFilterKey = key
    cardCursor = -1
    if (key === "not_now") loadNotNow()
    if (key === "closed") loadClosed()
  }

  function cycleFilter(step) {
    var keys = filters.map(function(filter) { return filter.key })
    var index = keys.indexOf(activeFilterKey)
    selectFilter(keys[(index + step + keys.length) % keys.length])
  }

  // ---------------------------------------------------------------- card page

  function openCard(card) {
    if (!card) return
    cardOriginKey = activeFilterKey
    cardDetail = card
    cardComments = []
    pushPage("card")
    reloadCardDetail()
  }

  // Bumped on every optimistic write so a detail GET that was already in
  // flight can't overwrite fresher local state with pre-mutation data.
  property int mutationGen: 0

  function reloadCardDetail() {
    if (!cardDetail) return
    var number = cardDetail.number
    var gen = mutationGen
    api("GET", "/{slug}/cards/" + number, null, false, function(ok, out) {
      if (!ok || gen !== root.mutationGen) return
      var detail = Model.parseJson(out, null)
      if (detail && root.cardDetail && root.cardDetail.number === number)
        root.cardDetail = detail
    })
    commentsLoading = true
    api("GET", "/{slug}/cards/" + number + "/comments", null, true, function(ok, out) {
      root.commentsLoading = false
      if (ok && root.cardDetail && root.cardDetail.number === number)
        root.cardComments = Model.parseArray(out)
    })
  }

  function afterCardMutation() {
    reloadCardDetail()
    loadBoard()
    if (cardOriginKey === "not_now") loadNotNow()
    if (cardOriginKey === "closed" || Model.cardPlace(cardDetail, cardOriginKey) === "closed") loadClosed()
  }

  function moveCard(target) {
    if (!cardDetail) return
    var number = cardDetail.number
    var done = function(ok) { if (ok) root.afterCardMutation() }
    if (target === "closed") api("POST", "/{slug}/cards/" + number + "/closure", null, false, done)
    else if (target === "reopen") api("DELETE", "/{slug}/cards/" + number + "/closure", null, false, done)
    else if (target === "not_now") api("POST", "/{slug}/cards/" + number + "/not_now", null, false, done)
    else if (target === "maybe") api("DELETE", "/{slug}/cards/" + number + "/triage", null, false, done)
    else api("POST", "/{slug}/cards/" + number + "/triage", { column_id: String(target) }, false, done)

    // Optimistic place change so the mover chips respond instantly.
    var next = JSON.parse(JSON.stringify(cardDetail))
    if (target === "closed") next.closed = true
    else {
      next.closed = false
      if (target === "maybe" || target === "not_now" || target === "reopen") delete next.column
      else {
        for (var i = 0; i < columns.length; i++)
          if (String(columns[i].id) === String(target)) next.column = columns[i]
      }
    }
    cardOriginKey = target === "not_now" ? "not_now" : (target === "closed" ? "closed" : "maybe")
    mutationGen++
    lastCardsJson = ""
    cardDetail = next
  }

  function toggleStep(step) {
    if (!cardDetail || !step) return
    var next = JSON.parse(JSON.stringify(cardDetail))
    var steps = next.steps || []
    for (var i = 0; i < steps.length; i++)
      if (steps[i].id === step.id) steps[i].completed = !steps[i].completed
    mutationGen++
    cardDetail = next
    api("POST", "/{slug}/cards/" + cardDetail.number + "/steps/" + step.id + "/toggle", null, false,
      function(ok) { if (!ok) root.reloadCardDetail() })
  }

  function toggleAssignee(user) {
    if (!cardDetail || !user) return
    var next = JSON.parse(JSON.stringify(cardDetail))
    var assignees = next.assignees || []
    if (Model.hasAssignee(next, user.id))
      next.assignees = assignees.filter(function(a) { return String(a.id) !== String(user.id) })
    else {
      assignees.push(user)
      next.assignees = assignees
    }
    mutationGen++
    cardDetail = next
    api("POST", "/{slug}/cards/" + cardDetail.number + "/assignments", { assignee_id: String(user.id) }, false,
      function(ok) { if (!ok) root.reloadCardDetail(); else root.loadBoard() })
  }

  function toggleTag(tag) {
    if (!cardDetail || !tag) return
    var next = JSON.parse(JSON.stringify(cardDetail))
    var titles = (next.tags || []).map(Model.tagTitle)
    if (Model.hasTag(next, tag.title))
      next.tags = titles.filter(function(t) { return t.toLowerCase() !== tag.title.toLowerCase() })
    else {
      titles.push(tag.title)
      next.tags = titles
    }
    mutationGen++
    cardDetail = next
    api("POST", "/{slug}/cards/" + cardDetail.number + "/taggings", { tag_title: tag.title }, false,
      function(ok) { if (!ok) root.reloadCardDetail(); else root.loadBoard() })
  }

  function toggleGolden() {
    if (!cardDetail) return
    var wasGolden = cardDetail.golden === true
    var next = JSON.parse(JSON.stringify(cardDetail))
    next.golden = !wasGolden
    mutationGen++
    cardDetail = next
    api(wasGolden ? "DELETE" : "POST", "/{slug}/cards/" + cardDetail.number + "/goldness", null, false,
      function(ok) { if (!ok) root.reloadCardDetail(); else root.loadBoard() })
  }

  function addComment(text, done) {
    var trimmed = String(text || "").trim()
    if (trimmed === "" || !cardDetail) {
      if (done) done(false)
      return
    }
    var number = cardDetail.number
    api("POST", "/{slug}/cards/" + number + "/comments", { comment: { body: trimmed } }, false,
      function(ok, out) {
        if (done) done(ok)
        if (!ok) return
        var comment = Model.parseJson(out, null)
        if (comment && root.cardDetail && root.cardDetail.number === number) {
          var next = root.cardComments.slice()
          next.push(comment)
          root.cardComments = next
        }
      })
  }

  // ---------------------------------------------------------------- compose

  function openCompose(prefillTitle) {
    loadDirectory()
    pushPage("compose")
    composePageItem.reset(prefillTitle || "")
  }

  function createQuickCard(title, done) {
    var trimmed = String(title || "").trim()
    if (trimmed === "" || boardId === "") {
      if (done) done(false)
      return
    }
    api("POST", "/{slug}/boards/" + boardId + "/cards", { card: { title: trimmed } }, false,
      function(ok) {
        if (done) done(ok)
        if (ok) root.loadBoard()
      })
  }

  function createFullCard(input) {
    if (composeBusy || boardId === "") return
    composeBusy = true
    var payload = { card: { title: input.title } }
    if (input.description !== "") payload.card.description = input.description
    api("POST", "/{slug}/boards/" + boardId + "/cards", payload, false, function(ok, out) {
      if (!ok) { root.composeBusy = false; return }
      var created = Model.parseJson(out, null)
      var number = created ? created.number : null
      var followUps = 0
      var finish = function() {
        if (followUps > 0) return
        root.composeBusy = false
        // Only pop if the composer is still on top — the user may have
        // Esc'd out and navigated elsewhere while the create was in flight.
        if (root.page === "compose") root.popPage()
        root.loadBoard()
      }
      var track = function(ok2) { followUps--; finish() }
      if (number !== null && number !== undefined) {
        if (input.columnId !== "") {
          followUps++
          root.api("POST", "/{slug}/cards/" + number + "/triage", { column_id: String(input.columnId) }, false, track)
        }
        for (var i = 0; i < input.tagTitles.length; i++) {
          followUps++
          root.api("POST", "/{slug}/cards/" + number + "/taggings", { tag_title: input.tagTitles[i] }, false, track)
        }
        for (var j = 0; j < input.assigneeIds.length; j++) {
          followUps++
          root.api("POST", "/{slug}/cards/" + number + "/assignments", { assignee_id: String(input.assigneeIds[j]) }, false, track)
        }
      }
      finish()
    })
  }

  // ---------------------------------------------------------------- auth

  function connectWithToken(token) {
    var trimmed = String(token || "").trim()
    if (trimmed === "") { notice = "Paste a token first"; return }
    tokenRejected = false
    notice = "Connecting…"
    afterSave = function() { root.resolveIdentity() }
    saveConfig({ token: trimmed, base_url: config.base_url || "https://app.fizzy.do", account_slug: null })
  }

  // Background poll keeps the bar badge honest while the panel is closed.
  readonly property int refreshIntervalSec: Math.max(60, parseInt(setting("refreshIntervalSec", 300), 10) || 300)

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.authed && root.boardId !== "" && !root.tokenRejected
    repeat: true
    onTriggered: root.loadBoard()
  }

  // FileView can't watch a file that doesn't exist yet: poll slowly until a
  // token shows up so a config created by an external tool is still noticed.
  Timer {
    interval: 5000
    running: !root.hasToken
    repeat: true
    onTriggered: root.configFile.reload()
  }

  // ---------------------------------------------------------------- ui

  // One fixed footprint on every page — the house bar-panel width, and tall
  // enough that a typical card reads without scrolling. fittedContentHeight
  // still clamps to the screen on short displays.
  readonly property real panelWidth: Style.space(380)
  readonly property real panelHeight: Style.space(560)

  readonly property string heroTitle:
    page === "auth" ? "Fizzy"
    : page === "boards" ? "Fizzy"
    : page === "board" ? (boardName || "Board")
    : page === "card" ? (cardDetail ? "#" + cardDetail.number : "Card")
    : "New card"

  readonly property string heroMeta:
    page === "auth" ? "Connect your account"
    : offline ? "Offline — press r to retry"
    : page === "boards" ? (boards.length > 0 ? boards.length + " boards" : "Your boards")
    : page === "board" ? (grouped.maybe.length + " maybe · " + inPlayCount + " in play")
    : page === "card" ? ((boardName || "") + (cardDetail ? " · " + Model.relativeTime(cardDetail.last_active_at, nowTick) : ""))
    : (boardName || "")

  readonly property string heroDetail: {
    if (page !== "card" || !cardDetail) return ""
    var place = Model.cardPlace(cardDetail, cardOriginKey)
    if (place === "maybe") return "Maybe?"
    if (place === "not_now") return "Not Now"
    if (place === "closed") return "Done"
    return cardDetail.column ? cardDetail.column.name : ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(root.panelHeight, root.panelHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // Shell contract: stand down while any inline editor owns the keys.
      blocked: authPageItem.editorFocused || boardPageItem.editorFocused
        || cardPageItem.editorFocused || composePageItem.editorFocused

      onCloseRequested: {
        root.clearPendingVimKey()
        if (root.helpVisible) root.helpVisible = false
        else if (root.page === "card" || root.page === "compose") root.popPage()
        else if (root.page === "boards" && root.boardId !== "") root.page = "board"
        else root.close()
      }
      onDeleteRequested: {
        root.clearPendingVimKey()
        if (root.helpVisible) { root.helpVisible = false; return }
        if (root.page === "board" && root.cardCursor >= 0 && root.cardCursor < root.visibleCards.length)
          root.closeCardAt(root.cardCursor)
      }
      onMoveRequested: function(dx, dy) {
        root.clearPendingVimKey()
        if (root.helpVisible) return
        if (root.page === "board") {
          if (dx !== 0) root.cycleFilter(dx)
          if (dy !== 0 && root.visibleCards.length > 0) {
            boardPageItem.resetGate()
            root.cardCursor = Math.max(0, Math.min(root.visibleCards.length - 1, root.cardCursor + dy))
          }
        } else if (root.page === "boards" && dy !== 0 && root.boards.length > 0) {
          boardsPageItem.resetGate()
          root.boardCursor = Math.max(0, Math.min(root.boards.length - 1, root.boardCursor + dy))
        } else if (root.page === "card" && dy !== 0) {
          cardPageItem.scrollBy(dy)
        }
      }
      onTextKey: function(t) {
        var pending = root.pendingVimKey
        root.pendingVimKey = ""
        pendingKeyTimer.stop()

        if (t === "?") { root.helpVisible = !root.helpVisible; return }
        if (root.helpVisible) { root.helpVisible = false; return }

        if (t === "g") {
          if (pending === "g") { root.jumpToEdge(-1); return }
          root.pendingVimKey = "g"
          pendingKeyTimer.restart()
          return
        }
        if (t === "G") { root.jumpToEdge(1); return }
        if (t === "r" || t === "R") { root.refresh(true); return }
        if ((t === "n" || t === "N" || t === "c" || t === "C") && root.page === "board") { root.openCompose(""); return }
        if (t === "o" || t === "O") {
          if (root.page === "board" && root.cardCursor >= 0 && root.cardCursor < root.visibleCards.length)
            root.openCard(root.visibleCards[root.cardCursor])
          return
        }
        if (t === "a" || t === "A") {
          if (root.page === "board") boardPageItem.focusComposer()
          else if (root.page === "card") cardPageItem.focusComment()
          return
        }
        if ((t === "s" || t === "S") && root.page === "card" && root.cardDetail) { root.toggleGolden(); return }
        if (root.page === "board" && t >= "1" && t <= "9") {
          var index = parseInt(t, 10) - 1
          if (index < root.filters.length) root.selectFilter(root.filters[index].key)
          return
        }
      }
      onActivateRequested: {
        root.clearPendingVimKey()
        if (root.helpVisible) { root.helpVisible = false; return }
        if (root.page === "board" && root.cardCursor >= 0 && root.cardCursor < root.visibleCards.length)
          root.openCard(root.visibleCards[root.cardCursor])
        else if (root.page === "boards" && root.boardCursor >= 0 && root.boardCursor < root.boards.length)
          root.selectBoard(root.boards[root.boardCursor].id)
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        anchors.fill: parent
        spacing: Style.space(14)

        // ------------------------------------------------ hero
        Item {
          id: heroItem
          width: parent.width
          implicitHeight: hero.implicitHeight
          readonly property bool showBack: root.currentLevel > 1

          // Inside the Component blocks below, PanelHero's internal
          // `id: root` shadows the panel's — the dropbox panel documents
          // this trap. All panel state goes through this handle instead.
          readonly property var fizzy: root

          PanelHero {
            id: hero
            width: parent.width
            title: root.heroTitle
            meta: root.heroMeta
            detail: root.heroDetail
            foreground: root.ink
            fontFamily: root.fontFamily

            iconComponent: heroItem.showBack ? backIcon : bubbleIcon

            // Card actions live with the content they describe (title star,
            // footer link) — the hero stays: back · number · meta · place.
            trailingControl:
              root.page === "board" ? boardActions
              : root.page === "boards" ? refreshAction
              : null
          }

          Component {
            id: bubbleIcon
            FizzyIcon {
              iconSize: Style.font.display
              tint: heroItem.fizzy.accent
              animate: heroItem.fizzy.opened
            }
          }

          Component {
            id: backIcon
            PanelActionButton {
              iconText: "󰅁"
              tooltipText: "Back"
              fontSize: Style.font.title
              foreground: heroItem.fizzy.ink
              onClicked: {
                if (heroItem.fizzy.page === "boards") heroItem.fizzy.page = "board"
                else heroItem.fizzy.popPage()
              }
            }
          }

          Component {
            id: refreshAction
            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh"
              foreground: heroItem.fizzy.dim
              onClicked: heroItem.fizzy.refresh(true)
            }
          }

          Component {
            id: boardActions
            Row {
              spacing: Style.space(2)

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: heroItem.fizzy.dim
                onClicked: heroItem.fizzy.refresh(true)
              }

              PanelActionButton {
                iconText: "󰐕"
                tooltipText: "New card — notes, column, tags, people"
                foreground: heroItem.fizzy.ink
                onClicked: heroItem.fizzy.openCompose("")
              }

              PanelActionButton {
                iconText: "󰕰"
                tooltipText: "All boards"
                foreground: heroItem.fizzy.dim
                onClicked: { heroItem.fizzy.page = "boards"; heroItem.fizzy.loadBoards() }
              }

              PanelActionButton {
                iconText: "?"
                fontSize: Style.font.bodySmall
                tooltipText: "Keyboard shortcuts — press ? (Shift + /)"
                foreground: heroItem.fizzy.dim
                onClicked: heroItem.fizzy.helpVisible = true
              }
            }
          }

        }

        // ------------------------------------------------ pages
        Item {
          id: pages
          width: parent.width
          height: parent.height - heroItem.height - Style.space(14)
          clip: true

          component PageSlot: Item {
            id: slot
            property string name: ""
            default property alias content: inner.data
            readonly property bool active: root.page === name
            readonly property int level: root.pageLevel(name)

            width: pages.width
            height: pages.height
            // iOS-style parallax: the page beneath retreats a third of the
            // distance while the incoming page travels the full width.
            x: active ? 0 : (level < root.currentLevel ? -pages.width * 0.35 : pages.width)
            opacity: active ? 1 : 0
            // Visible the instant a page activates (not once its fade-in
            // clears the threshold) so forceActiveFocus on its fields works.
            visible: active || opacity > 0.01

            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            Item { id: inner; anchors.fill: parent }
          }

          PageSlot { name: "auth";   AuthPage   { id: authPageItem; anchors.fill: parent; panel: root } }
          PageSlot { name: "boards"; BoardsPage { id: boardsPageItem; anchors.fill: parent; panel: root } }
          PageSlot { name: "board";  BoardPage  { id: boardPageItem; anchors.fill: parent; panel: root } }
          PageSlot { name: "card";   CardPage   { id: cardPageItem; anchors.fill: parent; panel: root } }
          PageSlot {
            name: "compose"
            ComposePage { id: composePageItem; anchors.fill: parent; panel: root }
          }
        }
      }

      // ------------------------------------------------ activity sweep
      // A hairline in the hero/pages gap that glides while requests are in
      // flight. XAnimator runs on the render thread and stops when hidden.
      Item {
        id: busyLine
        y: heroItem.height + Style.space(6)
        width: parent.width
        height: Math.max(2, Style.space(2))
        clip: true
        opacity: root.busyVisible && root.opened ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          color: root.hairline
        }

        Rectangle {
          id: sweepChip
          width: Math.round(busyLine.width * 0.3)
          height: parent.height
          opacity: 0.85
          // Soft-edged sweep: the chip fades in and out of its own tail.
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Style.selectedStateColor(root.ink, root.accent) }
            GradientStop { position: 1.0; color: "transparent" }
          }

          XAnimator on x {
            running: busyLine.visible
            loops: Animation.Infinite
            from: -sweepChip.width
            to: busyLine.width
            duration: 1100
            easing.type: Easing.InOutQuad
          }
        }
      }

      // ------------------------------------------------ help overlay
      Rectangle {
        id: helpOverlay
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        z: 20
        radius: Style.cornerRadius
        color: Util.alpha(Color.popups.background, 0.97)
        opacity: root.helpVisible ? 1 : 0
        visible: opacity > 0.01
        scale: root.helpVisible ? 1 : 0.98
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        MouseArea {
          anchors.fill: parent
          onClicked: root.helpVisible = false
        }

        component HelpRow: Row {
          property string keys: ""
          property string does: ""
          spacing: Style.space(12)

          Text {
            text: parent.keys
            width: Style.space(72)
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
          }

          Text {
            text: parent.does
            color: root.ink
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Column {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(4)
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "KEYBOARD"
            foreground: root.ink
            fontFamily: root.fontFamily
          }

          HelpRow { keys: "j / k  ↑ ↓"; does: "Move · scroll" }
          HelpRow { keys: "h / l  ← →"; does: "Switch filter" }
          HelpRow { keys: "gg / G"; does: "First · last" }
          HelpRow { keys: "Enter / o"; does: "Open card" }
          HelpRow { keys: "a"; does: "Quick add · comment" }
          HelpRow { keys: "n / c"; does: "New card (composer)" }
          HelpRow { keys: "x"; does: "Mark card done" }
          HelpRow { keys: "s"; does: "Toggle golden" }
          HelpRow { keys: "1 – 9"; does: "Jump to filter" }
          HelpRow { keys: "r"; does: "Refresh" }
          HelpRow { keys: "Tab"; does: "Next bar panel" }
          HelpRow { keys: "Esc"; does: "Back · close" }
          HelpRow { keys: "?"; does: "This help" }
        }
      }
    }
  }
}
