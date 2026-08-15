import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property string sourceDir:
    Quickshell.env("PLUGIN_CONTROL_SOURCE_DIR")
  property var createdObjects: []
  property var serviceObject: null

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
    function hide(pluginId) { return true }
    function isPluginOpen(pluginId) { return false }
    function serviceFor(pluginId) { return root.serviceObject }
    function toggle(pluginId, payloadJson) {
      lastToggleId = pluginId
      lastTogglePayload = payloadJson
    }
  }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      root.serviceObject = root.loadEntry("Service.qml", "service")
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
        var shiftEvent = { modifiers: Qt.ShiftModifier, key: Qt.Key_O }
        var contextEvent = {
          modifiers: Qt.ControlModifier | Qt.ShiftModifier,
          key: Qt.Key_O
        }
        if (overlay.isContextShortcut(shiftEvent, Qt.Key_O)
            || !overlay.isContextShortcut(contextEvent, Qt.Key_O)) {
          console.error("PLUGIN_CONTROL_LOAD_ERROR context shortcut modifiers")
        }
        var infoEvent = {
          modifiers: Qt.ControlModifier | Qt.ShiftModifier,
          key: Qt.Key_I
        }
        var shiftInfoEvent = { modifiers: Qt.ShiftModifier, key: Qt.Key_I }
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
            || !overlay.handleKey(infoEvent)
            || overlay.pendingOperation !== "browse"
            || overlay.pendingSnapshotId !== ""
            || !overlay.selectedRecord
            || overlay.selectedRecord.id !== "io.example.docs") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR info shortcut")
        }
        if (!overlay.handleKey({ modifiers: 0, key: Qt.Key_Escape }))
          console.error("PLUGIN_CONTROL_LOAD_ERROR info dialog close")
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
            || overlay.filteredRecords.length !== 3 || overlay.query !== "") {
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
            || !overlay.opened || !overlay.surfaceVisible) {
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
      Qt.callLater(Qt.quit)
    }
  }
}
