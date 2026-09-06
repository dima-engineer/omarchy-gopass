import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "GopassSearch.js" as Search

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool focusPrimed: false
  property string filterText: ""
  property string activeTab: "secrets"
  property string currentDir: ""
  property int selectedIndex: 0
  property bool cursorActive: false

  property var allSecretPaths: []
  property var allTotpPaths: []
  property var totpAccountMap: ({})
  property var filteredPaths: []

  property string errorMessage: ""

  property bool creating: false
  property string createKind: ""
  property string createStep: ""
  property string createPath: ""
  property string createValue: ""
  property string createError: ""
  property bool createBusy: false
  property int generateLength: 20
  property bool generateSymbols: false
  property string pasteTarget: ""

  readonly property int minGenerateLength: 4
  readonly property int maxGenerateLength: 64

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int rowHeight: Math.max(Style.space(30), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(680), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    root.focusPrimed = false
    focusPrimeTimer.restart()
    root.filterText = ""
    root.activeTab = "secrets"
    root.currentDir = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.errorMessage = ""
    root.cancelCreate()
    root.generateLength = 20
    root.generateSymbols = false
    root.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.forget()
  }

  function dismiss() {
    root.opened = false
    root.forget()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.dima-engineer.gopass")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function forget() {
    focusPrimeTimer.stop()
    root.focusPrimed = false
    root.cancelCreate()
    root.totpCodes = ({})
    root.totpErrors = ({})
    root._lastWindowByPath = ({})
    root._otpQueue = []
    root._otpBusy = false
  }

  function reload() {
    root.errorMessage = ""
    listProcess.running = true
  }

  Process {
    id: listProcess
    command: ["gopass", "ls", "--flat"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: listProcess.captured = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: listProcess.capturedErr = text }
    property string captured: ""
    property string capturedErr: ""

    onExited: function(code) {
      if (code === 0) {
        var split = Search.splitEntries(Search.parseList(captured))
        var totpInfo = Search.totpAccounts(split.totps)
        root.allSecretPaths = split.secrets
        root.allTotpPaths = totpInfo.accounts
        root.totpAccountMap = totpInfo.pathFor
        root.rebuildDisplay()
      } else {
        root.allSecretPaths = []
        root.allTotpPaths = []
        root.totpAccountMap = ({})
        root.errorMessage = capturedErr.trim() || "Could not list the gopass store. Is it initialized (gopass init)?"
        root.rebuildDisplay()
      }
      captured = ""
      capturedErr = ""
    }
  }

  function currentSourceList() {
    return root.activeTab === "totp" ? root.allTotpPaths : root.allSecretPaths
  }

  function rebuildDisplay() {
    displayModel.clear()

    if (root.filterText) {
      var out = Search.filterEntries(root.currentSourceList(), root.filterText, 500)
      root.filteredPaths = out
      for (var i = 0; i < out.length; i++)
        displayModel.append({ path: out[i], label: out[i], isDir: false, isUp: false })
    } else {
      var children = Search.childrenOf(root.currentSourceList(), root.currentDir)
      root.filteredPaths = children.entries
      if (root.currentDir)
        displayModel.append({ path: Search.parentDir(root.currentDir), label: "..", isDir: true, isUp: true })
      for (var d = 0; d < children.dirs.length; d++)
        displayModel.append({ path: root.currentDir + children.dirs[d] + "/", label: children.dirs[d] + "/", isDir: true, isUp: false })
      for (var e = 0; e < children.entries.length; e++)
        displayModel.append({ path: children.entries[e], label: Search.basename(children.entries[e]), isDir: false, isUp: false })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0
    cursorActive = displayModel.count > 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })

    root.primeTotpCodes()
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function switchTab() {
    root.activeTab = root.activeTab === "secrets" ? "totp" : "secrets"
    root.currentDir = ""
    root.selectedIndex = 0
    root.rebuildDisplay()
  }

  function select(delta) {
    if (displayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectPage(delta) {
    if (displayModel.count === 0) return
    var visibleRows = Math.max(1, Math.floor(resultList.height / root.rowHeight))
    var newIndex = selectedIndex + delta * visibleRows
    if (newIndex < 0) newIndex = 0
    if (newIndex >= displayModel.count) newIndex = displayModel.count - 1
    selectedIndex = newIndex
    cursorActive = true
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectedEntry() {
    if (!cursorActive || selectedIndex < 0 || selectedIndex >= displayModel.count) return null
    return displayModel.get(selectedIndex)
  }

  function enterDir(dirPath) {
    root.currentDir = dirPath
    root.selectedIndex = 0
    root.cursorActive = true
    root.rebuildDisplay()
  }

  function goUpDir() {
    if (!root.currentDir) return
    root.enterDir(Search.parentDir(root.currentDir))
  }

  function activateSelected() {
    var entry = root.selectedEntry()
    if (!entry) return
    if (entry.isDir) { root.enterDir(entry.path); return }
    if (root.activeTab === "totp") root.copySecret(entry.path, "otp")
    else root.copySecret(entry.path, "show")
  }

  function typeSelected() {
    var entry = root.selectedEntry()
    if (!entry || entry.isDir) return
    if (root.activeTab === "totp") root.typeSecret(entry.path, "otp")
    else root.typeSecret(entry.path, "show")
  }

  function allKnownPaths() {
    return root.allSecretPaths.concat(root.allTotpPaths)
  }

  function beginCreate() {
    root.creating = true
    root.createKind = root.activeTab === "totp" ? "totp" : "secret"
    root.createStep = "path"
    root.createPath = root.filterText || root.currentDir
    root.createValue = ""
    root.createError = ""
    root.cursorActive = false
  }

  function cancelCreate() {
    root.creating = false
    root.createKind = ""
    root.createStep = ""
    root.createPath = ""
    root.createValue = ""
    root.createError = ""
    root.cursorActive = displayModel.count > 0
  }

  function finishCreate(message) {
    root.creating = false
    root.createKind = ""
    root.createStep = ""
    root.createPath = ""
    root.createValue = ""
    root.createError = ""
    root.createBusy = false
    root.notify(message)
    root.setFilter("")
    root.reload()
  }

  function submitCreatePath() {
    var clean = Search.normalizePath(root.createPath)
    if (!clean) { root.createError = "Path required."; return }
    var fullPath = root.createKind === "totp" ? Search.ensureTotpSuffix(clean) : clean
    if (root.allKnownPaths().indexOf(fullPath) >= 0) {
      root.createError = "An entry already exists at \"" + fullPath + "\"."
      return
    }
    root.createPath = fullPath
    root.createStep = "value"
    root.createError = ""
  }

  function submitCreateValue() {
    if (root.createBusy) return
    if (root.createKind === "totp") {
      if (!root.createValue) { root.createError = "Paste the secret key shown under the QR code."; return }
      var accountPath = Search.normalizePath(root.createPath.replace(/\/totp$/i, ""))
      var uri = Search.buildOtpauthUri(accountPath, root.createValue)
      root.insertSecret(root.createPath, uri)
    } else {
      if (!root.createValue) { root.createError = "Type a password, or press Ctrl+G to generate one."; return }
      root.insertSecret(root.createPath, root.createValue)
    }
  }

  function generateCreateValue() {
    if (root.createBusy || root.createKind !== "secret" || root.createStep !== "value") return
    root.createBusy = true
    root.createError = ""
    generateProcess.path = root.createPath
    var cmd = ["gopass", "generate", "-p"]
    if (root.generateSymbols) cmd.push("-s")
    cmd.push(root.createPath, String(root.generateLength))
    generateProcess.command = cmd
    generateProcess.running = true
  }

  function adjustGenerateLength(delta) {
    root.generateLength = Math.max(root.minGenerateLength, Math.min(root.maxGenerateLength, root.generateLength + delta))
  }

  function toggleGenerateSymbols() {
    root.generateSymbols = !root.generateSymbols
  }

  function isPasteShortcut(event) {
    if (event.key === Qt.Key_V && event.modifiers === Qt.ControlModifier) return true
    // Hyprland's SUPER+V "universal paste" bind re-dispatches Ctrl+V to the
    // focused surface, except when it thinks that surface is a terminal (its
    // own active_window_is_terminal() check, which falls back to whatever
    // real window was last active since a layer-shell overlay isn't one) —
    // then it sends Shift+Insert instead. Confirmed via this overlay's own
    // debug log: SUPER+V arrives here as Shift+Insert, not Ctrl+V.
    if (event.key === Qt.Key_Insert && event.modifiers === Qt.ShiftModifier) return true
    return false
  }

  function pasteInto(target) {
    if (root.pasteTarget) return
    root.pasteTarget = target
    pasteProcess.running = true
  }

  Process {
    id: pasteProcess
    command: ["wl-paste", "-n"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: pasteProcess.captured = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: pasteProcess.capturedErr = text }
    property string captured: ""
    property string capturedErr: ""
    onExited: function(code) {
      var target = root.pasteTarget
      root.pasteTarget = ""
      if (code === 0) {
        var line = Search.firstLine(captured)
        if (target === "path") { root.createPath += line; root.createError = "" }
        else if (target === "value") { root.createValue += line; root.createError = "" }
        else if (target === "filter") root.setFilter(root.filterText + line)
      } else {
        var message = capturedErr.trim() || "Could not read the clipboard."
        if (target === "path" || target === "value") root.createError = message
        else root.notify(message)
      }
      captured = ""
      capturedErr = ""
    }
  }

  function insertSecret(path, value) {
    root.createBusy = true
    root.createError = ""
    insertProcess.path = path
    insertProcess.pending = value + "\n"
    insertProcess.command = ["gopass", "insert", path]
    insertProcess.stdinEnabled = true
    insertProcess.running = true
  }

  Process {
    id: insertProcess
    property string pending: ""
    property string path: ""
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: insertProcess.capturedErr = text }
    property string capturedErr: ""
    onStarted: {
      write(pending)
      pending = ""
      stdinEnabled = false
    }
    onExited: function(code) {
      if (code === 0) root.finishCreate("Created " + insertProcess.path)
      else { root.createBusy = false; root.createError = capturedErr.trim() || "Could not create the secret." }
      capturedErr = ""
    }
  }

  Process {
    id: generateProcess
    property string path: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: generateProcess.capturedErr = text }
    property string capturedErr: ""
    onExited: function(code) {
      if (code === 0) root.finishCreate("Generated password for " + generateProcess.path)
      else { root.createBusy = false; root.createError = capturedErr.trim() || "Could not generate a password." }
      capturedErr = ""
    }
  }

  property var totpCodes: ({})
  property var totpErrors: ({})
  property int codesVersion: 0
  property var _lastWindowByPath: ({})
  property var _otpQueue: []
  property bool _otpBusy: false

  readonly property int totpPeriod: 30
  property real _nowMs: Date.now()
  readonly property int currentWindow: Math.floor(_nowMs / 1000 / totpPeriod)
  readonly property int secondsLeft: totpPeriod - (Math.floor(_nowMs / 1000) % totpPeriod)

  onCurrentWindowChanged: root.primeTotpCodes()

  Timer {
    interval: 250
    running: root.opened
    repeat: true
    onTriggered: root._nowMs = Date.now()
  }

  function codeFor(path) {
    root.codesVersion
    return root.totpCodes.hasOwnProperty(path) ? root.totpCodes[path] : ""
  }

  function codeErrorFor(path) {
    root.codesVersion
    return root.totpErrors.hasOwnProperty(path) ? root.totpErrors[path] : false
  }

  function primeTotpCodes() {
    if (!root.opened || root.activeTab !== "totp") return
    var queue = root._otpQueue.slice(0)
    var changed = false
    for (var i = 0; i < root.filteredPaths.length; i++) {
      var p = root.filteredPaths[i]
      if (root._lastWindowByPath[p] === root.currentWindow) continue
      if (queue.indexOf(p) >= 0) continue
      queue.push(p)
      changed = true
    }
    if (changed) root._otpQueue = queue
    root._drainOtpQueue()
  }

  function _drainOtpQueue() {
    if (root._otpBusy || root._otpQueue.length === 0) return
    var next = root._otpQueue[0]
    root._otpQueue = root._otpQueue.slice(1)
    root._otpBusy = true
    otpFetch.path = next
    otpFetch.window = root.currentWindow
    otpFetch.command = ["gopass", "otp", root.totpAccountMap[next] || next, "-o"]
    otpFetch.running = true
  }

  Process {
    id: otpFetch
    property string path: ""
    property int window: 0
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: otpFetch.captured = text }
    stderr: StdioCollector { waitForEnd: true }
    property string captured: ""

    onExited: function(code) {
      root._lastWindowByPath[path] = window
      var codes = {}
      for (var k in root.totpCodes) codes[k] = root.totpCodes[k]
      var errs = {}
      for (var k2 in root.totpErrors) errs[k2] = root.totpErrors[k2]
      if (code === 0) {
        codes[path] = captured.replace(/\n+$/, "")
        errs[path] = false
      } else {
        errs[path] = true
      }
      root.totpCodes = codes
      root.totpErrors = errs
      root.codesVersion++
      captured = ""
      root._otpBusy = false
      root._drainOtpQueue()
    }
  }

  function notify(body) {
    Quickshell.execDetached(["notify-send", "-a", "Gopass", "-i", "gopass", "Gopass", body])
  }

  function copySecret(path, kind) {
    fetchThen(path, kind, function(value) {
      clipProcess.pending = value
      clipProcess.command = ["wl-copy", "--sensitive"]
      clipProcess.stdinEnabled = true
      clipProcess.running = true
      root._pendingClipboardValue = value
      clearCheckTimer.restart()
    })
    root.dismiss()
  }

  function typeSecret(path, kind) {
    fetchThen(path, kind, function(value) {
      typeProcess.pending = value
      typeDelay.restart()
    })
    root.dismiss()
  }

  function fetchThen(path, kind, onValue) {
    fetchProcess.command = kind === "otp"
      ? ["gopass", "otp", root.totpAccountMap[path] || path, "-o"]
      : ["gopass", "show", "--unsafe", "--noparsing", path]
    fetchProcess.kind = kind
    fetchProcess.onValue = onValue
    fetchProcess.label = path
    fetchProcess.running = true
  }

  Process {
    id: fetchProcess
    property var onValue: null
    property string label: ""
    property string kind: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: fetchProcess.captured = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: fetchProcess.capturedErr = text }
    property string captured: ""
    property string capturedErr: ""

    onExited: function(code) {
      if (code === 0) {
        var value = kind === "otp"
          ? captured.replace(/\n+$/, "")
          : captured.replace(/\r/g, "").split("\n")[0]
        if (typeof onValue === "function") onValue(value)
      } else {
        root.notify("Could not read " + label + (capturedErr.trim() ? ": " + capturedErr.trim() : ""))
      }
      captured = ""
      capturedErr = ""
      onValue = null
    }
  }

  Process {
    id: clipProcess
    property string pending: ""
    stdinEnabled: true
    onStarted: {
      write(pending)
      pending = ""
      stdinEnabled = false
    }
    onExited: function(code) {
      if (code === 0) root.notify("Copied to clipboard (clears in 45s)")
    }
  }

  property string _pendingClipboardValue: ""

  Timer {
    id: clearCheckTimer
    interval: 45000
    onTriggered: {
      if (root._pendingClipboardValue === "") return
      clearCheck.expected = root._pendingClipboardValue
      root._pendingClipboardValue = ""
      clearCheck.command = ["wl-paste", "-n"]
      clearCheck.running = true
    }
  }

  Process {
    id: clearCheck
    property string expected: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: clearCheck.captured = text }
    stderr: StdioCollector { waitForEnd: true }
    property string captured: ""

    onExited: function(code) {
      if (code === 0 && captured === expected) {
        clearProcess.command = ["wl-copy", "--clear"]
        clearProcess.running = true
      }
      captured = ""
      expected = ""
    }
  }

  Process { id: clearProcess }

  Timer {
    id: typeDelay
    interval: 220
    onTriggered: {
      typeProcess.stdinEnabled = true
      typeProcess.running = true
    }
  }

  Process {
    id: typeProcess
    property string pending: ""
    command: ["wtype", "-"]
    stdinEnabled: true
    onStarted: {
      write(pending)
      pending = ""
      stdinEnabled = false
    }
  }

  ListModel { id: displayModel }

  // Brief Exclusive prime (guarantees focus the instant the surface maps,
  // same as KeyboardPanel.qml) then settle on OnDemand — Exclusive blocks
  // Hyprland from processing its own keybinds at all (e.g. the SUPER+V
  // "universal paste" dispatch) for as long as it holds focus, so staying
  // Exclusive permanently would leave Super-based shortcuts dead the whole
  // time the overlay is open.
  Timer {
    id: focusPrimeTimer
    interval: 75
    onTriggered: if (root.opened) root.focusPrimed = true
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-gopass"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }

    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.creating) {
            if (event.key === Qt.Key_Escape) {
              if (root.createStep === "value") { root.createStep = "path"; root.createValue = ""; root.createError = "" }
              else root.cancelCreate()
              event.accepted = true
            } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_G) {
              root.generateCreateValue()
              event.accepted = true
            } else if (root.isPasteShortcut(event)) {
              root.pasteInto(root.createStep === "path" ? "path" : "value")
              event.accepted = true
            } else if (root.createKind === "secret" && root.createStep === "value"
                       && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
              root.adjustGenerateLength(event.key === Qt.Key_Up ? 1 : -1)
              event.accepted = true
            } else if (root.createKind === "secret" && root.createStep === "value" && event.key === Qt.Key_Tab) {
              root.toggleGenerateSymbols()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (root.createStep === "path") root.submitCreatePath()
              else root.submitCreateValue()
              event.accepted = true
            } else if (root.createStep === "path" && Util.editsFilter(event, root.createPath)) {
              root.createPath = Util.editedFilter(event, root.createPath)
              root.createError = ""
              event.accepted = true
            } else if (root.createStep === "value" && Util.editsFilter(event, root.createValue)) {
              root.createValue = Util.editedFilter(event, root.createValue)
              root.createError = ""
              event.accepted = true
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              if (root.createStep === "path") root.createPath += event.text
              else root.createValue += event.text
              root.createError = ""
              event.accepted = true
            } else {
              event.accepted = true
            }
            return
          }
          if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_N) {
            root.beginCreate()
            event.accepted = true
          } else if (root.isPasteShortcut(event)) {
            root.pasteInto("filter")
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else if (root.currentDir) root.goUpDir()
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Tab) {
            root.switchTab()
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText && root.currentDir) {
            root.goUpDir()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up || (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_K)) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_J)) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.selectPage(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.selectPage(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Right && !root.filterText && root.cursorActive) {
            var hovered = root.selectedEntry()
            if (hovered && hovered.isDir) root.enterDir(hovered.path)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (event.modifiers === Qt.ShiftModifier) root.typeSelected()
            else if (root.cursorActive) root.activateSelected()
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Row {
            id: tabsRow
            spacing: Style.space(4)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              width: secretsLabel.implicitWidth + Style.space(16)
              height: root.headerHeight - Style.space(6)
              radius: root.cornerRadius
              color: root.activeTab === "secrets" ? root.selectedBackground : "transparent"
              Text {
                id: secretsLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Secrets (" + root.allSecretPaths.length + ")"
                color: root.activeTab === "secrets" ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              MouseArea {
                anchors.fill: parent
                onClicked: { if (root.activeTab !== "secrets") root.switchTab() }
              }
            }

            Rectangle {
              width: totpLabel.implicitWidth + Style.space(16)
              height: root.headerHeight - Style.space(6)
              radius: root.cornerRadius
              color: root.activeTab === "totp" ? root.selectedBackground : "transparent"
              Text {
                id: totpLabel
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "TOTP (" + root.allTotpPaths.length + ")"
                color: root.activeTab === "totp" ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              MouseArea {
                anchors.fill: parent
                onClicked: { if (root.activeTab !== "totp") root.switchTab() }
              }
            }
          }

          Text {
            anchors.left: tabsRow.right
            anchors.leftMargin: Style.space(16)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.creating
              ? (root.createKind === "totp" ? "New TOTP entry" : "New secret")
              : (root.filterText || (root.currentDir
                  ? "/ " + root.currentDir.replace(/\/$/, "").split("/").join(" / ")
                  : (root.activeTab === "totp" ? "Search TOTP accounts…" : "Search secrets…")))
            color: root.foreground
            opacity: root.creating || root.filterText ? 1 : (root.currentDir ? 0.85 : 0.58)
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideLeft
            horizontalAlignment: Text.AlignRight
          }
        }

        Text {
          visible: !root.creating && root.errorMessage.length > 0
          width: parent.width
          textFormat: Text.PlainText
          text: root.errorMessage
          color: root.foreground
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.creating && root.createError.length > 0
          width: parent.width
          textFormat: Text.PlainText
          text: root.createError
          color: "#e06c75"
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - footerRow.height - root.contentSpacing * 2
            - (!root.creating && root.errorMessage.length > 0 ? Style.space(24) : 0)
            - (root.creating && root.createError.length > 0 ? Style.space(24) : 0)

          Column {
            visible: root.creating
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.spacing.md

            Text {
              textFormat: Text.PlainText
              text: root.createStep === "path" ? "Path" : "Path: " + root.createPath
              color: root.foreground
              opacity: root.createStep === "path" ? 1 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              visible: root.createStep === "path"
              width: parent.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: root.selectedBackground
              Text {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: root.createPath.length > 0 ? root.createPath : "e.g. work/github/alice"
                color: root.selectedText
                opacity: root.createPath.length > 0 ? 1 : 0.6
                elide: Text.ElideLeft
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Text {
              visible: root.createStep === "value"
              textFormat: Text.PlainText
              text: root.createKind === "totp" ? "Secret key (base32)" : "Password"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              visible: root.createStep === "value"
              width: parent.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: root.selectedBackground
              Text {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: root.createBusy
                  ? "Working…"
                  : (root.createValue.length > 0
                      ? (root.createKind === "totp" ? root.createValue : "•".repeat(root.createValue.length))
                      : (root.createKind === "totp" ? "Paste the secret key" : "Type a password, or Ctrl+G to generate"))
                color: root.selectedText
                opacity: root.createValue.length > 0 || root.createBusy ? 1 : 0.6
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Text {
              visible: root.createKind === "secret" && root.createStep === "value"
              textFormat: Text.PlainText
              text: "Generate: " + root.generateLength + " chars, symbols "
                + (root.generateSymbols ? "on" : "off") + "  (↑/↓ length · Tab symbols · Ctrl+G generate)"
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          ListView {
            id: resultList
            visible: !root.creating
            anchors.fill: parent
            model: displayModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: delegateRoot
              required property int index
              required property string path
              required property string label
              required property bool isDir
              required property bool isUp

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property bool isTotpRow: root.activeTab === "totp" && !delegateRoot.isDir

              width: resultList.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: codeText.visible ? codeText.left : parent.right
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: delegateRoot.isUp ? "󰅁 .." : (delegateRoot.isDir ? "󰉋 " + delegateRoot.label : delegateRoot.label)
                color: hasCursor ? root.selectedText : root.foreground
                elide: Text.ElideMiddle
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: codeText
                visible: delegateRoot.isTotpRow
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: {
                  if (root.codeErrorFor(delegateRoot.path)) return "⚠"
                  var c = root.codeFor(delegateRoot.path)
                  return (c.length > 0 ? c : "······") + "  " + root.secondsLeft + "s"
                }
                color: root.secondsLeft <= 5 && !root.codeErrorFor(delegateRoot.path)
                  ? "#e06c75" : (hasCursor ? root.selectedText : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.selectedIndex = index
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = index
                  root.activateSelected()
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: !root.creating && displayModel.count === 0 && root.errorMessage.length === 0

            Text {
              textFormat: Text.PlainText
              text: root.filterText.length > 0
                ? "No matches for “" + root.filterText + "”"
                : (root.currentDir.length > 0
                    ? "Empty folder"
                    : (root.activeTab === "totp" ? "No entries named “totp” yet" : "No secrets found"))
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: root.cardWidth - root.contentMargin * 2
              wrapMode: Text.WordWrap
            }
          }
        }

        Row {
          id: footerRow
          width: parent.width
          height: Style.space(20)
          spacing: Style.space(16)

          Text {
            textFormat: Text.PlainText
            text: root.creating
              ? (root.createStep === "path"
                  ? "Enter next · Ctrl+V paste · Esc cancel"
                  : (root.createKind === "secret"
                      ? "Enter save · Ctrl+G generate · Ctrl+V paste · Esc back"
                      : "Enter save · Ctrl+V paste · Esc back"))
              : "Enter open/copy · ←/Backspace up · Shift+Enter type · Tab switch · Ctrl+N new · Esc close"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
