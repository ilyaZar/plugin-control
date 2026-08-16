"use strict";

const assert = require("node:assert/strict");
const Fuzzy = require("../Fuzzy.js");
const Catalog = require("../CatalogModel.js");
const Palette = require("../PaletteViewModel.js");
const SELF_ID = "io.github.ilyazar.plugin-control";

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
    id: SELF_ID,
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

test("empty browse leaves commands unpinned", () => {
  const result = Fuzzy.search(records, "", 50);
  assert.equal(result.mode, "browse");
  assert.equal(result.results.some((row) => row.commandCompletion), false);
  assert.equal(result.results[0].name, "Clock");
});

test("short plugin text leaves commands unpinned", () => {
  for (const query of ["p", "pl", "n"]) {
    const result = Fuzzy.search(records, query, 50);
    assert.equal(result.mode, "browse");
    assert.equal(result.results.some((row) => row.commandCompletion), false);
  }
});

test("partial command input hides plugin rows", () => {
  const install = Fuzzy.search(records, "plug-in", 50);
  assert.equal(install.mode, "command");
  assert.deepEqual(install.results.map((row) => row.commandCompletion),
    ["plug-install: "]);

  const remove = Fuzzy.search(records, "plug-rm", 50);
  assert.equal(remove.mode, "command");
  assert.deepEqual(remove.results.map((row) => row.commandCompletion),
    ["plug-remove: "]);
});

test("command-shaped selection is fuzzy and keeps install first", () => {
  for (const query of ["plg-in"]) {
    const result = Fuzzy.search(records, query, 50);
    assert.equal(result.mode, "command");
    assert.deepEqual(result.results.map((row) => row.commandCompletion),
      ["plug-install: "]);
  }
  assert.deepEqual(Fuzzy.search(records, "plug", 50)
    .results.map((row) => row.commandCompletion),
    ["plug-install: ", "plug-remove: "]);
  assert.deepEqual(Fuzzy.search(records, "plug", 1)
    .results.map((row) => row.commandCompletion), ["plug-install: "]);
});

test("operation intent promotes commands above browse results", () => {
  for (const query of ["i", "in", "inst", "istl"]) {
    const result = Fuzzy.search(records, query, 50);
    assert.equal(result.mode, "browse");
    assert.equal(result.results[0].commandCompletion, "plug-install: ");
  }
  for (const query of ["r", "re", "rem"]) {
    const result = Fuzzy.search(records, query, 50);
    assert.equal(result.mode, "browse");
    assert.equal(result.results[0].commandCompletion, "plug-remove: ");
  }

  for (const query of ["sta", "all", "ove"]) {
    const result = Fuzzy.search(records, query, 50);
    assert.equal(result.mode, "browse");
    assert.equal(result.results.some((row) => row.commandCompletion), false);
  }
  const station = Fuzzy.search(records, "sta", 50);
  assert.ok(station.results.some((row) => row.id === "io.example.weather"));
});

test("ordinary plugin text does not become a command", () => {
  const result = Fuzzy.search(records, "plugin", 50);
  assert.equal(result.mode, "browse");
  assert.deepEqual(result.results.map((row) => row.id),
    [SELF_ID]);
});

test("deleting the colon returns to command completion", () => {
  const result = Fuzzy.search(records, "plug-install", 50);
  assert.equal(result.mode, "command");
  assert.equal(result.results[0].commandCompletion, "plug-install: ");
});

test("malformed colon input is inert", () => {
  for (const query of ["plug-instll:", "plug-unknown:", "weather:"]) {
    const result = Fuzzy.search(records, query, 50);
    assert.equal(result.mode, "command");
    assert.deepEqual(result.results, []);
  }
});

test("install mode limits candidates", () => {
  const result = Fuzzy.search(records, "plug-install: weather", 50);
  assert.deepEqual(result.results.map((row) => row.id), ["io.example.weather"]);
});

test("remove mode includes removable self", () => {
  const result = Fuzzy.search(records, "plug-remove: ", 50);
  assert.deepEqual(result.results.map((row) => row.id),
    ["local.notes", SELF_ID]);
});

test("exact name outranks prefix and fuzzy matches", () => {
  const values = Catalog.prepareRecords([
    { id: "x.weather", name: "Weather", source: "custom" },
    { id: "x.weather-station", name: "Weather Station", source: "custom" },
    { id: "x.wthr", name: "Wild Thunder", source: "custom" }
  ]);
  assert.equal(Fuzzy.search(values, "weather", 10).results[0].id,
    "x.weather");
});

test("token boundary outranks later contiguous matches", () => {
  const boundary = { id: "x.one", name: "Panel Media", source: "custom" };
  const middle = { id: "x.two", name: "Multimedia", source: "custom" };
  const values = Catalog.prepareRecords([middle, boundary]);
  assert.equal(Fuzzy.search(values, "media", 10).results[0].id,
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
  assert.equal(Fuzzy.search(values, "plgctl", 10).results[0].id,
    "x.control");
});

test("stable ties use name then id", () => {
  const values = Catalog.prepareRecords([
    { id: "z.two", name: "Same", author: "match", source: "custom" },
    { id: "a.one", name: "Same", author: "match", source: "custom" },
    { id: "b.other", name: "Alpha", author: "match", source: "custom" }
  ]);
  assert.deepEqual(Fuzzy.search(values, "match", 10).results
    .map((row) => row.id), ["b.other", "a.one", "z.two"]);
});

test("search is case-insensitive", () => {
  assert.equal(Fuzzy.search(records, "WEATHER", 10).results[0].id,
    "io.example.weather");
});

test("ID author and tags are searchable", () => {
  assert.equal(Fuzzy.search(records, "io.example.weather", 10)
    .results[0].id, "io.example.weather");
  assert.equal(Fuzzy.search(records, "alice", 10).results[0].id,
    "io.example.weather");
  assert.equal(Fuzzy.search(records, "forecast", 10).results[0].id,
    "io.example.weather");
});

test("result caps are enforced", () => {
  assert.equal(Fuzzy.search(records, "", 2).results.length, 2);
});

test("browse-only and installed-only entries remain discoverable", () => {
  assert.equal(Fuzzy.search(records, "power", 10).results[0].id,
    "io.example.power");
  assert.equal(Fuzzy.search(records, "notes", 10).results[0].id,
    "local.notes");
});

test("marketplace provenance survives local presentation", () => {
  const listedLocal = Catalog.prepareRecords([{
    id: "x.listed",
    name: "Listed local",
    source: "local",
    marketplaceListed: true,
    installed: true
  }])[0];
  assert.equal(listedLocal.source, "local");
  assert.equal(listedLocal.marketplaceListed, true);
  const localBuiltin = Catalog.prepareRecords([{
    id: "omarchy.local",
    name: "Local built-in",
    source: "builtin",
    builtIn: true
  }])[0];
  assert.equal(localBuiltin.marketplaceListed, false);
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

test("palette view model keeps settings and records declarative", () => {
  const settings = Palette.settingsResult();
  assert.equal(settings.mode, "settings");
  assert.equal(settings.results[2].settingsAction, "remove-self");
  assert.equal(settings.results[2].dangerous, true);
  assert.equal(Palette.displayRecord({ id: "example", name: "Example" })
    .pluginName, "Example");
  assert.equal(Palette.removableRecord(records, SELF_ID).id, SELF_ID);
  assert.equal(Palette.removableRecord(records, "missing"), null);
});
