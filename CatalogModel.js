function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function text(value) {
  return value === undefined || value === null ? "" : String(value)
}

function cleanText(value) {
  return text(value).trim()
}

function searchText(value) {
  return cleanText(value).toLowerCase().replace(/\s+/g, " ")
}

function copy(value) {
  var out = {}
  if (!isRecord(value)) return out
  for (var key in value) out[key] = value[key]
  return out
}

function sourceRank(record) {
  if (record && isFinite(Number(record.sourceRank)))
    return Number(record.sourceRank)
  var source = cleanText(record && record.source)
  if (source === "local") return 50
  if (source === "builtin") return 40
  if (source === "marketplace") return 30
  if (source === "submission") return 20
  return 10
}

function sourceLabel(record) {
  var source = cleanText(record && record.source)
  if (source === "local") return "Local checkout"
  if (source === "builtin") return "Omarchy built-in"
  if (source === "marketplace") return "Marketplace listed"
  if (source === "submission") return "Unlisted submission"
  return cleanText(record && record.sourceName) || "Custom channel"
}

function warningState(record) {
  if (record && record.builtIn === true) return ""
  var state = cleanText(record && record.upstreamCheckStatus).toLowerCase()
  if (record && record.unlisted === true) {
    var security = Array.isArray(record.securityWarnings)
      ? record.securityWarnings.slice(0, 2).map(cleanText).filter(Boolean) : []
    return security.length > 0
      ? "Unlisted - " + security.join(", ") : "Unlisted"
  }
  if (!state || state === "unknown") return "Validation unknown"
  if (state === "passed") {
    var listed = cleanText(record.listingValidatedCommit)
    var upstream = cleanText(record.upstreamObservedCommit)
    return listed && upstream && listed !== upstream ? "Upstream changed" : ""
  }
  return "Validation " + state
}

function stateLabel(record) {
  if (record.builtIn === true) return record.enabled === false ? "Disabled" : "Built-in"
  if (record.installed === true)
    return record.enabled === false ? "Disabled" : "Added"
  if (record.installable === true) return "Available"
  return "Browse only"
}

function count(value) {
  var numeric = Number(value)
  return isFinite(numeric) && numeric >= 0
    ? Math.floor(numeric) : null
}

function normalizeRecord(value) {
  var record = copy(value)
  record.id = cleanText(record.id)
  record.name = cleanText(record.name) || record.id
  record.description = cleanText(record.description)
  record.author = cleanText(record.author)
  record.version = cleanText(record.version)
  record.releaseTag = cleanText(record.releaseTag)
  record.repository = cleanText(record.repository)
  record.category = cleanText(record.category)
  record.kind = cleanText(record.kind)
  record.kinds = Array.isArray(record.kinds)
    ? record.kinds.map(cleanText).filter(Boolean) : []
  record.fullBar = record.fullBar === true
    || record.kinds.indexOf("bar") >= 0
  record.source = cleanText(record.source) || "custom"
  record.sourceName = cleanText(record.sourceName)
  record.marketplaceListed = record.marketplaceListed === true
    || record.source === "marketplace"
  record.tags = Array.isArray(record.tags) ? record.tags.map(cleanText) : []
  record.stars = count(record.stars)
  record.verificationStatus = cleanText(record.verificationStatus)
  record.metricsAvailable = record.metricsAvailable === true
  record.views = record.metricsAvailable ? count(record.views) : null
  record.copies = record.metricsAvailable ? count(record.copies) : null
  record.hearts = record.metricsAvailable ? count(record.hearts) : null
  record.sourceRank = sourceRank(record)
  record.sourceLabel = sourceLabel(record)
  record.warning = warningState(record)
  record.stateLabel = stateLabel(record)
  record.installed = record.installed === true
  record.enabled = record.enabled !== false
  record.canDisable = record.canDisable === true
  record.installable = record.installable === true && !record.installed
  record.removable = record.removable === true
    && record.builtIn !== true
  record.gitManaged = record.gitManaged === true
  record.dirty = record.dirty === true
  record.updateAvailable = record.updateAvailable === true
  record.updateStatus = cleanText(record.updateStatus) || "unknown"
  record.updateReason = cleanText(record.updateReason)
  record.localCommit = cleanText(record.localCommit)
  record.remoteCommit = cleanText(record.remoteCommit)
  record.searchFields = [record.name, record.id, record.repository,
    record.author, record.tags.join(" "), record.category, record.kind,
    record.sourceLabel, record.description].map(searchText)
  return record
}

function prepareRecords(records) {
  var values = Array.isArray(records) ? records : []
  var out = []
  for (var i = 0; i < values.length; i++) {
    var record = normalizeRecord(values[i])
    if (record.id) out.push(record)
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    warningState: warningState,
    prepareRecords: prepareRecords
  }
}
