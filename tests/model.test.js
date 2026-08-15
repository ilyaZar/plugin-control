"use strict";

const assert = require("node:assert/strict");
const Fuzzy = require("../Fuzzy.js");
const Catalog = require("../CatalogModel.js");

function test(name, callback) {
  try {
    callback();
    process.stdout.write(`ok - ${name}\n`);
  } catch (error) {
    process.stderr.write(`not ok - ${name}\n${error.stack}\n`);
    process.exitCode = 1;
  }
}

const records = Catalog.prepareRecords([
  {
    id: "io.example.weather",
    name: "Weather Station",
    description: "Forecast in the bar",
    author: "Alice",
    tags: ["forecast", "bar"],
    category: "Information",
    kind: "Bar widget",
    repository: "https://github.com/alice/weather",
    source: "marketplace",
    installable: true
  },
  {
    id: "io.example.power",
    name: "Power Profiles",
    description: "Switch power modes",
    author: "Bob",
    tags: ["battery"],
    source: "marketplace",
    installable: false
  },
  {
    id: "local.notes",
    name: "Notes",
    description: "Local notes",
    author: "Carla",
    source: "local",
    installed: true,
    removable: true
  },
  {
    id: "omarchy.clock",
    name: "Clock",
    source: "builtin",
    builtIn: true,
    enabled: true,
    installable: false,
    removable: false
  },
  {
    id: Catalog.SELF_ID,
    name: "Plugin Control",
    source: "local",
    installed: true,
    removable: true
  }
]);

test("browse query has no command mode", () => {
  assert.deepEqual(Fuzzy.parseQuery("weather"), {
    mode: "browse", query: "weather"
  });
});

test("prefix parsing is case-insensitive", () => {
  assert.equal(Fuzzy.parseQuery("PLUG-INSTALL: weather").mode, "install");
  assert.equal(Fuzzy.parseQuery("Plug-Remove: notes").mode, "remove");
});

test("whitespace around a colon is accepted", () => {
  const parsed = Fuzzy.parseQuery("  plug-remove   :   local ");
  assert.equal(parsed.mode, "remove");
  assert.equal(parsed.query, "local");
});

test("install mode limits candidates", () => {
  const result = Fuzzy.search(records, "plug-install: weather", 50,
    Catalog.SELF_ID);
  assert.deepEqual(result.results.map((row) => row.id), ["io.example.weather"]);
});

test("remove mode limits candidates and excludes self", () => {
  const result = Fuzzy.search(records, "plug-remove: ", 50,
    Catalog.SELF_ID);
  assert.deepEqual(result.results.map((row) => row.id), ["local.notes"]);
});

test("exact name outranks prefix and fuzzy matches", () => {
  const values = Catalog.prepareRecords([
    { id: "x.weather", name: "Weather", source: "custom" },
    { id: "x.weather-station", name: "Weather Station", source: "custom" },
    { id: "x.wthr", name: "Wild Thunder", source: "custom" }
  ]);
  assert.equal(Fuzzy.search(values, "weather", 10, "self").results[0].id,
    "x.weather");
});

test("token boundary outranks later contiguous matches", () => {
  const boundary = { id: "x.one", name: "Panel Media", source: "custom" };
  const middle = { id: "x.two", name: "Multimedia", source: "custom" };
  const values = Catalog.prepareRecords([middle, boundary]);
  assert.equal(Fuzzy.search(values, "media", 10, "self").results[0].id,
    "x.one");
});

test("ordered fuzzy subsequences match", () => {
  const values = Catalog.prepareRecords([
    { id: "x.control", name: "Plugin Control" }
  ]);
  assert.ok(Fuzzy.scoreRecord(values[0], "plgctl") > 0);
});

test("name subsequences outrank secondary metadata matches", () => {
  const values = Catalog.prepareRecords([
    { id: "x.control", name: "Plugin Control" },
    { id: "x.helper", name: "Helper", description: "plgctl helper" }
  ]);
  assert.equal(Fuzzy.search(values, "plgctl", 10, "self").results[0].id,
    "x.control");
});

test("stable ties use name then id", () => {
  const values = Catalog.prepareRecords([
    { id: "z.two", name: "Same", author: "match", source: "custom" },
    { id: "a.one", name: "Same", author: "match", source: "custom" },
    { id: "b.other", name: "Alpha", author: "match", source: "custom" }
  ]);
  assert.deepEqual(Fuzzy.search(values, "match", 10, "self").results
    .map((row) => row.id), ["b.other", "a.one", "z.two"]);
});

test("search is case-insensitive", () => {
  assert.equal(Fuzzy.search(records, "WEATHER", 10, "self").results[0].id,
    "io.example.weather");
});

test("ID author and tags are searchable", () => {
  assert.equal(Fuzzy.search(records, "io.example.weather", 10, "self")
    .results[0].id, "io.example.weather");
  assert.equal(Fuzzy.search(records, "alice", 10, "self").results[0].id,
    "io.example.weather");
  assert.equal(Fuzzy.search(records, "forecast", 10, "self").results[0].id,
    "io.example.weather");
});

test("result caps are enforced", () => {
  assert.equal(Fuzzy.search(records, "", 2, "self").results.length, 2);
});

test("browse-only and installed-only entries remain discoverable", () => {
  assert.equal(Fuzzy.search(records, "power", 10, "self").results[0].id,
    "io.example.power");
  assert.equal(Fuzzy.search(records, "notes", 10, "self").results[0].id,
    "local.notes");
});

test("validation drift creates a warning", () => {
  assert.equal(Catalog.warningState({
    upstreamCheckStatus: "passed",
    listingValidatedCommit: "aaa",
    upstreamObservedCommit: "bbb"
  }), "Upstream changed");
});

test("built-ins do not show upstream validation warnings", () => {
  assert.equal(Catalog.warningState({
    builtIn: true,
    upstreamCheckStatus: "unknown"
  }), "");
});

test("unlisted security labels remain visible warnings", () => {
  assert.equal(Catalog.warningState({
    unlisted: true,
    securityWarnings: ["security-review-required"]
  }), "Unlisted - security-review-required");
});

test("bar widget kinds accept native hyphenated spelling", () => {
  assert.equal(Catalog.isBarWidget("bar-widget"), true);
  assert.equal(Catalog.isBarWidget("Bar widget"), true);
  assert.equal(Catalog.isBarWidget("overlay"), false);
});
