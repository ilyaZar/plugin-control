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
    enabled: true,
    canDisable: true,
    removable: true,
    gitManaged: true,
    updateAvailable: true,
    updateStatus: "available"
  },
  {
    id: "local.disabled",
    name: "Disabled Local",
    source: "local",
    installed: true,
    enabled: false,
    canDisable: true,
    removable: false
  },
  {
    id: "omarchy.clock",
    name: "Clock",
    source: "builtin",
    builtIn: true,
    enabled: true,
    canDisable: true,
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
  assert.equal(Fuzzy.parseQuery("PLUG-ADD: weather").mode, "add");
  assert.equal(Fuzzy.parseQuery("Plug-Remove: notes").mode, "remove");
  assert.equal(Fuzzy.parseQuery("Plug-Enable: local").mode, "enable");
  assert.equal(Fuzzy.parseQuery("Plug-Disable: local").mode, "disable");
  assert.equal(Fuzzy.parseQuery("Plug-Update: local").mode, "update");
});

test("install command remains an add alias", () => {
  assert.equal(Fuzzy.parseQuery("plug-install: weather").mode, "add");
  assert.deepEqual(Fuzzy.search(records, "plug-install: weather", 50)
    .results.map((row) => row.id), ["io.example.weather"]);
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
  const add = Fuzzy.search(records, "plug-ad", 50);
  assert.equal(add.mode, "command");
  assert.deepEqual(add.results.map((row) => row.commandCompletion),
    ["plug-add: "]);

  const remove = Fuzzy.search(records, "plug-rm", 50);
  assert.equal(remove.mode, "command");
  assert.deepEqual(remove.results.map((row) => row.commandCompletion),
    ["plug-remove: "]);

  const enable = Fuzzy.search(records, "plug-en", 50);
  assert.deepEqual(enable.results.map((row) => row.commandCompletion),
    ["plug-enable: "]);

  const disable = Fuzzy.search(records, "plug-dis", 50);
  assert.deepEqual(disable.results.map((row) => row.commandCompletion),
    ["plug-disable: "]);
});

test("command-shaped selection is fuzzy and keeps add first", () => {
  for (const query of ["plg-ad"]) {
    const result = Fuzzy.search(records, query, 50);
    assert.equal(result.mode, "command");
    assert.deepEqual(result.results.map((row) => row.commandCompletion),
      ["plug-add: "]);
  }
  assert.deepEqual(Fuzzy.search(records, "plug", 50)
    .results.map((row) => row.commandCompletion),
    ["plug-add: ", "plug-remove: ", "plug-enable: ", "plug-disable: ",
      "plug-update: "]);
  assert.deepEqual(Fuzzy.search(records, "plug", 1)
    .results.map((row) => row.commandCompletion), ["plug-add: "]);
});

test("operation intent promotes commands above browse results", () => {
  for (const query of ["a", "ad"]) {
    const result = Fuzzy.search(records, query, 50);
    assert.equal(result.mode, "browse");
    assert.equal(result.results[0].commandCompletion, "plug-add: ");
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
  const result = Fuzzy.search(records, "plug-add", 50);
  assert.equal(result.mode, "command");
  assert.equal(result.results[0].commandCompletion, "plug-add: ");
});

test("malformed colon input is inert", () => {
  for (const query of ["plug-adx:", "plug-unknown:", "weather:"]) {
    const result = Fuzzy.search(records, query, 50);
    assert.equal(result.mode, "command");
    assert.deepEqual(result.results, []);
  }
});

test("add mode limits candidates", () => {
  const result = Fuzzy.search(records, "plug-add: weather", 50);
  assert.deepEqual(result.results.map((row) => row.id), ["io.example.weather"]);
});

test("remove mode includes removable self", () => {
  const result = Fuzzy.search(records, "plug-remove: ", 50);
  assert.deepEqual(result.results.map((row) => row.id),
    ["local.notes", SELF_ID]);
});

test("enable and disable modes follow runtime switchability", () => {
  assert.deepEqual(Fuzzy.search(records, "plug-enable: ", 50)
    .results.map((row) => row.id), ["local.disabled"]);
  assert.deepEqual(Fuzzy.search(records, "plug-disable: ", 50)
    .results.map((row) => row.id), ["omarchy.clock", "local.notes"]);
});

test("update mode contains only checked fast-forward candidates", () => {
  assert.deepEqual(Fuzzy.search(records, "plug-update: ", 50)
    .results.map((row) => row.id), ["local.notes"]);
  assert.deepEqual(Fuzzy.search(records, "plug-upd", 50)
    .results.map((row) => row.commandCompletion), ["plug-update: "]);
});

test("update results follow action-driven record state", () => {
  const candidate = {
    id: "local.lifecycle",
    name: "Lifecycle",
    installed: true,
    builtIn: false,
    enabled: true,
    canDisable: true,
    removable: true,
    updateAvailable: true,
    updateStatus: "available"
  };
  function ids(record) {
    return Fuzzy.search([record], "plug-update: ", 50).results
      .map((row) => row.id);
  }

  assert.deepEqual(ids(candidate), [candidate.id]);
  assert.deepEqual(ids({ ...candidate, enabled: false }), [candidate.id]);
  assert.deepEqual(ids({ ...candidate, updateAvailable: false,
    updateStatus: "current" }), []);
  assert.deepEqual(ids({ ...candidate, installed: false }), []);
  assert.deepEqual(ids({ ...candidate, updateAvailable: true,
    updateStatus: "error" }), [candidate.id]);
});

test("inactive full bars can be enabled but active bars cannot be disabled", () => {
  const bars = Catalog.prepareRecords([
    { id: "bar.active", name: "Active", builtIn: true,
      fullBar: true, enabled: true, canDisable: false },
    { id: "bar.inactive", name: "Inactive", builtIn: true,
      fullBar: true, enabled: false, canDisable: false }
  ]);
  assert.deepEqual(Fuzzy.search(bars, "plug-enable: ", 50)
    .results.map((row) => row.id), ["bar.inactive"]);
  assert.deepEqual(Fuzzy.search(bars, "plug-disable: ", 50).results, []);
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

test("marketplace metrics remain optional and retain honest counts", () => {
  const values = Catalog.prepareRecords([{
    id: "x.metrics",
    marketplaceListed: true,
    metricsAvailable: true,
    stars: 12,
    verificationStatus: "verified",
    views: 34,
    copies: 5,
    hearts: 6,
    tags: ["shell"]
  }, {
    id: "x.no-metrics",
    marketplaceListed: true,
    views: 0,
    copies: 0,
    hearts: 0
  }]);
  assert.equal(values[0].stars, 12);
  assert.equal(values[0].views, 34);
  assert.equal(values[0].copies, 5);
  assert.equal(values[0].hearts, 6);
  assert.equal(values[1].metricsAvailable, false);
  assert.equal(values[1].views, null);
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

test("runtime switchability must be explicitly true", () => {
  const values = Catalog.prepareRecords([
    { id: "x.yes", canDisable: true },
    { id: "x.no", canDisable: false },
    { id: "x.missing" }
  ]);
  assert.equal(values[0].canDisable, true);
  assert.equal(values[1].canDisable, false);
  assert.equal(values[2].canDisable, false);
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

test("shared action model follows every plugin state", () => {
  function labels(record, readOnly) {
    return Palette.actionOptions(record, readOnly)
      .map((option) => option.label);
  }

  assert.deepEqual(labels({ id: "builtin.on", builtIn: true, enabled: true,
    canDisable: true }), ["Cancel", "Disable"]);
  assert.deepEqual(labels({ id: "builtin.off", builtIn: true, enabled: false,
    canDisable: true }), ["Cancel", "Enable"]);
  assert.deepEqual(labels({ id: "user.available", installable: true }),
    ["Cancel", "Add"]);
  assert.deepEqual(labels({ id: "user.on", installed: true, enabled: true,
    canDisable: true, removable: true, updateStatus: "unknown" }),
  ["Cancel", "Update", "Disable", "Remove"]);
  assert.deepEqual(labels({ id: "user.off", installed: true, enabled: false,
    canDisable: true, removable: true, updateStatus: "current" }),
  ["Cancel", "Update", "Enable", "Remove"]);
  assert.deepEqual(labels({ id: "bar.on", builtIn: true,
    fullBar: true, enabled: true }),
    ["Cancel"]);
  assert.deepEqual(labels({ id: "bar.off", builtIn: true,
    fullBar: true, enabled: false }),
    ["Cancel", "Enable"]);
  assert.deepEqual(labels({ id: "x.info" }, true), ["Close"]);
});

test("unavailable Update remains present with its explanation", () => {
  const manual = Palette.actionOptions({
    id: "manual.plugin",
    installed: true,
    removable: true,
    updateStatus: "manual",
    updateReason: "Manually copied/installed plugin. No Git repository to update."
  }, false)[1];
  assert.equal(manual.label, "Update");
  assert.equal(manual.available, false);
  assert.equal(manual.reason,
    "Manually copied/installed plugin. No Git repository to update.");

  for (const status of ["dirty", "ahead", "diverged", "unsupported",
    "error"])
    assert.equal(Palette.actionOptions({ id: "blocked." + status,
      installed: true,
      updateStatus: status, updateReason: status }, false)[1].available,
    false);
});
