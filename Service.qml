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
  property string refreshBaselineTimestamp: ""
  property bool refreshSuccessVisible: false
  property real serviceReadyMs: -1
  property real lastOpenRequestMs: -1
  property real lastFocusReadyMs: -1
  property real lastFilterMs: -1
  property real lastRefreshDurationMs: 0
  property int catalogRecordCount: records.length
  property double componentStartedAt: Date.now()
  property double latestOpenStartedAt: 0
  property int configChangeRevision: 0
  property bool configSyncQueued: false
  property bool initialLoadStarted: false
  property bool channelConfigWatchReady: false
  readonly property int actionNoticeDurationMs: 10000
  readonly property int refreshSuccessDurationMs: 10000

  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME")
    || homeDir + "/.config"
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDir
    ? sourceDir + "/bin/plugin-control" : ""
  readonly property string channelConfigPath: configHome
    + "/omarchy/ilyazar.plugin-control/channels.yaml"
  readonly property bool actionRunning: actionStarting
    || (actionState && actionState.running === true)
  readonly property string moduleName: "io.github.ilyazar.plugin-control"

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

  function applyConfigStatus(raw, exitCode, revision) {
    if (revision !== configChangeRevision || exitCode !== 0) return false
    var parsed = parseJson(raw, null)
    if (!parsed || parsed.ok !== true || parsed.usingLastGood === true
        || !parsed.config || parsed.config.version !== 2) return false
    var settings = parsed.config.settings
    var value = settings ? settings["tray-icon-hidden"] : undefined
    if (typeof value !== "boolean") return false
    if (!pluginRegistry
        || typeof pluginRegistry.setBarWidget !== "function") return false
    var error = String(pluginRegistry.setBarWidget(
      moduleName, "trayIconHidden", value, {}) || "")
    if (error) {
      lastError = "Could not apply tray icon visibility."
      return false
    }
    return true
  }

  function requestConfigSync() {
    if (!helperPath) return
    if (configSyncProcess.running) {
      configSyncQueued = true
      return
    }
    configSyncQueued = false
    configSyncProcess.output = ""
    configSyncProcess.revision = configChangeRevision
    configSyncProcess.command = [helperPath, "config-status", sourceDir]
    configSyncProcess.running = true
  }

  function configProblemNotice(raw) {
    var parsed = parseJson(raw, null)
    if (!parsed || parsed.ok !== false) return ""
    var field = String(parsed.field || "configuration")
    var actual = String(parsed.actual || "")
    var expected = String(parsed.expected || "")
    var detail = String(parsed.error || "Invalid Plugin Control settings.")
    if (expected) {
      detail = actual
        ? actual + " is not admissible for " + field
          + ". Set it to " + expected + "."
        : field + " is not admissible. Use " + expected + "."
    }
    var fallback = parsed.fallback === "defaults"
      ? "Using shipped defaults."
      : (parsed.fallback === "last-good"
        ? "Keeping the last valid settings."
        : "Fix the file before it can be used.")
    return (detail + " " + fallback).slice(0, 480)
  }

  function notifyConfigProblem(raw, revision) {
    if (revision !== configChangeRevision) return false
    var message = configProblemNotice(raw)
    if (!message) return false
    Quickshell.execDetached(["omarchy-notification-send", "-u", "normal",
      "Plugin Control settings", message])
    return true
  }

  function clearRefreshSuccess() {
    refreshSuccessTimer.stop()
    refreshSuccessVisible = false
  }

  function applySnapshot(raw, exitCode, refreshResult) {
    var parsed = parseJson(raw, null)
    if (refreshResult === true) refreshing = false
    if (!parsed || parsed.ok !== true || !Array.isArray(parsed.records)) {
      if (refreshResult === true) clearRefreshSuccess()
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
    if (refreshResult === true) {
      clearRefreshSuccess()
      if (exitCode === 0 && !lastRefreshError && lastSuccessfulRefresh
          && lastSuccessfulRefresh !== refreshBaselineTimestamp) {
        refreshSuccessVisible = true
        refreshSuccessTimer.restart()
      }
    }
    return true
  }

  function loadCached() {
    if (!helperPath || cachedProcess.running) return false
    cachedProcess.output = ""
    cachedProcess.command = [helperPath, "cached", sourceDir]
    cachedProcess.running = true
    return true
  }

  function startInitialLoad() {
    if (initialLoadStarted || !helperPath) return false
    initialLoadStarted = loadCached()
    return initialLoadStarted
  }

  function requestRefresh(force) {
    if (!helperPath) return
    if (refreshProcess.running) {
      refreshProcess.forceQueued = refreshProcess.forceQueued || force === true
      return
    }
    clearRefreshSuccess()
    refreshBaselineTimestamp = lastSuccessfulRefresh
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
    var previousAcknowledged = actionState
      && actionState.acknowledged === false
    var previousActionId = String(actionState && actionState.actionId || "")
    var parsed = parseJson(raw, null)
    if (!parsed || typeof parsed !== "object") return
    actionState = parsed
    var finishedUnacknowledged = parsed.running !== true
      && parsed.acknowledged !== true
    var isNewNotice = previousRunning || !previousAcknowledged
      || previousActionId !== String(parsed.actionId || "")
    if (finishedUnacknowledged && isNewNotice)
      actionNoticeTimer.restart()
    if (previousRunning && parsed.running !== true) {
      loadCached()
      actionFinished(parsed)
    }
  }

  function startAction(operation, pluginId, snapshotId, executionMode) {
    if (!helperPath || actionRunning || actionProcess.running) return false
    if (["add", "remove", "remove-purge", "enable", "disable"]
        .indexOf(String(operation)) < 0) return false
    if (!String(pluginId) || !String(snapshotId)) return false
    if (["background", "terminal"].indexOf(String(executionMode)) < 0)
      return false
    if (executionMode === "terminal" && operation !== "add") return false
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
      actionNoticeTimer.restart()
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
    actionNoticeTimer.stop()
    if (helperPath && actionId)
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
    id: channelConfigFile
    path: root.channelConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.channelConfigWatchReady = true
      configWatchRetry.stop()
    }
    onLoadFailed: {
      root.channelConfigWatchReady = false
      configWatchRetry.restart()
    }
    onFileChanged: {
      root.channelConfigWatchReady = false
      reload()
      root.configChangeRevision++
      configRefreshDebounce.restart()
    }
  }

  Timer {
    id: configWatchRetry
    interval: 1000
    repeat: false
    onTriggered: channelConfigFile.reload()
  }

  Process {
    id: configSyncProcess
    property string output: ""
    property int revision: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: configSyncProcess.output = text
    }
    onExited: function(exitCode) {
      root.applyConfigStatus(output, exitCode, revision)
      root.notifyConfigProblem(output, revision)
      if (root.configSyncQueued || revision !== root.configChangeRevision)
        Qt.callLater(root.requestConfigSync)
    }
  }

  Process {
    id: cachedProcess
    property string output: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: cachedProcess.output = text
    }
    onExited: function(exitCode) {
      root.applySnapshot(output, exitCode, false)
      channelConfigFile.reload()
      Qt.callLater(root.requestStatus)
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
      root.applySnapshot(output, exitCode, true)
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
    onTriggered: {
      root.requestConfigSync()
      root.requestRefresh(true)
    }
  }

  Timer {
    id: actionPoll
    interval: 500
    repeat: true
    running: root.actionRunning
    onTriggered: root.requestStatus()
  }

  Timer {
    id: actionNoticeTimer
    interval: root.actionNoticeDurationMs
    repeat: false
    onTriggered: root.acknowledgeAction()
  }

  Timer {
    id: refreshSuccessTimer
    interval: root.refreshSuccessDurationMs
    repeat: false
    onTriggered: root.refreshSuccessVisible = false
  }

  onHelperPathChanged: startInitialLoad()

  Component.onCompleted: {
    animationProbe.running = true
    startInitialLoad()
  }
}
