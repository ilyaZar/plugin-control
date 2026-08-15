function text(value) {
  return value === undefined || value === null ? "" : String(value)
}

function normalize(value) {
  return text(value).toLowerCase().replace(/\s+/g, " ").trim()
}

function commandRecord(name, operation, description) {
  return {
    name: name + ":",
    description: description,
    author: "Plugin Control",
    kind: "Command",
    stateLabel: "TAB / ENTER",
    sourceLabel: "Command",
    commandCompletion: name + ": ",
    commandName: name + ":",
    operation: operation
  }
}

var COMMANDS = [
  commandRecord("plug-install", "install",
    "Search available plugins to install"),
  commandRecord("plug-remove", "remove", "Search removable local plugins")
]

function parseQuery(value) {
  var raw = text(value)
  var match = /^\s*plug-(install|remove)\s*:\s*([\s\S]*)$/i.exec(raw)
  if (!match) return { mode: "browse", query: raw.trim() }

  var command = match[1].toLowerCase()
  return {
    mode: command,
    query: match[2].trim()
  }
}

function tokenBoundaryIndex(haystack, needle) {
  var offset = 0
  while (offset <= haystack.length - needle.length) {
    var index = haystack.indexOf(needle, offset)
    if (index < 0) return -1
    if (index === 0 || /[\s._\-/]/.test(haystack.charAt(index - 1))) return index
    offset = index + 1
  }
  return -1
}

function subsequenceCost(haystack, needle) {
  var position = 0
  var start = -1
  var previous = -1
  var gaps = 0

  for (var i = 0; i < needle.length; i++) {
    var found = haystack.indexOf(needle.charAt(i), position)
    if (found < 0) return -1
    if (start < 0) start = found
    if (previous >= 0) gaps += found - previous - 1
    previous = found
    position = found + 1
  }
  return start * 4 + gaps
}

function fieldScore(haystack, query, priority, exactEligible) {
  if (!haystack || !query) return -1

  if (exactEligible && haystack === query) return 100000 + priority
  if (haystack.indexOf(query) === 0) return 80000 + priority - haystack.length

  var boundary = tokenBoundaryIndex(haystack, query)
  if (boundary >= 0) return 60000 + priority - boundary

  var contiguous = haystack.indexOf(query)
  if (contiguous >= 0) return 40000 + priority - contiguous

  var cost = subsequenceCost(haystack, query)
  return cost >= 0 ? 20000 + priority - cost : -1
}

function scoreRecord(record, rawQuery) {
  var query = normalize(rawQuery)
  if (!query) return 0
  var fields = record.searchFields
  if (!Array.isArray(fields) || fields.length !== 9) return -1
  var priorities = [900, 850, 420, 320, 260, 240, 220, 180, 100]

  var primary = -1
  for (var i = 0; i < 2; i++) {
    var primaryScore = fieldScore(fields[i], query, priorities[i], true)
    if (primaryScore > primary) primary = primaryScore
  }
  if (primary >= 0) return 200000 + primary

  var best = -1
  for (var j = 2; j < fields.length; j++) {
    var candidate = fieldScore(fields[j], query, priorities[j], false)
    if (candidate > best) best = candidate
  }
  return best
}

function compareRows(left, right) {
  if (left.score !== right.score) return right.score - left.score
  var leftName = left.record.searchFields[0]
  var rightName = right.record.searchFields[0]
  if (leftName < rightName) return -1
  if (leftName > rightName) return 1
  var leftId = left.record.searchFields[1]
  var rightId = right.record.searchFields[1]
  return leftId < rightId ? -1 : (leftId > rightId ? 1 : 0)
}

function commandIntent(value) {
  var query = normalize(value)
  if (query.length < 3 || query.indexOf(":") >= 0) return false
  return "plug-".indexOf(query) === 0
    || query.indexOf("plug-") === 0
    || query.indexOf("plg-") === 0
}

function commandSuggestions(value) {
  if (!commandIntent(value)) return null
  var query = normalize(value)
  var results = []
  for (var i = 0; i < COMMANDS.length; i++) {
    var command = COMMANDS[i]
    var canonicalScore = fieldScore(command.commandName, query, 900, true)
    var operationScore = fieldScore(command.operation, query, 850, true)
    if (Math.max(canonicalScore, operationScore) >= 0)
      results.push(command)
  }
  return results
}

function eligible(record, mode, selfId) {
  if (!record || !record.id) return false
  if (mode === "install")
    return record.installable === true && record.installed !== true
  if (mode === "remove")
    return record.removable === true && record.id !== selfId
  return true
}

function search(records, input, limit, selfId) {
  var parsed = parseQuery(input)
  var values = Array.isArray(records) ? records : []
  var maximum = Number(limit)
  if (!isFinite(maximum)) maximum = 50
  maximum = Math.max(0, Math.min(100, Math.floor(maximum)))
  if (parsed.mode === "browse" && normalize(input).indexOf(":") >= 0)
    return { mode: "command", results: [] }
  var commands = parsed.mode === "browse" ? commandSuggestions(input) : null
  if (commands !== null) {
    return { mode: "command", results: commands.slice(0, maximum) }
  }
  var rows = []

  for (var i = 0; i < values.length; i++) {
    var record = values[i]
    if (!eligible(record, parsed.mode, selfId)) continue
    var score = scoreRecord(record, parsed.query)
    if (parsed.query && score < 0) continue
    rows.push({ record: record, score: score })
  }

  rows.sort(compareRows)
  var results = []
  var rawQuery = normalize(input)
  if (parsed.mode === "browse"
      && (!rawQuery || (rawQuery.length < 3
        && "plug-".indexOf(rawQuery) === 0))) {
    for (var k = 0; k < COMMANDS.length && results.length < maximum; k++)
      results.push(COMMANDS[k])
  } else if (parsed.mode === "browse") {
    for (var m = 0; m < COMMANDS.length && results.length < maximum; m++) {
      if (fieldScore(COMMANDS[m].operation, rawQuery, 850, true) >= 0)
        results.push(COMMANDS[m])
    }
  }
  for (var j = 0; j < rows.length && results.length < maximum; j++)
    results.push(rows[j].record)
  return { mode: parsed.mode, results: results }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseQuery: parseQuery,
    scoreRecord: scoreRecord,
    search: search
  }
}
