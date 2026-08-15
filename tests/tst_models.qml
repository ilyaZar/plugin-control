import QtQuick
import QtTest
import "../Fuzzy.js" as Fuzzy
import "../CatalogModel.js" as Catalog

TestCase {
  name: "PluginControlModels"

  function test_parser() {
    compare(Fuzzy.parseQuery("plug-install: weather").mode, "install")
    compare(Fuzzy.parseQuery("plug-remove : local").query, "local")
  }

  function test_qml_search() {
    var records = Catalog.prepareRecords([
      { id: "x.weather", name: "Weather", source: "marketplace",
        installable: true },
      { id: "x.local", name: "Local", source: "local",
        installed: true, removable: true }
    ])
    compare(Fuzzy.search(records, "plug-install: weather", 50)
      .results[0].id, "x.weather")
    compare(Fuzzy.search(records, "plug-remove: local", 50)
      .results[0].id, "x.local")
    compare(Fuzzy.search(records, "plug-in", 50)
      .results[0].commandCompletion, "plug-install: ")
    compare(Fuzzy.search(records, "plg-in", 50)
      .results[0].commandCompletion, "plug-install: ")
    compare(Fuzzy.search(records, "rem", 50)
      .results[0].commandCompletion, "plug-remove: ")
    compare(Fuzzy.search(records, "weather:", 50).results.length, 0)
  }
}
