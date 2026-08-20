import QtQuick
import QtTest
import "../Fuzzy.js" as Fuzzy
import "../CatalogModel.js" as Catalog

TestCase {
  name: "PluginControlModels"

  function test_parser() {
    compare(Fuzzy.parseQuery("plug-add: weather").mode, "add")
    compare(Fuzzy.parseQuery("plug-remove : local").query, "local")
    compare(Fuzzy.parseQuery("plug-enable: local").mode, "enable")
    compare(Fuzzy.parseQuery("plug-disable: local").mode, "disable")
    compare(Fuzzy.parseQuery("plug-update: local").mode, "update")
  }

  function test_qml_search() {
    var records = Catalog.prepareRecords([
      { id: "x.weather", name: "Weather", source: "marketplace",
        installable: true },
      { id: "x.local", name: "Local", source: "local",
        installed: true, enabled: true, canDisable: true, removable: true,
        updateAvailable: true },
      { id: "x.disabled", name: "Disabled", source: "local",
        installed: true, enabled: false, canDisable: true }
    ])
    compare(Fuzzy.search(records, "plug-add: weather", 50)
      .results[0].id, "x.weather")
    compare(Fuzzy.search(records, "plug-remove: local", 50)
      .results[0].id, "x.local")
    compare(Fuzzy.search(records, "plug-ad", 50)
      .results[0].commandCompletion, "plug-add: ")
    compare(Fuzzy.search(records, "plg-ad", 50)
      .results[0].commandCompletion, "plug-add: ")
    compare(Fuzzy.search(records, "rem", 50)
      .results[0].commandCompletion, "plug-remove: ")
    compare(Fuzzy.search(records, "plug-enable: disabled", 50)
      .results[0].id, "x.disabled")
    compare(Fuzzy.search(records, "plug-disable: local", 50)
      .results[0].id, "x.local")
    compare(Fuzzy.search(records, "plug-update: local", 50)
      .results[0].id, "x.local")
    compare(Fuzzy.search(records, "weather:", 50).results.length, 0)
  }
}
