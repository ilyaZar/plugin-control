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
  return {
    pluginName: String(value.name || value.id || ""),
    pluginId: String(value.id || ""),
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
    dangerous: value.dangerous === true
  }
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
    displayRecord: displayRecord,
    removableRecord: removableRecord,
    settingsResult: settingsResult
  }
}
