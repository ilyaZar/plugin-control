function settingsResult() {
  return {
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
        name: "Cleanly remove Plugin Control and user data",
        description: "Remove the plugin with optional user-data cleanup",
        settingsAction: "remove-self",
        separatorBefore: true,
        dangerous: true
      },
      {
        name: "Cancel / Back",
        description: "Return to the plugin list",
        settingsAction: "cancel"
      }
    ]
  }
}

function displayRecord(record) {
  var value = record || {}
  var id = String(value.id || "")
  var thumbUrl = String(value.previewThumbnailUrl || value.previewImageUrl || "")
  var detailUrl = String(value.previewImageUrl || "")
  if (!thumbUrl && id) {
    thumbUrl = "file://" + (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/plugins/" + id + "/preview.png"
  }
  return {
    pluginName: String(value.name || value.id || ""),
    pluginId: id,
    description: String(value.description || ""),
    author: String(value.author || "Unknown"),
    kind: String(value.kind || value.category || "Plugin"),
    stateLabel: String(value.stateLabel || "Browse only"),
    sourceLabel: String(value.sourceLabel || value.sourceName || "Unknown"),
    warning: String(value.warning || ""),
    version: String(value.version || ""),
    releaseTag: String(value.releaseTag || ""),
    repository: String(value.repository || ""),
    separatorBefore: value.separatorBefore === true,
    dangerous: value.dangerous === true,
    previewThumbnailUrl: thumbUrl,
    previewImageUrl: detailUrl,
    installed: value.installed === true,
    builtIn: value.builtIn === true
  }
}

function updateOption(record) {
  var status = String(record && record.updateStatus || "unknown")
  var unavailable = ["manual", "dirty", "ahead", "diverged", "unsupported",
    "error"]
    .indexOf(status) >= 0
  return {
    operation: "update",
    label: "Update",
    available: !unavailable,
    reason: unavailable ? String(record.updateReason
      || "This plugin cannot be updated safely.") : ""
  }
}

function actionOptions(record, readOnly) {
  if (readOnly === true)
    return [{ operation: "close", label: "Close", available: true }]

  var options = [
    { operation: "cancel", label: "Cancel", available: true }
  ]
  if (!record || !record.id) return options

  var present = record.builtIn === true || record.installed === true
  if (record.fullBar === true) {
    if (present && record.enabled === false)
      options.push({ operation: "enable", label: "Enable", available: true })
    return options
  }
  if (record.builtIn === true) {
    if (record.canDisable === true) {
      options.push(record.enabled === false
        ? { operation: "enable", label: "Enable", available: true }
        : { operation: "disable", label: "Disable", available: true })
    }
    return options
  }
  if (record.installed === true) {
    options.push(updateOption(record))
    if (record.canDisable === true) {
      options.push(record.enabled === false
        ? { operation: "enable", label: "Enable", available: true }
        : { operation: "disable", label: "Disable", available: true })
    }
    options.push({ operation: "remove", label: "Uninstall",
      available: record.dirty !== true,
      reason: record.dirty === true
        ? "Removal is blocked because this Git checkout has local changes."
        : "", dangerous: true })
    return options
  }
  if (record.installable === true)
    options.push({ operation: "add", label: "Add", available: true })
  return options
}

function removableRecord(records, id) {
  var values = Array.isArray(records) ? records : []
  for (var i = 0; i < values.length; i++) {
    var record = values[i]
    if (record && record.id === id && record.installed === true
        && record.removable === true) return record
  }
  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    actionOptions: actionOptions,
    displayRecord: displayRecord,
    removableRecord: removableRecord,
    settingsResult: settingsResult
  }
}
