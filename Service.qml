import QtQuick
import Quickshell
import Quickshell.Io
import "CatalogModel.js" as CatalogModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  property var records: []
  property var snapshot: ({})
  property var actionState: ({
    ok: true,
    running: false,
    acknowledged: true,
    message: "No action has run."
  })
  property bool ready: false
  property bool refreshing: false
  property bool actionStarting: false
  property bool animationsEnabled: true
  property string lastError: ""
  property string lastRefreshError: ""
  property string lastSuccessfulRefresh: ""
  property real serviceReadyMs: -1
  property real lastOpenRequestMs: -1
  property real lastFocusReadyMs: -1
  property real lastFilterMs: -1
  property real lastRefreshDurationMs: 0
  property int catalogRecordCount: records.length
  property double componentStartedAt: Date.now()
  property double latestOpenStartedAt: 0
  property bool startupRefreshPending: true

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
    || homeDir + "/.config"
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDir
    ? sourceDir + "/bin/plugin-control" : ""
  readonly property string channelConfigPath: configHome
    + "/omarchy/plugin-control/channels.yaml"
  readonly property bool actionRunning: actionStarting
    || (actionState && actionState.running === true)

  signal actionFinished(var state)

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "")) } catch (error) { return fallback }
  }

  function applyRecords(values) {
    records = CatalogModel.prepareRecords(values)
    catalogRecordCount = records.length
    if (!ready && records.length > 0) {
      ready = true
      serviceReadyMs = Date.now() - componentStartedAt
    }
  }

  function applyBootstrap(raw) {
    var parsed = parseJson(raw, {})
    if (!parsed || !Array.isArray(parsed.plugins)) return
    if (records.length === 0) applyRecords(parsed.plugins)
  }

  function applySnapshot(raw, exitCode) {
    var parsed = parseJson(raw, null)
    refreshing = false
    if (!parsed || parsed.ok !== true || !Array.isArray(parsed.records)) {
      if (parsed && parsed.error) lastError = String(parsed.error)
      else if (exitCode !== 0) lastError = "Catalog helper failed."
      return false
    }

    snapshot = parsed
    applyRecords(parsed.records)
    lastRefreshError = parsed.cache
      ? String(parsed.cache.lastRefreshError || "") : ""
    lastSuccessfulRefresh = parsed.cache
      ? String(parsed.cache.lastSuccessfulRefresh || "") : ""
    lastRefreshDurationMs = parsed.cache
      ? Number(parsed.cache.refreshDurationMs || 0) : 0
    lastError = ""
    return true
  }

  function loadCached() {
    if (!helperPath || cachedProcess.running) return
    cachedProcess.output = ""
    cachedProcess.command = [helperPath, "cached", sourceDir]
    cachedProcess.running = true
  }

  function requestRefresh(force) {
    if (!helperPath) return
    if (refreshProcess.running) {
      refreshProcess.forceQueued = refreshProcess.forceQueued || force === true
      return
    }
    refreshing = true
    refreshProcess.output = ""
    var command = [helperPath, "refresh", sourceDir]
    if (force === true) command.push("--force")
    refreshProcess.command = command
    refreshProcess.running = true
  }

  function requestStatus() {
    if (!helperPath || statusProcess.running) return
    statusProcess.output = ""
    statusProcess.command = [helperPath, "status"]
    statusProcess.running = true
  }

  function acceptStatus(raw) {
    var previousRunning = actionState && actionState.running === true
    var parsed = parseJson(raw, null)
    if (!parsed || typeof parsed !== "object") return
    actionState = parsed
    if (previousRunning && parsed.running !== true) {
      loadCached()
      actionFinished(parsed)
    }
  }

  function startAction(operation, pluginId, snapshotId, executionMode) {
    if (!helperPath || actionRunning || actionProcess.running) return false
    if (["install", "remove", "enable", "disable", "add-bar"]
        .indexOf(String(operation)) < 0) return false
    if (!String(pluginId) || !String(snapshotId)) return false
    if (["background", "terminal"].indexOf(String(executionMode)) < 0)
      return false
    if (executionMode === "terminal" && operation !== "install") return false
    actionStarting = true
    actionProcess.output = ""
    actionProcess.command = [helperPath, "action", sourceDir,
      String(operation), String(pluginId), String(snapshotId),
      String(executionMode)]
    actionProcess.running = true
    return true
  }

  function acceptActionStart(raw, exitCode) {
    actionStarting = false
    var parsed = parseJson(raw, null)
    if (!parsed || parsed.ok !== true || exitCode !== 0) {
      actionState = {
        ok: false,
        running: false,
        acknowledged: false,
        message: parsed && parsed.error
          ? String(parsed.error) : "Could not start the plugin action."
      }
      actionFinished(actionState)
      return
    }
    actionState = {
      ok: true,
      running: true,
      acknowledged: false,
      actionId: String(parsed.actionId || ""),
      message: "Working..."
    }
    actionPoll.restart()
  }

  function acknowledgeAction() {
    var actionId = String(actionState && actionState.actionId || "")
    if (!helperPath || !actionId) return
    Quickshell.execDetached([helperPath, "ack", actionId])
    var copy = ({})
    for (var key in actionState) copy[key] = actionState[key]
    copy.acknowledged = true
    actionState = copy
  }

  function recordOpenRequest() {
    latestOpenStartedAt = Date.now()
    lastOpenRequestMs = 0
  }

  function recordSurfaceVisible() {
    if (latestOpenStartedAt > 0)
      lastOpenRequestMs = Date.now() - latestOpenStartedAt
  }

  function recordFocusReady() {
    if (latestOpenStartedAt > 0)
      lastFocusReadyMs = Date.now() - latestOpenStartedAt
  }

  function recordFilterDuration(durationMs) {
    lastFilterMs = Number(durationMs)
  }

  function cacheAgeSeconds() {
    var refreshed = Date.parse(lastSuccessfulRefresh)
    if (!isFinite(refreshed)) return -1
    return Math.max(0, Math.floor((Date.now() - refreshed) / 1000))
  }

  FileView {
    path: root.sourceDir ? root.sourceDir + "/bootstrap/catalog.json" : ""
    printErrors: false
    onLoaded: root.applyBootstrap(text())
  }

  FileView {
    path: root.channelConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: configRefreshDebounce.restart()
  }

  Process {
    id: cachedProcess
    property string output: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: cachedProcess.output = text
    }
    onExited: function(exitCode) {
      root.applySnapshot(output, exitCode)
      Qt.callLater(root.requestStatus)
      if (root.startupRefreshPending) {
        root.startupRefreshPending = false
        Qt.callLater(function() { root.requestRefresh(false) })
      }
    }
  }

  Process {
    id: refreshProcess
    property string output: ""
    property bool forceQueued: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: refreshProcess.output = text
    }
    onExited: function(exitCode) {
      root.applySnapshot(output, exitCode)
      if (forceQueued) {
        forceQueued = false
        Qt.callLater(function() { root.requestRefresh(true) })
      }
    }
  }

  Process {
    id: statusProcess
    property string output: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: statusProcess.output = text
    }
    onExited: root.acceptStatus(output)
  }

  Process {
    id: actionProcess
    property string output: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: actionProcess.output = text
    }
    onExited: function(exitCode) {
      root.acceptActionStart(output, exitCode)
    }
  }

  Process {
    id: animationProbe
    command: ["hyprctl", "-j", "getoption", "animations:enabled"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.parseJson(text, {})
        root.animationsEnabled = parsed.int === undefined
          ? true : Number(parsed.int) !== 0
      }
    }
  }

  Timer {
    id: configRefreshDebounce
    interval: 300
    repeat: false
    onTriggered: root.requestRefresh(true)
  }

  Timer {
    id: actionPoll
    interval: 500
    repeat: true
    running: root.actionRunning
    onTriggered: root.requestStatus()
  }

  Component.onCompleted: {
    animationProbe.running = true
    Qt.callLater(loadCached)
  }
}
