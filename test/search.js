var assert = require("assert")
var Search = require("../src/GopassSearch.js")

var failures = 0
function check(name, fn) {
  try {
    fn()
    console.log("ok   " + name)
  } catch (e) {
    failures++
    console.log("FAIL " + name + ": " + e.message)
  }
}

check("parseList splits, trims, and drops blank lines", function() {
  var out = Search.parseList("a/b\nc/d\r\n\n  \nwork/totp\n")
  assert.deepStrictEqual(out, ["a/b", "c/d", "work/totp"])
})

check("parseList handles empty/undefined input", function() {
  assert.deepStrictEqual(Search.parseList(""), [])
  assert.deepStrictEqual(Search.parseList(undefined), [])
})

check("basename returns the last path segment", function() {
  assert.strictEqual(Search.basename("work/github/erin/totp"), "totp")
  assert.strictEqual(Search.basename("root"), "root")
})

check("childrenOf lists subfolders and leaf entries directly under a prefix", function() {
  var paths = ["work/dev/db/root", "work/dev/db/erin", "work/github/erin/totp", "apple.com/me@example.com", "root"]
  var root = Search.childrenOf(paths, "")
  assert.deepStrictEqual(root.dirs, ["apple.com", "work"])
  assert.deepStrictEqual(root.entries, ["root"])

  var work = Search.childrenOf(paths, "work/")
  assert.deepStrictEqual(work.dirs, ["dev", "github"])
  assert.deepStrictEqual(work.entries, [])

  var db = Search.childrenOf(paths, "work/dev/db/")
  assert.deepStrictEqual(db.dirs, [])
  assert.deepStrictEqual(db.entries, ["work/dev/db/erin", "work/dev/db/root"])
})

check("childrenOf ignores paths outside the given prefix", function() {
  var out = Search.childrenOf(["work/dev/db/root", "other/thing"], "work/")
  assert.deepStrictEqual(out.dirs, ["dev"])
  assert.deepStrictEqual(out.entries, [])
})

check("parentDir strips the last path segment", function() {
  assert.strictEqual(Search.parentDir("work/dev/"), "work/")
  assert.strictEqual(Search.parentDir("work/"), "")
  assert.strictEqual(Search.parentDir(""), "")
})

check("isTotp matches only a leaf literally named totp, case-insensitive", function() {
  assert.strictEqual(Search.isTotp("work/github/erin/totp"), true)
  assert.strictEqual(Search.isTotp("work/github/erin/TOTP"), true)
  assert.strictEqual(Search.isTotp("work/totp-backup-codes"), false)
  assert.strictEqual(Search.isTotp("work/dev/db/root"), false)
})

check("splitEntries separates totp leaves from everything else", function() {
  var paths = ["work/dev/db/root", "work/github/erin/totp", "apple.com/me@example.com"]
  var out = Search.splitEntries(paths)
  assert.deepStrictEqual(out.secrets, ["work/dev/db/root", "apple.com/me@example.com"])
  assert.deepStrictEqual(out.totps, ["work/github/erin/totp"])
})

check("totpAccounts maps each account's parent path to its real totp leaf", function() {
  var out = Search.totpAccounts(["work/github/erin/totp", "work/github/other/TOTP", "totp"])
  assert.deepStrictEqual(out.accounts, ["work/github/erin", "work/github/other", "totp"])
  assert.deepStrictEqual(out.pathFor, {
    "work/github/erin": "work/github/erin/totp",
    "work/github/other": "work/github/other/TOTP",
    "totp": "totp"
  })
})

check("fuzzyScore requires every needle char in order", function() {
  assert.strictEqual(Search.fuzzyScore("work/dev/db/root", "xyz"), null)
  assert.notStrictEqual(Search.fuzzyScore("work/dev/db/root", "wdbroot"), null)
  assert.notStrictEqual(Search.fuzzyScore("work/dev/db/root", "work/dev/db/root"), null)
})

check("fuzzyScore rewards matches at path-segment boundaries", function() {
  var boundary = Search.fuzzyScore("work/dev/db/root", "db")
  var midword = Search.fuzzyScore("abdomen", "db")
  assert.ok(boundary > midword, boundary + " should be > " + midword)
})

check("filterEntries with no query returns everything, alphabetical, capped at limit", function() {
  var out = Search.filterEntries(["b", "a", "c"], "", 10)
  assert.deepStrictEqual(out, ["a", "b", "c"])
  var capped = Search.filterEntries(["b", "a", "c"], "", 2)
  assert.deepStrictEqual(capped, ["a", "b"])
})

check("filterEntries with a query keeps only matches, best first", function() {
  var paths = ["work/dev/db/root", "work/dev/db/erin", "apple.com/me@example.com"]
  var out = Search.filterEntries(paths, "db", 10)
  assert.deepStrictEqual(out, ["work/dev/db/erin", "work/dev/db/root"])
})

check("filterEntries is case-insensitive", function() {
  var out = Search.filterEntries(["Work/Dev/DB/Root"], "dbroot", 10)
  assert.deepStrictEqual(out, ["Work/Dev/DB/Root"])
})

check("firstLine takes only the text up to the first line break", function() {
  assert.strictEqual(Search.firstLine("secret\nrest\nof\nfile"), "secret")
  assert.strictEqual(Search.firstLine("secret\r\nrest"), "secret")
  assert.strictEqual(Search.firstLine("nolinebreak"), "nolinebreak")
  assert.strictEqual(Search.firstLine(""), "")
  assert.strictEqual(Search.firstLine(undefined), "")
})

check("normalizePath trims slashes and whitespace", function() {
  assert.strictEqual(Search.normalizePath("  /work/github/alice/  "), "work/github/alice")
  assert.strictEqual(Search.normalizePath("work//github///alice"), "work/github/alice")
  assert.strictEqual(Search.normalizePath(""), "")
  assert.strictEqual(Search.normalizePath(undefined), "")
})

check("ensureTotpSuffix appends totp unless already the leaf", function() {
  assert.strictEqual(Search.ensureTotpSuffix("work/github/alice"), "work/github/alice/totp")
  assert.strictEqual(Search.ensureTotpSuffix("work/github/alice/totp"), "work/github/alice/totp")
  assert.strictEqual(Search.ensureTotpSuffix("work/github/alice/TOTP"), "work/github/alice/TOTP")
  assert.strictEqual(Search.ensureTotpSuffix(""), "totp")
})

check("buildOtpauthUri derives label/issuer from the account path", function() {
  var uri = Search.buildOtpauthUri("work/github/alice", "jbsw y3dp ehpk 3pxp")
  assert.strictEqual(uri, "otpauth://totp/github%3Aalice?secret=JBSWY3DPEHPK3PXP&issuer=github")
})

check("buildOtpauthUri omits issuer for a top-level account", function() {
  var uri = Search.buildOtpauthUri("github", "JBSWY3DPEHPK3PXP")
  assert.strictEqual(uri, "otpauth://totp/github?secret=JBSWY3DPEHPK3PXP")
})

if (failures > 0) {
  console.log(failures + " failure(s)")
  process.exit(1)
}
console.log("all passed")
