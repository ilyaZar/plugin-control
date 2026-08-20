import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  readonly property string sourceDir:
    Quickshell.env("PLUGIN_CONTROL_SOURCE_DIR")
  property var createdObjects: []
  property var serviceObject: null
  property int dialogCanceledCount: 0
  property int dialogConfirmedCount: 0
  property string lastDialogOperation: ""
  property int removalCanceledCount: 0
  property int removalPreserveCount: 0
  property int removalPurgeCount: 0
  property bool entryChecksComplete: false
  property bool watcherSaveStarted: false
  property int watcherWaitAttempts: 0

  function manifestData() {
    return {
      schemaVersion: 1,
      id: "io.github.ilyazar.plugin-control",
      name: "Plugin Control",
      version: "test",
      kinds: ["service", "overlay", "bar-widget"],
      entryPoints: {
        service: "Service.qml",
        overlay: "PluginControl.qml",
        barWidget: "PluginControlBar.qml"
      },
      __sourceDir: sourceDir
    }
  }

  function loadEntry(fileName, kind) {
    var url = encodeURI("file://" + sourceDir + "/" + fileName)
    var component = Qt.createComponent(url, Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      console.error("PLUGIN_CONTROL_LOAD_ERROR " + kind + ": "
        + component.errorString())
      return null
    }
    var object = component.createObject(host)
    if (!object) {
      console.error("PLUGIN_CONTROL_CREATE_ERROR " + kind + ": "
        + component.errorString())
      return null
    }
    if ("manifest" in object) object.manifest = manifestData()
    if ("shell" in object) object.shell = mockShell
    if ("pluginRegistry" in object) object.pluginRegistry = mockPluginRegistry
    createdObjects.push(object)
    console.log("PLUGIN_CONTROL_LOAD_OK " + kind)
    return object
  }

  Item { id: host }

  FileView {
    id: testConfigFile
    path: Quickshell.env("XDG_CONFIG_HOME")
      + "/omarchy/ilyazar.plugin-control/channels.yaml"
    blockLoading: true
    blockWrites: true
    atomicWrites: true
    printErrors: false
  }

  QtObject {
    id: mockBarWidgetRegistry
    function metadataFor(moduleName) {
      return { sourceDir: root.sourceDir }
    }
  }

  QtObject {
    id: mockPluginRegistry
    property int settingCalls: 0
    property string lastSettingId: ""
    property string lastSettingKey: ""
    property var lastSettingValue: null
    property string settingError: ""
    function setBarWidget(id, key, value, selector) {
      settingCalls++
      lastSettingId = String(id)
      lastSettingKey = String(key)
      lastSettingValue = value
      return settingError
    }
  }

  QtObject {
    id: mockBar
    property string position: "top"
    property bool barHidden: false
    property bool vertical: false
    property int barSize: 32
    property string fontFamily: "JetBrainsMono Nerd Font"
    property color barForeground: "white"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    property var shell: mockShell
    property var barWidgetRegistry: mockBarWidgetRegistry
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
    function registerClickTarget(item) {}
    function unregisterClickTarget(item) {}
  }

  QtObject {
    id: mockShell
    property var bar: mockBar
    property string lastToggleId: ""
    property string lastTogglePayload: ""
    property string lastSummonId: ""
    property string lastSummonPayload: ""
    function hide(pluginId) { return true }
    function isPluginOpen(pluginId) { return false }
    function serviceFor(pluginId) { return root.serviceObject }
    function toggle(pluginId, payloadJson) {
      lastToggleId = pluginId
      lastTogglePayload = payloadJson
    }
    function summon(pluginId, payloadJson) {
      lastSummonId = pluginId
      lastSummonPayload = payloadJson
      return true
    }
  }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      root.serviceObject = root.loadEntry("Service.qml", "service")
      if (root.serviceObject) {
        if (!root.serviceObject.initialLoadStarted) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR late service initialization")
        }
        mockPluginRegistry.settingCalls = 0
        var hiddenSnapshot = JSON.stringify({
          ok: true,
          records: [],
          config: { settings: { "tray-icon-hidden": true } }
        })
        root.serviceObject.applySnapshot(hiddenSnapshot, 0, false)
        if (mockPluginRegistry.settingCalls !== 0) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR startup tray override")
        }
        root.serviceObject.configChangeRevision = 2
        var hiddenConfigStatus = JSON.stringify({
          ok: true,
          usingLastGood: false,
          config: {
            version: 2,
            settings: { "tray-icon-hidden": true }
          }
        })
        root.serviceObject.applyConfigStatus(hiddenConfigStatus, 0, 1)
        if (mockPluginRegistry.settingCalls !== 0) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR stale tray setting")
        }
        root.serviceObject.applyConfigStatus(JSON.stringify({
          ok: false,
          usingLastGood: true,
          config: {
            version: 2,
            settings: { "tray-icon-hidden": true }
          }
        }), 0, 2)
        if (mockPluginRegistry.settingCalls !== 0) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR invalid tray setting")
        }
        var invalidNotice = root.serviceObject.configProblemNotice(
          JSON.stringify({
            ok: false,
            field: "settings.tray-icon-hidden",
            actual: '"hidden"',
            expected: "true or false",
            fallback: "last-good"
          }))
        if (invalidNotice !== '"hidden" is not admissible for '
            + "settings.tray-icon-hidden. Set it to true or false. "
            + "Keeping the last valid settings.") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR config problem notice")
        }
        var defaultNotice = root.serviceObject.configProblemNotice(
          JSON.stringify({
            ok: false,
            field: "refresh_minutes",
            actual: '"fast"',
            expected: "an integer from 5 through 1440",
            fallback: "defaults"
          }))
        if (defaultNotice.indexOf("Using shipped defaults.") < 0) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR config default notice")
        }
        root.serviceObject.applyConfigStatus(hiddenConfigStatus, 0, 2)
        if (mockPluginRegistry.settingCalls !== 1
            || mockPluginRegistry.lastSettingId
              !== "io.github.ilyazar.plugin-control"
            || mockPluginRegistry.lastSettingKey !== "trayIconHidden"
            || mockPluginRegistry.lastSettingValue !== true) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR live tray setting")
        }
        root.serviceObject.configChangeRevision = 3
        root.serviceObject.applyConfigStatus(JSON.stringify({
          ok: true,
          usingLastGood: false,
          config: {
            version: 2,
            settings: { "tray-icon-hidden": false }
          }
        }), 0, 3)
        if (mockPluginRegistry.settingCalls !== 2
            || mockPluginRegistry.lastSettingValue !== false) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR live tray setting update")
        }
        mockPluginRegistry.settingError = "could not find widget"
        root.serviceObject.configChangeRevision = 4
        if (root.serviceObject.applyConfigStatus(hiddenConfigStatus, 0, 4)
            || mockPluginRegistry.settingCalls !== 3) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR tray setting failure")
        }
        mockPluginRegistry.settingError = ""
        root.serviceObject.configChangeRevision = 5
        if (!root.serviceObject.applyConfigStatus(hiddenConfigStatus, 0, 5)
            || mockPluginRegistry.settingCalls !== 4
            || mockPluginRegistry.lastSettingValue !== true) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR tray setting retry")
        }
      }
      var overlay = root.loadEntry("PluginControl.qml", "overlay")
      if (overlay && "service" in overlay) {
        overlay.service = root.serviceObject
        overlay.query = "plug-ad"
        if (overlay.mode !== "command"
            || overlay.filteredRecords.length !== 1
            || overlay.selectedRecord !== null) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR add completion stage")
        }
        var tabEvent = { modifiers: 0, key: Qt.Key_Tab }
        var backspaceEvent = { modifiers: 0, key: Qt.Key_Backspace }
        var addPrefix = "plug-add:"
        var installAlias = "plug-install:"
        if (!overlay.isCompletedCommandPrefix(addPrefix,
              addPrefix.length, addPrefix.length, addPrefix.length)
            || !overlay.isCompletedCommandPrefix(installAlias,
              installAlias.length, installAlias.length, installAlias.length)
            || overlay.isCompletedCommandPrefix(addPrefix,
              addPrefix.length - 1, addPrefix.length - 1,
              addPrefix.length - 1)
            || overlay.isCompletedCommandPrefix(addPrefix,
              addPrefix.length, 0, addPrefix.length)
            || overlay.isCompletedCommandPrefix("PLUG-ADD:",
              addPrefix.length, addPrefix.length, addPrefix.length)) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR backspace boundary")
        }
        if (!overlay.handleKey(tabEvent))
          console.error("PLUGIN_CONTROL_LOAD_ERROR tab dispatch")
        if (overlay.query !== "plug-add: " || overlay.mode !== "add"
            || overlay.selectedRecord !== null) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR add completion")
        }
        if (overlay.handleKey(backspaceEvent)
            || overlay.query !== "plug-add: ") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR completion space backspace")
        }
        overlay.query = "plug-add:"
        if (!overlay.handleKey(backspaceEvent) || overlay.query !== "") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR add prefix backspace")
        }
        overlay.query = "plug-rm"
        var enterEvent = { modifiers: 0, key: Qt.Key_Return }
        if (!overlay.handleKey(enterEvent)
            || overlay.query !== "plug-remove: "
            || overlay.mode !== "remove") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR remove completion")
        }
        overlay.query = "plug-remove: notes"
        if (overlay.handleKey(backspaceEvent)
            || overlay.query !== "plug-remove: notes") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR suffix backspace ownership")
        }
        overlay.query = "plug-remove: "
        if (overlay.handleKey(backspaceEvent)
            || overlay.query !== "plug-remove: ") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR remove space backspace")
        }
        overlay.query = "plug-remove:"
        if (!overlay.handleKey(backspaceEvent) || overlay.query !== "") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR remove prefix backspace")
        }
        var savedUpdateService = overlay.service
        overlay.service = null
        overlay.query = "plug-upd"
        if (!overlay.handleKey(tabEvent)
            || overlay.query !== "plug-update: "
            || overlay.mode !== "update") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR update completion")
        }
        if (overlay.handleKey(backspaceEvent)
            || overlay.query !== "plug-update: ") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR update space backspace")
        }
        overlay.query = "plug-update:"
        if (!overlay.handleKey(backspaceEvent) || overlay.query !== "") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR update prefix backspace")
        }
        overlay.query = "plug-update:"
        if (!overlay.handleKey(enterEvent)
            || overlay.query !== "plug-update: ") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR typed update command")
        }
        overlay.query = ""
        if (!overlay.handleKey({
              modifiers: Qt.ControlModifier, key: Qt.Key_U
            }) || overlay.query !== "plug-update: ") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR update shortcut")
        }
        overlay.service = savedUpdateService
        overlay.query = "weather:"
        if (overlay.filteredRecords.length !== 0
            || !overlay.handleKey(tabEvent)
            || !overlay.handleKey(enterEvent)
            || overlay.query !== "weather:"
            || overlay.selectedRecord !== null) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR invalid colon dispatch")
        }
        if (overlay.handleKey(backspaceEvent))
          console.error("PLUGIN_CONTROL_LOAD_ERROR backspace ownership")
        var controlEvent = { modifiers: Qt.ControlModifier, key: Qt.Key_W }
        var shiftedControlEvent = {
          modifiers: Qt.ControlModifier | Qt.ShiftModifier, key: Qt.Key_W
        }
        if (!overlay.isControlShortcut(controlEvent, Qt.Key_W)
            || overlay.isControlShortcut(shiftedControlEvent, Qt.Key_W)
            || overlay.isControlShortcut(
              { modifiers: Qt.ShiftModifier, key: Qt.Key_W }, Qt.Key_W)) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR control shortcut modifiers")
        }
        var infoEvent = {
          modifiers: Qt.ControlModifier,
          key: Qt.Key_I
        }
        var shiftInfoEvent = { modifiers: Qt.ShiftModifier, key: Qt.Key_I }
        var shiftedControlInfoEvent = {
          modifiers: Qt.ControlModifier | Qt.ShiftModifier,
          key: Qt.Key_I
        }
        overlay.mode = "browse"
        overlay.filteredRecords = [{
          id: "io.example.docs",
          name: "Docs",
          description: "Browse-only plugin details",
          installable: false,
          installed: false
        }]
        overlay.selectedIndex = 0
        overlay.selectedRecord = null
        if (overlay.handleKey(shiftInfoEvent)
            || overlay.handleKey(shiftedControlInfoEvent)
            || !overlay.handleKey(infoEvent)
            || overlay.pendingOperation !== "browse"
            || overlay.pendingSnapshotId !== ""
            || !overlay.actionDialogReadOnly
            || !overlay.selectedRecord
            || overlay.selectedRecord.id !== "io.example.docs") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR info shortcut")
        }
        if (!overlay.handleKey({ modifiers: 0, key: Qt.Key_Escape }))
          console.error("PLUGIN_CONTROL_LOAD_ERROR info dialog close")
        var savedService = overlay.service
        overlay.service = null
        overlay.transientMessage = "Old message"
        if (!overlay.handleKey({
              modifiers: Qt.ControlModifier, key: Qt.Key_R
            }) || overlay.transientMessage !== "") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR refresh shortcut")
        }
        overlay.service = savedService
        root.serviceObject.lastError = "Old catalog error"
        root.serviceObject.refreshing = true
        if (overlay.rightStatusText !== "Refreshing catalog..."
            || String(overlay.rightStatusColor)
              !== String(overlay.shortcutColor)
            || overlay.rightStatusOpacity !== 1) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR refresh status")
        }
        root.serviceObject.lastError = ""
        root.serviceObject.refreshBaselineTimestamp =
          "2026-08-16T11:00:00Z"
        var refreshedAt = "2026-08-16T12:07:29Z"
        var refreshSnapshot = JSON.stringify({
          ok: true,
          records: [],
          cache: {
            lastRefreshError: "",
            lastSuccessfulRefresh: refreshedAt,
            refreshDurationMs: 42
          }
        })
        if (!root.serviceObject.applySnapshot(refreshSnapshot, 0, true))
          console.error("PLUGIN_CONTROL_LOAD_ERROR refresh snapshot")
        var formattedRefresh = overlay.formatStatusTimestamp(refreshedAt)
        if (formattedRefresh.indexOf("T") >= 0
            || formattedRefresh.indexOf("Z") >= 0
            || !formattedRefresh.match(
              /^\d{2}:\d{2}:\d{2} \(\d{4}-\d{2}-\d{2}\)$/)
            || overlay.rightStatusText !== "Catalog refreshed: "
              + formattedRefresh
            || !root.serviceObject.refreshSuccessVisible
            || root.serviceObject.refreshSuccessDurationMs !== 10000
            || String(overlay.rightStatusColor)
              !== String(overlay.successColor)
            || overlay.rightStatusOpacity !== 1) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR refresh success status")
        }
        root.serviceObject.clearRefreshSuccess()
        if (root.serviceObject.refreshSuccessVisible
            || String(overlay.rightStatusColor) !== String(overlay.foreground)
            || overlay.rightStatusOpacity !== 0.70) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR refresh settled status")
        }
        root.serviceObject.updateCheckBaselineTimestamp =
          "2026-08-16T11:00:00Z"
        var checkedAt = "2026-08-16T12:08:30Z"
        var updateSnapshot = JSON.stringify({
          ok: true,
          records: [],
          updates: {
            lastSuccessfulCheck: checkedAt,
            lastCheckAttempt: checkedAt,
            lastCheckError: "",
            lastCheckNotice: "1 dirty checkout(s)",
            checkDurationMs: 51,
            counts: { available: 0, dirty: 1, failed: 0 }
          }
        })
        if (!root.serviceObject.applySnapshot(updateSnapshot, 0,
              false, true)
            || overlay.leftStatusText.indexOf("Last update: "
              + overlay.formatStatusTimestamp(checkedAt)) !== 0
            || overlay.leftStatusText.indexOf("dirty checkout") < 0
            || !root.serviceObject.updateCheckSuccessVisible
            || root.serviceObject.updateCheckSuccessDurationMs !== 10000
            || String(overlay.leftStatusColor)
              !== String(overlay.successColor)
            || overlay.leftStatusOpacity !== 1) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR update success status")
        }
        root.serviceObject.clearUpdateCheckSuccess()
        if (overlay.leftStatusText !== "Last update: "
              + overlay.formatStatusTimestamp(checkedAt)
            || String(overlay.leftStatusColor) !== String(overlay.foreground)
            || overlay.leftStatusOpacity !== 0.70) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR update settled status")
        }
        overlay.selectedRecord = null
        root.serviceObject.snapshot = { snapshotId: "snapshot-test" }
        overlay.filteredRecords = [{
          id: "io.example.browse",
          name: "Browse",
          installable: false,
          installed: false
        }]
        overlay.selectedIndex = 0
        if (!overlay.handleKey(enterEvent)
            || !overlay.selectedRecord
            || overlay.selectedRecord.id !== "io.example.browse"
            || overlay.actionDialogReadOnly
            || overlay.pendingSnapshotId !== "snapshot-test") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR shared browse dialog")
        }
        overlay.handleKey({ modifiers: 0, key: Qt.Key_Escape })
        overlay.selectedRecord = null
        overlay.spaceActivatesSelection = false
        if (overlay.handleKey({ modifiers: 0, key: Qt.Key_Space })
            || overlay.selectedRecord !== null) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR searchable space")
        }
        overlay.spaceActivatesSelection = true
        if (!overlay.handleKey({ modifiers: 0, key: Qt.Key_Space })
            || !overlay.selectedRecord
            || overlay.selectedRecord.id !== "io.example.browse"
            || overlay.actionDialogReadOnly) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR shared browse space")
        }
        overlay.handleKey({ modifiers: 0, key: Qt.Key_Escape })

        overlay.filteredRecords = [{
          id: "io.example.installable",
          name: "Installable",
          installable: true,
          installed: false
        }]
        overlay.selectedIndex = 0
        if (!overlay.handleKey(enterEvent)
            || overlay.pendingOperation !== "browse"
            || overlay.pendingSnapshotId !== "snapshot-test"
            || overlay.actionDialogReadOnly
            || !overlay.selectedRecord
            || overlay.selectedRecord.id !== "io.example.installable") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR actionable enter")
        }
        if (!overlay.handleKey({ modifiers: 0, key: Qt.Key_Escape }))
          console.error("PLUGIN_CONTROL_LOAD_ERROR action dialog close")
        overlay.mode = "browse"
        overlay.selectedRecord = null
        overlay.filteredRecords = [{ commandCompletion: "plug-add: " }]
        overlay.selectedIndex = 0
        if (!overlay.handleKey(infoEvent) || overlay.selectedRecord !== null)
          console.error("PLUGIN_CONTROL_LOAD_ERROR command info boundary")
        overlay.loadStatusColors(
          'yellow = "#A1B2C3"\ngreen = "#4D5E6F"')
        if (String(overlay.shortcutColor).toLowerCase() !== "#a1b2c3"
            || String(overlay.successColor).toLowerCase() !== "#4d5e6f") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR theme status colors")
        }
        overlay.loadStatusColors("")
        if (String(overlay.shortcutColor).toLowerCase() !== "#e5c07b"
            || String(overlay.successColor).toLowerCase() !== "#98c379") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR status color fallback")
        }
        overlay.filteredRecords = [{
          id: "io.example.weather",
          repository: "https://github.com/example/weather",
          source: "local",
          marketplaceListed: true
        }]
        overlay.selectedIndex = 0
        if (overlay.marketplaceShortcutUrl()
              !== "https://omarchyplugins.com/plugin.html?id=io.example.weather"
            || overlay.githubShortcutUrl()
              !== "https://github.com/example/weather") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR contextual links")
        }
        overlay.filteredRecords = [{ commandCompletion: "plug-add: " }]
        if (overlay.marketplaceShortcutUrl() !== "https://omarchyplugins.com/"
            || overlay.githubShortcutUrl()
              !== "https://github.com/HANCORE-linux/omarchy-plugin-marketplace") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR global links")
        }
        overlay.open('{"settings":true}')
        if (!overlay.settingsMenuOpen || !overlay.opened
            || !overlay.surfaceVisible || overlay.mode !== "settings"
            || overlay.filteredRecords.length !== 4 || overlay.query !== ""
            || overlay.paletteChromeVisible
            || overlay.activeHeaderHeight !== 0
            || overlay.activeFooterHeight !== 0
            || overlay.statusHeight !== 0
            || overlay.filteredRecords[0].name !== "Plugin settings"
            || overlay.filteredRecords[0].settingsAction !== "plugin"
            || overlay.filteredRecords[1].name !== "Keybindings"
            || overlay.filteredRecords[1].settingsAction !== "keybindings"
            || overlay.filteredRecords[2].name
              !== "Cleanly remove Plugin Control and user data"
            || overlay.filteredRecords[2].settingsAction !== "remove-self"
            || overlay.filteredRecords[2].separatorBefore !== true
            || overlay.filteredRecords[3].name !== "Cancel / Back"
            || overlay.filteredRecords[3].settingsAction !== "cancel") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR settings payload")
        }
        var plainJ = { modifiers: Qt.NoModifier, key: Qt.Key_J, text: "j" }
        var plainK = { modifiers: Qt.NoModifier, key: Qt.Key_K, text: "k" }
        var plainA = { modifiers: Qt.NoModifier, key: Qt.Key_A, text: "a" }
        if (!overlay.handleKey(plainJ) || overlay.selectedIndex !== 1
            || !overlay.handleKey({ modifiers: 0, key: Qt.Key_Down })
            || overlay.selectedIndex !== 2
            || !overlay.handleKey(plainK) || overlay.selectedIndex !== 1
            || !overlay.handleKey({ modifiers: 0, key: Qt.Key_Up })
            || overlay.selectedIndex !== 0
            || !overlay.handleKey(plainA) || overlay.query !== ""
            || overlay.selectedIndex !== 0) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR settings navigation")
        }
        overlay.selectedIndex = 3
        if (!overlay.handleKey(enterEvent) || overlay.settingsMenuOpen
            || !overlay.opened || !overlay.surfaceVisible
            || !overlay.paletteChromeVisible
            || overlay.activeHeaderHeight !== overlay.headerHeight
            || overlay.activeFooterHeight !== overlay.footerHeight) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR settings cancel back")
        }
        overlay.showSettingsMenu()
        if (!overlay.handleKey({ modifiers: 0, key: Qt.Key_Escape })
            || overlay.settingsMenuOpen || !overlay.opened) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR settings escape back")
        }
        console.log("PLUGIN_CONTROL_INTERACTION_OK palette interactions")
        root.serviceObject.acceptActionStart('{"error":"Install failed."}', 1)
        if (root.serviceObject.actionNoticeDurationMs !== 10000
            || root.serviceObject.actionState.acknowledged !== false
            || overlay.leftStatusText !== "Install failed.") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR timed action notice")
        }
        root.serviceObject.acknowledgeAction()
        if (root.serviceObject.actionState.acknowledged !== true
            || overlay.leftStatusText === "Install failed.") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR action notice dismissal")
        }
        root.serviceObject.acceptStatus('{"ok":false,"running":false,'
          + '"acknowledged":false,"actionId":"persisted-failure",'
          + '"message":"Persisted failure."}')
        if (root.serviceObject.actionState.acknowledged !== false
            || overlay.leftStatusText !== "Persisted failure.") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR persisted action notice")
        }
        root.serviceObject.acknowledgeAction()
      }
      var dialog = root.loadEntry("ActionDialog.qml", "dialog")
      if (dialog) {
        dialog.canceled.connect(function() { root.dialogCanceledCount++ })
        dialog.actionRequested.connect(function(operation) {
          root.dialogConfirmedCount++
          root.lastDialogOperation = operation
        })
        dialog.plugin = {
          id: "io.example.info",
          description: "Plugin information",
          listingValidatedCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        }
        dialog.readOnly = true
        if (dialog.reviewedCommit
              !== "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            || dialog.actions.length !== 1
            || dialog.actions[0].label !== "Close"
            || dialog.operationText !== "No system change") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR reviewed commit")
        }
        dialog.openDialog()
        dialog.handleKey({ modifiers: 0, key: Qt.Key_Return })
        dialog.closeDialog()

        dialog.readOnly = false
        dialog.plugin = {
          id: "io.example.enabled",
          name: "Enabled",
          installed: true,
          enabled: true,
          canDisable: true,
          removable: true,
          gitManaged: true,
          updateStatus: "unknown",
          marketplaceListed: true,
          metricsAvailable: true,
          verificationStatus: "verified",
          stars: 9,
          views: 10,
          copies: 11,
          hearts: 12,
          tags: ["shell"]
        }
        if (dialog.actions.length !== 4
            || dialog.actions[0].label !== "Cancel"
            || dialog.actions[1].label !== "Update"
            || dialog.actions[2].label !== "Disable"
            || dialog.actions[3].label !== "Remove"
            || !dialog.listedUserPlugin || !dialog.metricsAvailable
            || dialog.verificationHelp.indexOf("not a security audit") < 0) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR shared action choices")
        }
        dialog.openDialog()
        if (dialog.selectedChoice !== 0)
          console.error("PLUGIN_CONTROL_LOAD_ERROR safe action default")
        dialog.handleKey({ modifiers: 0, key: Qt.Key_Right })
        if (dialog.selectedChoice !== 1
            || dialog.operationText
              !== "omarchy plugin update io.example.enabled --yes") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR update action selection")
        }
        dialog.handleKey({ modifiers: 0, key: Qt.Key_Return })
        if (root.dialogCanceledCount !== 1
            || root.dialogConfirmedCount !== 1
            || root.lastDialogOperation !== "update") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR shared action dispatch")
        }

        var manualReason = "Manually copied/installed plugin. "
          + "No Git repository to update."
        dialog.plugin = {
          id: "io.example.manual",
          installed: true,
          removable: true,
          updateStatus: "manual",
          updateReason: manualReason
        }
        dialog.openDialog()
        dialog.handleKey({ modifiers: 0, key: Qt.Key_Right })
        if (dialog.selectedChoice !== 1 || dialog.helpText !== ""
            || !dialog.helpDelayRunning) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR delayed update help")
        }
        dialog.handleKey({ modifiers: 0, key: Qt.Key_Space })
        if (dialog.helpText !== manualReason
            || root.dialogConfirmedCount !== 1) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR immediate update help")
        }
        dialog.handleKey({ modifiers: 0, key: Qt.Key_Right })
        if (dialog.helpText !== "" || dialog.selectedChoice !== 2) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR update help dismissal")
        }
        dialog.closeDialog()

        dialog.plugin = {
          id: "omarchy.bar",
          builtIn: true,
          fullBar: true,
          enabled: true
        }
        if (dialog.actions.length !== 1
            || dialog.actions[0].label !== "Cancel") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR active full bar actions")
        }
        dialog.plugin = {
          id: "third.bar",
          installed: true,
          fullBar: true,
          enabled: false
        }
        if (dialog.actions.length !== 2
            || dialog.actions[1].label !== "Enable") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR inactive full bar actions")
        }
      }
      var removalDialog = root.loadEntry(
        "SelfRemovalDialog.qml", "self-removal-dialog")
      if (removalDialog) {
        removalDialog.canceled.connect(function() {
          root.removalCanceledCount++
        })
        removalDialog.removeRequested.connect(function(deleteUserData) {
          if (deleteUserData) root.removalPurgeCount++
          else root.removalPreserveCount++
        })
        removalDialog.openDialog()
        if (removalDialog.selectedChoice !== 2)
          console.error("PLUGIN_CONTROL_LOAD_ERROR safe removal default")
        removalDialog.handleKey({ modifiers: 0, key: Qt.Key_Return })
        removalDialog.closeDialog()
        removalDialog.openDialog()
        removalDialog.handleKey({ modifiers: 0, key: Qt.Key_Up })
        removalDialog.handleKey({ modifiers: 0, key: Qt.Key_Return })
        removalDialog.closeDialog()
        removalDialog.openDialog()
        removalDialog.handleKey({ modifiers: 0, key: Qt.Key_Down })
        removalDialog.handleKey({ modifiers: 0, key: Qt.Key_Return })
        if (root.removalCanceledCount !== 1
            || root.removalPurgeCount !== 1
            || root.removalPreserveCount !== 1) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR self removal choices")
        }
      }
      var barWidget = root.loadEntry("PluginControlBar.qml", "bar-widget")
      if (barWidget) {
        barWidget.bar = mockBar
        root.serviceObject.actionState = {
          ok: false,
          acknowledged: false,
          message: "Install failed."
        }
        if (!barWidget.actionFailed)
          console.error("PLUGIN_CONTROL_LOAD_ERROR bar failure state")
        root.serviceObject.acknowledgeAction()
        if (barWidget.actionFailed)
          console.error("PLUGIN_CONTROL_LOAD_ERROR bar failure dismissal")
        barWidget.settings = { trayIconHidden: true }
        if (barWidget.visible || barWidget.implicitWidth !== 0
            || barWidget.implicitHeight !== 0)
          console.error("PLUGIN_CONTROL_LOAD_ERROR hidden tray icon")
        barWidget.settings = { trayIconHidden: false }
        if (!barWidget.visible)
          console.error("PLUGIN_CONTROL_LOAD_ERROR visible tray icon")
        barWidget.openPalette()
        if (mockShell.lastToggleId
            !== "io.github.ilyazar.plugin-control"
            || mockShell.lastTogglePayload !== "{}") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR bar-widget command")
        }
        barWidget.settingsMenuOpen = true
        barWidget.close()
        if (barWidget.settingsMenuOpen)
          console.error("PLUGIN_CONTROL_LOAD_ERROR bar settings menu")
        barWidget.openSettings()
        if (mockShell.lastTogglePayload !== '{"settings":true}')
          console.error("PLUGIN_CONTROL_LOAD_ERROR bar settings payload")
      }
      mockPluginRegistry.settingCalls = 0
      root.entryChecksComplete = true
    }
  }

  Timer {
    interval: 50
    running: root.entryChecksComplete
    repeat: true
    onTriggered: {
      root.watcherWaitAttempts++
      if (!root.serviceObject
          || !root.serviceObject.channelConfigWatchReady) {
        if (root.watcherWaitAttempts >= 100) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR fresh install watcher")
          stop()
          Qt.callLater(Qt.quit)
        }
        return
      }
      if (!root.watcherSaveStarted) {
        testConfigFile.reload()
        testConfigFile.waitForJob()
        var current = testConfigFile.text()
        if (current.indexOf("tray-icon-hidden: false") < 0) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR fresh config contents")
          stop()
          Qt.callLater(Qt.quit)
          return
        }
        root.watcherSaveStarted = true
        testConfigFile.setText(current.replace(
          "tray-icon-hidden: false", "tray-icon-hidden: true"))
        return
      }
      if (mockPluginRegistry.settingCalls > 0) {
        if (mockPluginRegistry.lastSettingKey !== "trayIconHidden"
            || mockPluginRegistry.lastSettingValue !== true) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR watched tray setting")
        } else {
          console.log("PLUGIN_CONTROL_WATCH_OK fresh install save")
        }
        stop()
        Qt.callLater(Qt.quit)
      } else if (root.watcherWaitAttempts >= 100) {
        console.error("PLUGIN_CONTROL_LOAD_ERROR watched config save")
        stop()
        Qt.callLater(Qt.quit)
      }
    }
  }
}
