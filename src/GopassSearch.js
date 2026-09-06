function parseList(raw) {
  var lines = String(raw || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/\r$/, "").trim()
    if (line.length > 0) out.push(line)
  }
  return out
}

function basename(path) {
  var idx = String(path || "").lastIndexOf("/")
  return idx >= 0 ? path.substring(idx + 1) : path
}

function childrenOf(paths, dirPath) {
  var values = Array.isArray(paths) ? paths : []
  var prefix = dirPath || ""
  var dirSeen = {}
  var dirs = []
  var entries = []
  for (var i = 0; i < values.length; i++) {
    var path = values[i]
    if (prefix.length > 0) {
      if (path.substring(0, prefix.length) !== prefix) continue
      path = path.substring(prefix.length)
    }
    if (path.length === 0) continue
    var slashIdx = path.indexOf("/")
    if (slashIdx >= 0) {
      var name = path.substring(0, slashIdx)
      if (!dirSeen.hasOwnProperty(name)) {
        dirSeen[name] = true
        dirs.push(name)
      }
    } else {
      entries.push(prefix + path)
    }
  }
  dirs.sort()
  entries.sort()
  return { dirs: dirs, entries: entries }
}

function parentDir(dirPath) {
  var trimmed = String(dirPath || "").replace(/\/$/, "")
  var idx = trimmed.lastIndexOf("/")
  return idx >= 0 ? trimmed.substring(0, idx + 1) : ""
}

function isTotp(path) {
  return basename(path).toLowerCase() === "totp"
}

function splitEntries(paths) {
  var secrets = []
  var totps = []
  var values = Array.isArray(paths) ? paths : []
  for (var i = 0; i < values.length; i++) {
    if (isTotp(values[i])) totps.push(values[i])
    else secrets.push(values[i])
  }
  return { secrets: secrets, totps: totps }
}

function totpAccounts(paths) {
  var values = Array.isArray(paths) ? paths : []
  var pathFor = {}
  var accounts = []
  for (var i = 0; i < values.length; i++) {
    var full = values[i]
    var idx = full.lastIndexOf("/")
    var account = idx >= 0 ? full.substring(0, idx) : full
    if (!pathFor.hasOwnProperty(account)) accounts.push(account)
    pathFor[account] = full
  }
  return { accounts: accounts, pathFor: pathFor }
}

function fuzzyScore(candidateLower, needleLower) {
  if (needleLower.length === 0) return 0
  var ci = 0, ni = 0
  var score = 0
  var consecutive = 0
  var firstMatchIndex = -1

  while (ci < candidateLower.length && ni < needleLower.length) {
    if (candidateLower.charAt(ci) === needleLower.charAt(ni)) {
      if (firstMatchIndex < 0) firstMatchIndex = ci
      var prev = ci > 0 ? candidateLower.charAt(ci - 1) : ""
      var atBoundary = ci === 0 || prev === "/" || prev === "-" || prev === "_" || prev === "." || prev === " "
      score += atBoundary ? 10 : 1
      score += consecutive * 3
      consecutive++
      ni++
    } else {
      consecutive = 0
    }
    ci++
  }

  if (ni < needleLower.length) return null

  score -= firstMatchIndex * 0.1
  score -= candidateLower.length * 0.05
  return score
}

function normalizedQuery(query) {
  return String(query || "").trim().toLowerCase()
}

function filterEntries(paths, query, limit) {
  var values = Array.isArray(paths) ? paths : []
  var needle = normalizedQuery(query)
  var max = limit === undefined || limit === null ? 300 : Number(limit)
  if (isNaN(max)) max = 300
  max = Math.max(0, max)

  var scored = []
  for (var i = 0; i < values.length; i++) {
    var path = values[i]
    if (!needle) {
      scored.push({ path: path, score: 0 })
      continue
    }
    var s = fuzzyScore(path.toLowerCase(), needle)
    if (s !== null) scored.push({ path: path, score: s })
  }

  if (needle) {
    scored.sort(function(a, b) {
      if (b.score !== a.score) return b.score - a.score
      if (a.path.length !== b.path.length) return a.path.length - b.path.length
      return a.path < b.path ? -1 : (a.path > b.path ? 1 : 0)
    })
  } else {
    scored.sort(function(a, b) { return a.path < b.path ? -1 : (a.path > b.path ? 1 : 0) })
  }

  if (scored.length > max) scored.length = max

  var out = []
  for (var j = 0; j < scored.length; j++) out.push(scored[j].path)
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    parseList: parseList,
    basename: basename,
    childrenOf: childrenOf,
    parentDir: parentDir,
    isTotp: isTotp,
    splitEntries: splitEntries,
    totpAccounts: totpAccounts,
    fuzzyScore: fuzzyScore,
    normalizedQuery: normalizedQuery,
    filterEntries: filterEntries
  }
}
