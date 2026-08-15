import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Fuzzy.js" as Fuzzy
import "CatalogModel.js" as CatalogModel
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

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.ilyazar.plugin-control"
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
    || Quickshell.env("HOME") + "/.config"
  readonly property string settingsPath: configHome
    + "/omarchy/plugin-control/settings.json"
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
    && statusText.length > 0 ? Style.space(28) : 0
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
  readonly property int cardHeight: Math.min(Style.space(500),
    Math.max(Style.space(actionDialog.opened ? 420 : 220),
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
    ? "Plugin page" : "Marketplace"
  readonly property string statusText: {
    if (transientMessage) return transientMessage
    if (service && service.actionRunning)
      return String(service.actionState.message || "Working...")
    if (service && service.actionState
        && service.actionState.acknowledged === false)
      return String(service.actionState.message || "Action finished.")
    if (service && service.refreshing) return "Refreshing catalog..."
    if (service && service.lastError) return service.lastError
    if (service && service.lastRefreshError)
      return "Offline/stale: " + service.lastRefreshError
    if (service && service.lastSuccessfulRefresh)
      return "Cached catalog - refreshed " + service.lastSuccessfulRefresh
    return service && service.ready ? "Cached catalog ready" : "Loading local cache..."
  }

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
      if (settingsMenuOpen) resultList.forceActiveFocus()
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
      cacheRefreshedAt: service ? service.lastSuccessfulRefresh : ""
    })
  }

  function rebuildResults() {
    filterStartedAt = Date.now()
    var records = service && Array.isArray(service.records)
      ? service.records : []
    var result = settingsMenuOpen ? {
      mode: "settings",
      results: [
        {
          name: "Plugin settings",
          description: "Edit channels and tray defaults",
          settingsAction: "plugin"
        },
        {
          name: "Keybindings",
          description: "Edit the user-owned Plugin Control shortcut",
          settingsAction: "keybindings"
        },
        {
          name: "Cancel / Back",
          description: "Return to the plugin list",
          settingsAction: "cancel"
        }
      ]
    } : Fuzzy.search(records, query, 50, pluginId)
    mode = result.mode
    filteredRecords = result.results
    displayModel.clear()
    for (var i = 0; i < filteredRecords.length; i++) {
      var record = filteredRecords[i]
      displayModel.append({
        pluginName: String(record.name || record.id || ""),
        pluginId: String(record.id || ""),
        description: String(record.description || ""),
        author: String(record.author || "Unknown"),
        kind: String(record.kind || record.category || "Plugin"),
        stateLabel: String(record.stateLabel || "Browse only"),
        sourceLabel: String(record.sourceLabel || record.sourceName || "Unknown"),
        warning: String(record.warning || ""),
        version: String(record.version || ""),
        releaseTag: String(record.releaseTag || ""),
        repository: String(record.repository || "")
      })
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

  function availableOperation(record) {
    if (!record) return "browse"
    if (mode === "install") return "install"
    if (mode === "remove") return "remove"
    if (record.builtIn === true) {
      var kind = String(record.kind || "").toLowerCase()
      if (kind === "bar") return "browse"
      if (CatalogModel.isBarWidget(kind))
        return record.enabled === false ? "add-bar" : "disable"
      return record.enabled === false ? "enable" : "disable"
    }
    if (record.installed === true && record.removable === true) return "remove"
    if (record.installable === true) return "install"
    return "browse"
  }

  function completeCommand(index) {
    if (index < 0 || index >= filteredRecords.length) return false
    var completion = String(filteredRecords[index].commandCompletion || "")
    if (!completion) return false
    queryInput.text = completion
    queryInput.cursorPosition = queryInput.text.length
    queryInput.forceActiveFocus()
    return true
  }

  function openDialogFor(record, operation) {
    if (!record || !record.id || record.commandCompletion) return false
    selectedRecord = JSON.parse(JSON.stringify(record))
    pendingOperation = String(operation || "browse")
    pendingSnapshotId = pendingOperation === "browse" ? ""
      : (service && service.snapshot
        ? String(service.snapshot.snapshotId || "") : "")
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
    var operation = availableOperation(record)
    if (operation === "browse") return
    openDialogFor(record, operation)
  }

  function openSelectedInfo() {
    return openDialogFor(shortcutRecord, "browse")
  }

  function confirmAction() {
    if (!selectedRecord || !service) return
    if (pendingOperation === "browse") return
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
        ? "Opening Omarchy terminal..." : "Action queued..."
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

  function loadShortcutColor(raw) {
    var match = String(raw || "").match(
      /^\s*(?:yellow|color3)\s*=\s*["']?(#[0-9A-Fa-f]{6})/im)
    shortcutColor = match ? match[1] : "#e5c07b"
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
    if (["plugin", "keybindings"].indexOf(String(action)) < 0) return
    dismiss()
    Quickshell.execDetached([sourcePath("scripts/open-settings.sh"),
      String(action), sourceDir()])
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
      && (text === "plug-install:" || text === "plug-remove:")
  }

  function clearCompletedCommandPrefix() {
    if (!isCompletedCommandPrefix(queryInput.text, queryInput.cursorPosition,
        queryInput.selectionStart, queryInput.selectionEnd)) return false
    queryInput.text = ""
    queryInput.cursorPosition = 0
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
    } else if (isControlShortcut(event, Qt.Key_D)) {
      openSelectedInfo()
    } else if (isControlShortcut(event, Qt.Key_O)) {
      openMarketplaceShortcut()
    } else if (isControlShortcut(event, Qt.Key_G)) {
      openGithubShortcut()
    } else if (isControlShortcut(event, Qt.Key_S)) {
      openSettings()
    } else if (isControlShortcut(event, Qt.Key_R)) {
      transientMessage = ""
      if (service) service.requestRefresh(true)
    } else if (isControlShortcut(event, Qt.Key_U)) {
      queryInput.text = ""
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
      completeCommand(selectedIndex)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      activateIndex(selectedIndex)
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
    onLoaded: root.loadShortcutColor(text())
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
    WlrLayershell.namespace: "plugin-control"
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
        operation: root.pendingOperation
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
        onConfirmed: root.confirmAction()
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
              text: "Search plugins or type plug-install: / plug-remove:"
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

            delegate: Rectangle {
              id: resultRow
              required property int index
              required property string pluginName
              required property string pluginId
              required property string description
              required property string author
              required property string kind
              required property string stateLabel
              required property string sourceLabel
              required property string warning
              required property string version
              required property string releaseTag
              required property string repository

              readonly property bool selected: index === root.selectedIndex
              width: ListView.view.width
              height: root.rowHeight
              radius: Style.cornerRadius
              color: selected ? root.selectedBackground : "transparent"

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.select(resultRow.index)
                onClicked: {
                  root.select(resultRow.index)
                  root.activateIndex(resultRow.index)
                }
              }

              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.right: badgeColumn.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Row {
                  width: parent.width
                  spacing: Style.spacing.sm
                  Text {
                    width: Math.min(implicitWidth, parent.width
                      * (root.settingsMenuOpen ? 1 : 0.52))
                    text: resultRow.pluginName
                    textFormat: Text.PlainText
                    color: resultRow.selected ? root.selectedText : root.foreground
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    visible: !root.settingsMenuOpen
                    width: parent.width - x
                    text: resultRow.pluginId
                    textFormat: Text.PlainText
                    color: resultRow.selected ? root.selectedText : root.foreground
                    opacity: 0.60
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                }

                Text {
                  width: parent.width
                  text: root.settingsMenuOpen ? resultRow.description
                    : resultRow.author + " - "
                      + (resultRow.description || resultRow.kind)
                  textFormat: Text.PlainText
                  color: resultRow.selected ? root.selectedText : root.foreground
                  opacity: 0.65
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignLeft
                }

                Text {
                  id: repositoryText
                  z: 2
                  visible: !root.settingsMenuOpen
                    && resultRow.repository !== ""
                  width: parent.width
                  text: resultRow.repository
                  textFormat: Text.PlainText
                  color: resultRow.selected ? root.selectedText : root.foreground
                  opacity: repositoryMouse.containsMouse ? 0.90 : 0.48
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.underline: repositoryMouse.containsMouse
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignLeft

                  MouseArea {
                    id: repositoryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.select(resultRow.index)
                    onClicked: root.openWebsite(resultRow.repository)
                  }
                }
              }

              Column {
                id: badgeColumn
                visible: !root.settingsMenuOpen
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? Style.space(178) : 0
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: resultRow.stateLabel
                    + (resultRow.version ? "  " + resultRow.version : "")
                    + (resultRow.releaseTag ? "  " + resultRow.releaseTag : "")
                  textFormat: Text.PlainText
                  color: resultRow.selected ? root.selectedText : root.foreground
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideLeft
                }
                Text {
                  width: parent.width
                  text: resultRow.sourceLabel + (resultRow.warning
                    ? " - " + resultRow.warning : "")
                  textFormat: Text.PlainText
                  color: resultRow.warning ? root.urgent
                    : (resultRow.selected ? root.selectedText : root.foreground)
                  opacity: resultRow.warning ? 1 : 0.55
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideRight
                }
              }

            }
          }

          Text {
            visible: displayModel.count === 0
            anchors.fill: parent
            text: root.mode === "install"
              ? "No installable plugins match this query"
              : (root.mode === "remove"
                ? "No removable local plugins match this query"
                : (root.mode === "command"
                  ? "No command matches this query"
                  : "No plugins match this query"))
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.62
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
          }
        }

        Text {
          visible: root.statusHeight > 0
          width: parent.width
          height: root.statusHeight
          text: root.statusText
          textFormat: Text.PlainText
          color: root.statusText.indexOf("failed") >= 0
            || root.statusText.indexOf("Offline") >= 0
            ? root.urgent : root.foreground
          opacity: 0.70
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
          visible: root.paletteChromeVisible
          width: parent.width
          height: root.activeFooterHeight

          Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: Util.alpha(root.foreground, 0.16)
          }

          Row {
            id: footerRow
            anchors.fill: parent
            anchors.topMargin: Style.space(6)

            Repeater {
              model: [
                { keyLabel: "[Ctrl+D]", label: "Details" },
                { keyLabel: "[Ctrl+O]",
                  label: root.marketplaceShortcutLabel },
                { keyLabel: "[Ctrl+G]", label: "GitHub source" },
                { keyLabel: "[Ctrl+R]", label: "Refresh" },
                { keyLabel: "[Ctrl+S]", label: "Settings" }
              ]

              delegate: Item {
                required property var modelData
                width: footerRow.width / 5
                height: footerRow.height

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(2)

                  Rectangle {
                    width: keyText.implicitWidth + Style.spacing.sm
                    height: Style.space(22)
                    radius: Style.space(4)
                    color: Util.alpha(root.shortcutColor, 0.10)
                    border.width: 1
                    border.color: Util.alpha(root.shortcutColor, 0.70)

                    Text {
                      id: keyText
                      anchors.centerIn: parent
                      text: modelData.keyLabel
                      textFormat: Text.PlainText
                      color: root.shortcutColor
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label
                    textFormat: Text.PlainText
                    color: root.foreground
                    opacity: 0.72
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
