import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Fuzzy.js" as Fuzzy
import "PaletteViewModel.js" as PaletteViewModel
import "lib/shortcuts" as Shortcuts

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var service: null

  property bool opened: false
  property bool surfaceVisible: false
  property alias query: queryInput.text
  property string mode: "browse"
  property int selectedIndex: 0
  property var filteredRecords: []
  property var selectedRecord: null
  property string pendingOperation: "browse"
  property string pendingSnapshotId: ""
  property string transientMessage: ""
  property var targetScreen: null
  property double filterStartedAt: 0
  property bool installInTerminal: false
  property bool settingsMenuOpen: false
  property var savedSettings: ({})
  property color shortcutColor: "#e5c07b"
  property color successColor: "#98c379"

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.ilyazar.plugin-control"
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
    || Quickshell.env("HOME") + "/.config"
  readonly property string settingsPath: configHome
    + "/omarchy/ilyazar.plugin-control/settings.json"
  readonly property string themeColorsPath: Color.currentThemePath
    + "/colors.toml"
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color urgent: Color.urgent
  readonly property var borderSpec: Border.surfaceSpec(
    "menu", "border", borderColor, Math.max(1, Style.space(2)))
  readonly property int cardWidth: Math.min(Style.space(720),
    Math.max(Style.space(320), panel.width - Style.gapsOut * 2))
  readonly property int rowHeight: Style.space(60)
  readonly property int headerHeight: Style.space(52)
  readonly property int footerHeight: Style.space(42)
  readonly property bool paletteChromeVisible: !settingsMenuOpen
  readonly property int activeHeaderHeight: paletteChromeVisible
    ? headerHeight : 0
  readonly property int activeFooterHeight: paletteChromeVisible
    ? footerHeight : 0
  readonly property int statusHeight: paletteChromeVisible
    && (leftStatusText.length > 0 || rightStatusText.length > 0)
    ? Style.space(28) : 0
  readonly property int visibleRows: Math.max(1,
    Math.min(6, filteredRecords.length || 1))
  readonly property int resultRowsHeight: visibleRows * rowHeight
    + Math.max(0, visibleRows - 1) * Style.space(2)
  readonly property int chromeSpacingCount: paletteChromeVisible
    ? (statusHeight > 0 ? 3 : 2) : 0
  readonly property int desiredCardHeight: Style.spacing.panelPadding * 2
    + activeHeaderHeight + resultRowsHeight
    + activeFooterHeight + statusHeight
    + Style.spacing.sm * chromeSpacingCount
  readonly property int cardHeight: Math.min(Style.space(600),
    Math.max(Style.space(actionDialog.opened ? 520
      : (selfRemovalDialog.opened ? 280 : 220)),
      Math.min(desiredCardHeight,
        panel.height - restingY - Style.gapsOut)))
  readonly property int topBarOffset: shell && shell.bar
    && shell.bar.position === "top" && shell.bar.barHidden !== true
    ? Number(shell.bar.barSize || 0) : 0
  readonly property int restingY: topBarOffset + Style.gapsOut
  readonly property var shortcutRecord: {
    if (selectedIndex < 0 || selectedIndex >= filteredRecords.length)
      return null
    var record = filteredRecords[selectedIndex]
    return record && record.id && !record.commandCompletion ? record : null
  }
  readonly property bool shortcutHasPluginPage: shortcutRecord
    && shortcutRecord.marketplaceListed === true
  readonly property string marketplaceShortcutLabel: shortcutHasPluginPage
    ? "Plugin website" : "Marketplace"
  readonly property bool actionDialogReadOnly: actionDialog.readOnly
  readonly property string leftStatusText: {
    if (transientMessage) return transientMessage
    if (service && service.actionRunning)
      return String(service.actionState.message || "Working...")
    if (service && service.checkingUpdates) return "Checking for updates..."
    if (service && service.actionState
        && service.actionState.acknowledged === false)
      return String(service.actionState.message || "Action finished.")
    if (service && service.lastUpdateCheckError)
      return "Update check incomplete: " + service.lastUpdateCheckError
    if (service && service.lastSuccessfulUpdateCheck) {
      var timestamp = "Last update: "
        + formatStatusTimestamp(service.lastSuccessfulUpdateCheck)
      if (service.updateCheckSuccessVisible
          && service.lastUpdateCheckNotice)
        return timestamp + "  " + service.lastUpdateCheckNotice
      return timestamp
    }
    return "Updates not checked"
  }
  readonly property string rightStatusText: {
    if (service && service.refreshing) return "Refreshing catalog..."
    if (service && service.lastError) return service.lastError
    if (service && service.lastRefreshError)
      return "Offline/stale: " + service.lastRefreshError
    if (service && service.lastSuccessfulRefresh)
      return "Catalog refreshed: "
        + formatStatusTimestamp(service.lastSuccessfulRefresh)
    return service && service.ready ? "Catalog cache ready" : "Loading local cache..."
  }
  readonly property bool leftStatusActive: service
    && (service.checkingUpdates
      || (service.actionRunning && ["Checking for updates...",
        "Updating plugins..."].indexOf(leftStatusText) >= 0))
  readonly property bool leftSuccessActive: service
    && ((service.updateCheckSuccessVisible === true
        && leftStatusText.indexOf("Last update: ") === 0)
      || (service.actionState && service.actionState.running !== true
        && service.actionState.acknowledged === false
        && service.actionState.ok === true))
  readonly property bool leftUrgent: service
    && ((service.actionState && service.actionState.running !== true
        && service.actionState.acknowledged === false
        && service.actionState.ok === false)
      || service.lastUpdateCheckError)
  readonly property color leftStatusColor: leftStatusActive
    ? shortcutColor : (leftSuccessActive ? successColor
      : (leftUrgent ? urgent : foreground))
  readonly property real leftStatusOpacity: leftStatusActive
    || leftSuccessActive || leftUrgent ? 1 : 0.70
  readonly property bool refreshStatusActive:
    rightStatusText === "Refreshing catalog..."
  readonly property bool refreshSuccessActive: service
    && service.refreshSuccessVisible === true
    && rightStatusText.indexOf("Catalog refreshed: ") === 0
  readonly property color rightStatusColor: refreshStatusActive
    ? shortcutColor : (refreshSuccessActive ? successColor
      : (rightStatusText.indexOf("failed") >= 0
        || rightStatusText.indexOf("Offline") >= 0 ? urgent : foreground))
  readonly property real rightStatusOpacity: refreshStatusActive
    || refreshSuccessActive ? 1 : 0.70

  function resolveTargetScreen() {
    var focused = Hyprland.focusedMonitor
    var name = focused ? String(focused.name || "") : ""
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === name) {
        targetScreen = screens[i]
        return
      }
    }
    targetScreen = screens.length > 0 ? screens[0] : null
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) }
    catch (error) { payload = ({}) }
    resolveTargetScreen()
    if (service) service.recordOpenRequest()
    if (service) service.loadCached()
    closeTimer.stop()
    surfaceVisible = true
    if (service) service.recordSurfaceVisible()
    opened = true
    transientMessage = ""
    query = ""
    selectedIndex = 0
    selectedRecord = null
    pendingSnapshotId = ""
    settingsMenuOpen = false
    actionDialog.closeDialog()
    if (payload.settings === true) showSettingsMenu()
    else rebuildResults()
    Qt.callLater(function() {
      if (actionDialog.opened) actionDialog.forceActiveFocus()
      else if (settingsMenuOpen) resultList.forceActiveFocus()
      else queryInput.forceActiveFocus()
      if (service) service.recordFocusReady()
    })
  }

  function close() {
    if (!surfaceVisible) return
    opened = false
    settingsMenuOpen = false
    actionDialog.closeDialog()
    closeTimer.interval = service && service.animationsEnabled ? 80 : 0
    closeTimer.restart()
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
  }

  function toggle() {
    if (opened) dismiss()
    else open("{}")
  }

  function debugMetrics() {
    return JSON.stringify({
      opened: opened,
      surfaceVisible: surfaceVisible,
      serviceReadyMs: service ? service.serviceReadyMs : -1,
      openRequestMs: service ? service.lastOpenRequestMs : -1,
      focusReadyMs: service ? service.lastFocusReadyMs : -1,
      filterMs: service ? service.lastFilterMs : -1,
      refreshMs: service ? service.lastRefreshDurationMs : -1,
      recordCount: service ? service.catalogRecordCount : 0,
      cacheAgeSeconds: service ? service.cacheAgeSeconds() : -1,
      cacheRefreshedAt: service ? service.lastSuccessfulRefresh : "",
      updateCheckedAt: service ? service.lastSuccessfulUpdateCheck : ""
    })
  }

  function rebuildResults() {
    filterStartedAt = Date.now()
    var records = service && Array.isArray(service.records)
      ? service.records : []
    var result = settingsMenuOpen ? PaletteViewModel.settingsResult()
      : Fuzzy.search(records, query, 50)
    mode = result.mode
    filteredRecords = result.results
    displayModel.clear()
    for (var i = 0; i < filteredRecords.length; i++) {
      displayModel.append(PaletteViewModel.displayRecord(filteredRecords[i]))
    }
    selectedIndex = displayModel.count > 0
      ? Math.max(0, Math.min(selectedIndex, displayModel.count - 1)) : 0
    if (service) service.recordFilterDuration(Date.now() - filterStartedAt)
    Qt.callLater(positionSelection)
  }

  function positionSelection() {
    if (displayModel.count > 0)
      resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function select(index) {
    if (displayModel.count === 0) return
    selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    positionSelection()
  }

  function completeCommand(index) {
    if (index < 0 || index >= filteredRecords.length) return false
    var candidate = filteredRecords[index]
    if (!candidate) return false
    var completion = String(candidate.commandCompletion || "")
    if (!completion) return false
    queryInput.text = completion
    queryInput.cursorPosition = queryInput.text.length
    queryInput.forceActiveFocus()
    if (String(candidate.operation || "") === "update"
        && service) service.requestUpdateCheck()
    return true
  }

  function openDialogFor(record, readOnly) {
    if (!record || !record.id || record.commandCompletion) return false
    selectedRecord = JSON.parse(JSON.stringify(record))
    pendingOperation = "browse"
    pendingSnapshotId = readOnly === true ? ""
      : (service && service.snapshot
          ? String(service.snapshot.snapshotId || "") : "")
    actionDialog.readOnly = readOnly === true
    actionDialog.openDialog()
    return true
  }

  function activateIndex(index) {
    if (index < 0 || index >= filteredRecords.length) return
    if (filteredRecords[index].settingsAction) {
      activateSettings(filteredRecords[index].settingsAction)
      return
    }
    if (completeCommand(index)) return
    var record = filteredRecords[index]
    openDialogFor(record, false)
  }

  function openSelectedInfo() {
    return openDialogFor(shortcutRecord, true)
  }

  function confirmAction(operation) {
    if (!selectedRecord || !service) return
    pendingOperation = String(operation || "")
    if (["add", "remove", "update", "enable", "disable"]
        .indexOf(pendingOperation) < 0) return
    if (pendingOperation === "remove"
        && String(selectedRecord.id || "") === pluginId) {
      actionDialog.closeDialog()
      openSelfRemovalDialog()
      return
    }
    if (!pendingSnapshotId) {
      transientMessage = "No actionable catalog snapshot is available."
      actionDialog.closeDialog()
      return
    }
    var executionMode = actionDialog.terminalInstall
      ? "terminal" : "background"
    if (service.startAction(pendingOperation,
        String(selectedRecord.id || ""), pendingSnapshotId, executionMode)) {
      transientMessage = executionMode === "terminal"
        ? "Opening Omarchy terminal..." : ""
      actionDialog.closeDialog()
      if (executionMode === "terminal") dismiss()
      else queryInput.forceActiveFocus()
    }
  }

  function deletePreviousWord(value) {
    var text = String(value || "")
    var trimmed = text.replace(/\s+$/, "")
    return trimmed.replace(/\S+$/, "")
  }

  function loadSettings(raw) {
    try {
      var value = JSON.parse(String(raw || "{}"))
      savedSettings = value && typeof value === "object"
        && !Array.isArray(value) ? value : ({})
    } catch (error) {
      savedSettings = ({})
    }
    installInTerminal = savedSettings.installInTerminal === true
  }

  function setInstallInTerminal(enabled) {
    var next = ({ installInTerminal: enabled === true })
    savedSettings = next
    installInTerminal = next.installInTerminal
    settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function padTimePart(value) {
    return Number(value) < 10 ? "0" + Number(value) : String(Number(value))
  }

  function formatStatusTimestamp(value) {
    var instant = new Date(String(value || ""))
    if (!isFinite(instant.getTime())) return String(value || "")
    var time = padTimePart(instant.getHours()) + ":"
      + padTimePart(instant.getMinutes()) + ":"
      + padTimePart(instant.getSeconds())
    var date = instant.getFullYear() + "-"
      + padTimePart(instant.getMonth() + 1) + "-"
      + padTimePart(instant.getDate())
    return time + " (" + date + ")"
  }

  function loadStatusColors(raw) {
    var yellowMatch = String(raw || "").match(
      /^\s*(?:yellow|color3)\s*=\s*["']?(#[0-9A-Fa-f]{6})/im)
    var greenMatch = String(raw || "").match(
      /^\s*(?:green|color2)\s*=\s*["']?(#[0-9A-Fa-f]{6})/im)
    shortcutColor = yellowMatch ? yellowMatch[1] : "#e5c07b"
    successColor = greenMatch ? greenMatch[1] : "#98c379"
  }

  function openWebsite(url) {
    dismiss()
    Quickshell.execDetached([omarchyPath + "/bin/omarchy", "launch",
      "browser", url])
  }

  function validGithubRepository(value) {
    return /^https:\/\/github\.com\/[A-Za-z0-9][A-Za-z0-9-]{0,38}\/[A-Za-z0-9._-]{1,100}\/?$/
      .test(String(value || ""))
  }

  function marketplaceShortcutUrl() {
    if (!shortcutHasPluginPage) return "https://omarchyplugins.com/"
    return "https://omarchyplugins.com/plugin.html?id="
      + encodeURIComponent(String(shortcutRecord.id))
  }

  function githubShortcutUrl() {
    if (shortcutRecord && validGithubRepository(shortcutRecord.repository))
      return String(shortcutRecord.repository).replace(/\/$/, "")
    return "https://github.com/HANCORE-linux/omarchy-plugin-marketplace"
  }

  function openMarketplaceShortcut() {
    openWebsite(marketplaceShortcutUrl())
  }

  function openGithubShortcut() {
    openWebsite(githubShortcutUrl())
  }

  function openSettings() {
    showSettingsMenu()
  }

  function showSettingsMenu() {
    settingsMenuOpen = true
    queryInput.text = ""
    selectedIndex = 0
    rebuildResults()
    resultList.forceActiveFocus()
  }

  function closeSettingsMenu() {
    settingsMenuOpen = false
    queryInput.text = ""
    selectedIndex = 0
    rebuildResults()
    queryInput.forceActiveFocus()
  }

  function activateSettings(action) {
    if (action === "cancel") {
      closeSettingsMenu()
      return
    }
    if (action === "remove-self") {
      openSelfRemovalDialog()
      return
    }
    if (["plugin", "keybindings"].indexOf(String(action)) < 0) return
    dismiss()
    Quickshell.execDetached([sourcePath("scripts/open-settings.sh"),
      String(action), sourceDir()])
  }

  function openSelfRemovalDialog() {
    if (!service || !Array.isArray(service.records) || !service.snapshot
        || !service.snapshot.snapshotId) {
      transientMessage = "No current plugin snapshot is available."
      return false
    }
    var record = PaletteViewModel.removableRecord(service.records, pluginId)
    if (record) {
      selectedRecord = JSON.parse(JSON.stringify(record))
      pendingSnapshotId = String(service.snapshot.snapshotId)
      selfRemovalDialog.openDialog()
      return true
    }
    transientMessage = "Plugin Control is not available for removal."
    return false
  }

  function confirmSelfRemoval(deleteUserData) {
    if (!service || !selectedRecord || !pendingSnapshotId) return
    var operation = deleteUserData === true ? "remove-purge" : "remove"
    if (service.startAction(operation, pluginId, pendingSnapshotId,
        "background")) {
      transientMessage = deleteUserData === true
        ? "Cleaning user data and removing Plugin Control..."
        : "Removing Plugin Control and preserving user data..."
      selfRemovalDialog.closeDialog()
      resultList.forceActiveFocus()
    }
  }

  function dismissStatus() {
    transientMessage = ""
    if (service) service.acknowledgeAction()
  }

  function sourceDir() {
    return manifest && manifest.__sourceDir
      ? String(manifest.__sourceDir) : ""
  }

  function sourcePath(relative) {
    return sourceDir() + "/" + relative
  }

  function isControlShortcut(event, key) {
    return event.modifiers === Qt.ControlModifier && event.key === key
  }

  function isCompletedCommandPrefix(value, cursor, selectionStart,
      selectionEnd) {
    var text = String(value || "")
    return cursor === text.length && selectionStart === selectionEnd
      && ["plug-add:", "plug-install:", "plug-remove:", "plug-enable:",
        "plug-disable:", "plug-update:"].indexOf(text) >= 0
  }

  function clearCompletedCommandPrefix() {
    if (!isCompletedCommandPrefix(queryInput.text, queryInput.cursorPosition,
        queryInput.selectionStart, queryInput.selectionEnd)) return false
    queryInput.text = ""
    queryInput.cursorPosition = 0
    return true
  }

  function startTypedUpdateCommand() {
    var current = String(queryInput.text || "")
    if (/\s$/.test(current) || current.trim().toLowerCase()
        !== "plug-update:") return false
    queryInput.text = "plug-update: "
    queryInput.cursorPosition = queryInput.text.length
    if (service) service.requestUpdateCheck()
    return true
  }

  function handleKey(event) {
    if (actionDialog.opened) return actionDialog.handleKey(event)
    var control = (event.modifiers & Qt.ControlModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0

    if (settingsMenuOpen) {
      if (event.key === Qt.Key_Escape) closeSettingsMenu()
      else if (event.key === Qt.Key_Up
          || (event.modifiers === Qt.NoModifier && event.key === Qt.Key_K))
        select(selectedIndex - 1)
      else if (event.key === Qt.Key_Down
          || (event.modifiers === Qt.NoModifier && event.key === Qt.Key_J))
        select(selectedIndex + 1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
        activateIndex(selectedIndex)
      return true
    }

    if (isControlShortcut(event, Qt.Key_P)) {
      dismiss()
    } else if (event.key === Qt.Key_Escape) {
      dismiss()
    } else if (isControlShortcut(event, Qt.Key_I)) {
      openSelectedInfo()
    } else if (isControlShortcut(event, Qt.Key_W)) {
      openMarketplaceShortcut()
    } else if (isControlShortcut(event, Qt.Key_G)) {
      openGithubShortcut()
    } else if (isControlShortcut(event, Qt.Key_S)) {
      openSettings()
    } else if (isControlShortcut(event, Qt.Key_R)) {
      transientMessage = ""
      if (service) service.requestRefresh(true)
    } else if (isControlShortcut(event, Qt.Key_U)) {
      transientMessage = ""
      queryInput.text = "plug-update: "
      queryInput.cursorPosition = queryInput.text.length
      if (service) service.requestUpdateCheck()
    } else if (isControlShortcut(event, Qt.Key_Backspace)) {
      queryInput.text = deletePreviousWord(queryInput.text)
    } else if (event.modifiers === Qt.NoModifier
        && event.key === Qt.Key_Backspace) {
      return clearCompletedCommandPrefix()
    } else if (event.key === Qt.Key_Up) {
      select(selectedIndex - 1)
    } else if (event.key === Qt.Key_Down) {
      select(selectedIndex + 1)
    } else if (event.key === Qt.Key_PageUp) {
      select(selectedIndex - 5)
    } else if (event.key === Qt.Key_PageDown) {
      select(selectedIndex + 5)
    } else if (event.key === Qt.Key_Home) {
      select(0)
    } else if (event.key === Qt.Key_End) {
      select(displayModel.count - 1)
    } else if (!control && !alt && event.key === Qt.Key_Tab) {
      if (!startTypedUpdateCommand()) completeCommand(selectedIndex)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (!startTypedUpdateCommand()) activateIndex(selectedIndex)
    } else {
      return false
    }
    return true
  }

  ListModel { id: displayModel }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("")
    onFileChanged: reload()
  }

  FileView {
    id: themeColorsFile
    path: root.themeColorsPath
    watchChanges: false
    printErrors: false
    onLoaded: root.loadStatusColors(text())
  }

  Connections {
    target: Color
    function onShellValuesChanged() { themeColorsFile.reload() }
  }

  Shortcuts.HyprlandBinding {
    id: paletteBinding
    actionDescription: "Plugin Control"
  }

  Connections {
    target: root.service
    function onRecordsChanged() { root.rebuildResults() }
    function onActionFinished(state) {
      root.transientMessage = ""
      root.rebuildResults()
    }
  }

  Timer {
    id: closeTimer
    repeat: false
    onTriggered: root.surfaceVisible = false
  }

  PanelWindow {
    id: panel
    visible: root.surfaceVisible
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "ilyazar.plugin-control"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.surfaceVisible
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: card.reveal
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      property real reveal: root.opened ? 1 : 0

      width: root.cardWidth
      height: root.cardHeight
      x: Math.round((panel.width - width) / 2)
      y: root.restingY - Math.round((1 - reveal) * Style.space(18))
      opacity: reveal
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      Behavior on reveal {
        enabled: root.service ? root.service.animationsEnabled : true
        NumberAnimation {
          duration: root.opened ? 110 : 75
          easing.type: Easing.OutCubic
        }
      }

      MouseArea { anchors.fill: parent; onClicked: {} }

      ActionDialog {
        id: actionDialog
        anchors.fill: parent
        z: 20
        plugin: root.selectedRecord
        selfId: root.pluginId
        busy: root.service ? root.service.actionRunning : false
        installInTerminal: root.installInTerminal
        background: root.background
        foreground: root.foreground
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        warningColor: root.urgent
        onCanceled: {
          closeDialog()
          queryInput.forceActiveFocus()
        }
        onTerminalInstallToggled: function(enabled) {
          root.setInstallInTerminal(enabled)
        }
        onActionRequested: function(operation) {
          root.confirmAction(operation)
        }
      }

      SelfRemovalDialog {
        id: selfRemovalDialog
        anchors.fill: parent
        z: 30
        busy: root.service ? root.service.actionRunning : false
        background: root.background
        foreground: root.foreground
        selectedBackground: root.selectedBackground
        selectedText: root.selectedText
        warningColor: root.urgent
        onCanceled: {
          closeDialog()
          resultList.forceActiveFocus()
        }
        onRemoveRequested: function(deleteUserData) {
          root.confirmSelfRemoval(deleteUserData)
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.sm

        Rectangle {
          visible: root.paletteChromeVisible
          width: parent.width
          height: root.activeHeaderHeight
          radius: Style.cornerRadius
          color: Util.alpha(root.foreground, 0.06)

          Text {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"
            color: root.foreground
            opacity: 0.70
            font.family: Style.font.family
            font.pixelSize: Style.font.iconLarge
          }

          TextInput {
            id: queryInput
            anchors.left: searchIcon.right
            anchors.leftMargin: Style.spacing.sm
            anchors.right: shortcutLabel.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            selectionColor: root.selectedBackground
            selectedTextColor: root.selectedText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.heading
            clip: true
            readOnly: root.settingsMenuOpen
            selectByMouse: true
            activeFocusOnTab: true
            onTextChanged: {
              root.selectedIndex = 0
              root.transientMessage = ""
              root.rebuildResults()
            }
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (root.handleKey(event)) event.accepted = true
            }

            Text {
              visible: !queryInput.text
              anchors.fill: parent
              text: "Search plugins or type plug-add: / plug-update:"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.48
              font: queryInput.font
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
            }
          }

          Text {
            id: shortcutLabel
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: paletteBinding.label
            color: root.foreground
            opacity: 0.55
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
        }

        Item {
          width: parent.width
          height: Math.max(root.rowHeight,
            parent.height - root.activeHeaderHeight - root.activeFooterHeight
              - root.statusHeight
              - parent.spacing * root.chromeSpacingCount)
          clip: true

          ListView {
            id: resultList
            focus: root.settingsMenuOpen
            anchors.fill: parent
            visible: displayModel.count > 0
            model: displayModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Style.space(2)
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (root.settingsMenuOpen && root.handleKey(event))
                event.accepted = true
            }

            delegate: PaletteResultRow {
              width: ListView.view.width
              selected: index === root.selectedIndex
              settingsMenuOpen: root.settingsMenuOpen
              rowHeight: root.rowHeight
              foreground: root.foreground
              selectedBackground: root.selectedBackground
              selectedText: root.selectedText
              urgent: root.urgent
              onHovered: root.select(index)
              onActivated: {
                root.select(index)
                root.activateIndex(index)
              }
              onRepositoryRequested: function(url) { root.openWebsite(url) }
            }
          }

          Text {
            visible: displayModel.count === 0
            anchors.fill: parent
            text: root.mode === "update"
              ? (root.service && root.service.checkingUpdates
                ? "Checking installed plugins..."
                : (root.service && root.service.lastUpdateCheckError
                  ? "No safely updateable plugins found"
                  : "All plugins are up to date!"))
              : (root.mode === "add"
              ? "No plugins available to add match this query"
              : (root.mode === "remove"
                ? "No removable local plugins match this query"
                : (root.mode === "enable"
                  ? "No disabled plugins match this query"
                  : (root.mode === "disable"
                    ? "No enabled plugins match this query"
                    : (root.mode === "command"
                      ? "No command matches this query"
                      : "No plugins match this query")))))
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.62
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
          }
        }

        Item {
          visible: root.statusHeight > 0
          width: parent.width
          height: root.statusHeight

          Text {
            anchors.left: parent.left
            anchors.right: statusGap.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.leftStatusText
            textFormat: Text.PlainText
            color: root.leftStatusColor
            opacity: root.leftStatusOpacity
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter

            MouseArea {
              anchors.fill: parent
              enabled: root.service && root.service.actionState
                && root.service.actionState.acknowledged === false
              onClicked: root.dismissStatus()
            }
          }

          Item {
            id: statusGap
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.spacing.sm
            height: 1
          }

          Text {
            anchors.left: statusGap.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.rightStatusText
            textFormat: Text.PlainText
            color: root.rightStatusColor
            opacity: root.rightStatusOpacity
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            verticalAlignment: Text.AlignVCenter
          }
        }

        PaletteFooter {
          visible: root.paletteChromeVisible
          width: parent.width
          height: root.activeFooterHeight
          marketplaceLabel: root.marketplaceShortcutLabel
          foreground: root.foreground
          shortcutColor: root.shortcutColor
        }
      }
    }
  }
}
