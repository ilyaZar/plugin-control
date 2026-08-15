import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property string sourceDir:
    Quickshell.env("PLUGIN_CONTROL_SOURCE_DIR")
  property var createdObjects: []
  property var serviceObject: null
  property int dialogCanceledCount: 0
  property int dialogConfirmedCount: 0

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
        mockPluginRegistry.settingCalls = 0
        var hiddenSnapshot = JSON.stringify({
          ok: true,
          records: [],
          config: { settings: { "tray-icon-hidden": true } }
        })
        root.serviceObject.applySnapshot(hiddenSnapshot, 0)
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
        overlay.query = "plug-in"
        if (overlay.mode !== "command"
            || overlay.filteredRecords.length !== 1
            || overlay.selectedRecord !== null) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR install completion stage")
        }
        var tabEvent = { modifiers: 0, key: Qt.Key_Tab }
        var backspaceEvent = { modifiers: 0, key: Qt.Key_Backspace }
        var installPrefix = "plug-install:"
        if (!overlay.isCompletedCommandPrefix(installPrefix,
              installPrefix.length, installPrefix.length,
              installPrefix.length)
            || overlay.isCompletedCommandPrefix(installPrefix,
              installPrefix.length - 1, installPrefix.length - 1,
              installPrefix.length - 1)
            || overlay.isCompletedCommandPrefix(installPrefix,
              installPrefix.length, 0, installPrefix.length)
            || overlay.isCompletedCommandPrefix("PLUG-INSTALL:",
              installPrefix.length, installPrefix.length,
              installPrefix.length)) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR backspace boundary")
        }
        if (!overlay.handleKey(tabEvent))
          console.error("PLUGIN_CONTROL_LOAD_ERROR tab dispatch")
        if (overlay.query !== "plug-install: " || overlay.mode !== "install"
            || overlay.selectedRecord !== null) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR install completion")
        }
        if (overlay.handleKey(backspaceEvent)
            || overlay.query !== "plug-install: ") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR completion space backspace")
        }
        overlay.query = "plug-install:"
        if (!overlay.handleKey(backspaceEvent) || overlay.query !== "") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR install prefix backspace")
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
        var controlEvent = { modifiers: Qt.ControlModifier, key: Qt.Key_O }
        var shiftedControlEvent = {
          modifiers: Qt.ControlModifier | Qt.ShiftModifier, key: Qt.Key_O
        }
        if (!overlay.isControlShortcut(controlEvent, Qt.Key_O)
            || overlay.isControlShortcut(shiftedControlEvent, Qt.Key_O)
            || overlay.isControlShortcut(
              { modifiers: Qt.ShiftModifier, key: Qt.Key_O }, Qt.Key_O)) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR control shortcut modifiers")
        }
        var infoEvent = {
          modifiers: Qt.ControlModifier,
          key: Qt.Key_D
        }
        var shiftInfoEvent = { modifiers: Qt.ShiftModifier, key: Qt.Key_D }
        var shiftedControlInfoEvent = {
          modifiers: Qt.ControlModifier | Qt.ShiftModifier,
          key: Qt.Key_D
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
        if (overlay.statusText !== "Refreshing catalog...")
          console.error("PLUGIN_CONTROL_LOAD_ERROR refresh status")
        root.serviceObject.refreshing = false
        root.serviceObject.lastError = ""
        root.serviceObject.lastSuccessfulRefresh = "just now"
        if (overlay.statusText.indexOf("Refreshing catalog...") >= 0)
          console.error("PLUGIN_CONTROL_LOAD_ERROR refresh status completion")
        overlay.selectedRecord = null
        if (!overlay.handleKey(enterEvent) || overlay.selectedRecord !== null)
          console.error("PLUGIN_CONTROL_LOAD_ERROR browse enter mutated")

        root.serviceObject.snapshot = { snapshotId: "snapshot-test" }
        overlay.filteredRecords = [{
          id: "io.example.installable",
          name: "Installable",
          installable: true,
          installed: false
        }]
        overlay.selectedIndex = 0
        if (!overlay.handleKey(enterEvent)
            || overlay.pendingOperation !== "install"
            || overlay.pendingSnapshotId !== "snapshot-test"
            || !overlay.selectedRecord
            || overlay.selectedRecord.id !== "io.example.installable") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR actionable enter")
        }
        if (!overlay.handleKey({ modifiers: 0, key: Qt.Key_Escape }))
          console.error("PLUGIN_CONTROL_LOAD_ERROR action dialog close")
        overlay.selectedRecord = null
        overlay.filteredRecords = [{ commandCompletion: "plug-install: " }]
        overlay.selectedIndex = 0
        if (!overlay.handleKey(infoEvent) || overlay.selectedRecord !== null)
          console.error("PLUGIN_CONTROL_LOAD_ERROR command info boundary")
        overlay.loadShortcutColor('yellow = "#A1B2C3"')
        if (String(overlay.shortcutColor).toLowerCase() !== "#a1b2c3")
          console.error("PLUGIN_CONTROL_LOAD_ERROR theme yellow")
        overlay.loadShortcutColor("")
        if (String(overlay.shortcutColor).toLowerCase() !== "#e5c07b")
          console.error("PLUGIN_CONTROL_LOAD_ERROR yellow fallback")
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
        overlay.filteredRecords = [{ commandCompletion: "plug-install: " }]
        if (overlay.marketplaceShortcutUrl() !== "https://omarchyplugins.com/"
            || overlay.githubShortcutUrl()
              !== "https://github.com/HANCORE-linux/omarchy-plugin-marketplace") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR global links")
        }
        overlay.open('{"settings":true}')
        if (!overlay.settingsMenuOpen || !overlay.opened
            || !overlay.surfaceVisible || overlay.mode !== "settings"
            || overlay.filteredRecords.length !== 3 || overlay.query !== ""
            || overlay.paletteChromeVisible
            || overlay.activeHeaderHeight !== 0
            || overlay.activeFooterHeight !== 0
            || overlay.statusHeight !== 0
            || overlay.filteredRecords[0].name !== "Plugin settings"
            || overlay.filteredRecords[0].settingsAction !== "plugin"
            || overlay.filteredRecords[1].name !== "Keybindings"
            || overlay.filteredRecords[1].settingsAction !== "keybindings"
            || overlay.filteredRecords[2].name !== "Cancel / Back"
            || overlay.filteredRecords[2].settingsAction !== "cancel") {
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
        overlay.selectedIndex = 2
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
        root.serviceObject.records = []
        root.serviceObject.snapshot = { snapshotId: "self-removal-snapshot" }
        overlay.open('{"removeSelf":true}')
        if (!overlay.selfRemovalRequested || overlay.selectedRecord !== null) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR pending self removal")
        }
        root.serviceObject.records = [{
          id: "io.github.ilyazar.plugin-control",
          name: "Plugin Control",
          installed: true,
          removable: true,
          dirty: false
        }]
        overlay.tryOpenSelfRemoval()
        if (overlay.selfRemovalRequested
            || overlay.pendingOperation !== "remove"
            || overlay.pendingSnapshotId !== "self-removal-snapshot"
            || !overlay.selectedRecord
            || overlay.selectedRecord.id
              !== "io.github.ilyazar.plugin-control") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR self removal payload")
        }
        if (!overlay.handleKey({ modifiers: 0, key: Qt.Key_Escape }))
          console.error("PLUGIN_CONTROL_LOAD_ERROR self removal cancel")
        console.log("PLUGIN_CONTROL_INTERACTION_OK palette interactions")
        root.serviceObject.acceptActionStart('{"error":"Install failed."}', 1)
        if (root.serviceObject.actionNoticeDurationMs !== 10000
            || root.serviceObject.actionState.acknowledged !== false
            || overlay.statusText !== "Install failed.") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR timed action notice")
        }
        root.serviceObject.acknowledgeAction()
        if (root.serviceObject.actionState.acknowledged !== true
            || overlay.statusText === "Install failed.") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR action notice dismissal")
        }
        root.serviceObject.acceptStatus('{"ok":false,"running":false,'
          + '"acknowledged":false,"actionId":"persisted-failure",'
          + '"message":"Persisted failure."}')
        if (root.serviceObject.actionState.acknowledged !== false
            || overlay.statusText !== "Persisted failure.") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR persisted action notice")
        }
        root.serviceObject.acknowledgeAction()
      }
      var dialog = root.loadEntry("ActionDialog.qml", "dialog")
      if (dialog) {
        dialog.plugin = {
          id: "io.example.info",
          description: "Plugin information",
          listingValidatedCommit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        }
        dialog.operation = "browse"
        if (dialog.reviewedCommit
            !== "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR reviewed commit")
        }
        if (dialog.mutating || dialog.canConfirm
            || dialog.operationText !== "No system change")
          console.error("PLUGIN_CONTROL_LOAD_ERROR info dialog boundary")
        dialog.selfId = "io.github.ilyazar.plugin-control"
        dialog.plugin = {
          id: "io.github.ilyazar.plugin-control",
          name: "Plugin Control",
          dirty: false
        }
        dialog.operation = "remove"
        dialog.canceled.connect(function() { root.dialogCanceledCount++ })
        dialog.confirmed.connect(function() { root.dialogConfirmedCount++ })
        if (!dialog.selfRemoval
            || dialog.title !== "Remove Plugin Control itself?"
            || dialog.cancelLabel !== "No"
            || dialog.confirmLabel !== "Yes, remove") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR self removal warning")
        }
        dialog.openDialog()
        dialog.handleKey({ modifiers: 0, key: Qt.Key_Return })
        dialog.closeDialog()
        dialog.openDialog()
        dialog.handleKey({ modifiers: 0, key: Qt.Key_Right })
        dialog.handleKey({ modifiers: 0, key: Qt.Key_Return })
        if (root.dialogCanceledCount !== 1
            || root.dialogConfirmedCount !== 1) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR self removal choices")
        }
        dialog.plugin = {
          id: "io.github.ilyazar.plugin-control",
          dirty: true
        }
        if (dialog.canConfirm)
          console.error("PLUGIN_CONTROL_LOAD_ERROR dirty self removal")
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
        barWidget.settingsMenuOpen = true
        barWidget.removePluginControl()
        if (barWidget.settingsMenuOpen
            || mockShell.lastSummonId
              !== "io.github.ilyazar.plugin-control"
            || mockShell.lastSummonPayload !== '{"removeSelf":true}') {
          console.error("PLUGIN_CONTROL_LOAD_ERROR bar removal payload")
        }
      }
      Qt.callLater(Qt.quit)
    }
  }
}
