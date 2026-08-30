import QtQuick
import QtTest
import ".."

TestCase {
  id: testCase

  name: "PaletteResultRow"
  width: 760
  height: 180
  visible: true
  when: windowShown

  readonly property string repositoryUrl:
    "https://github.com/alice/weather"
  property var row: null

  Component {
    id: rowComponent

    PaletteResultRow {
      width: 700
      index: 0
      pluginName: "Weather"
      pluginId: "io.example.weather"
      description: "Forecast in the bar"
      author: "Alice"
      kind: "Bar widget"
      stateLabel: "Available"
      sourceLabel: "Marketplace listed"
      warning: ""
      version: "1.0.0"
      releaseTag: ""
      repository: testCase.repositoryUrl
      separatorBefore: false
      dangerous: false
    }
  }

  SignalSpy {
    id: activatedSpy
    signalName: "activated"
  }

  SignalSpy {
    id: repositorySpy
    signalName: "repositoryRequested"
  }

  function descendants(parent) {
    var values = []
    var children = parent && parent.children ? parent.children : []
    for (var index = 0; index < children.length; index++) {
      var child = children[index]
      values.push(child)
      var nested = descendants(child)
      for (var nestedIndex = 0; nestedIndex < nested.length; nestedIndex++)
        values.push(nested[nestedIndex])
    }
    return values
  }

  function textItem(value) {
    var items = descendants(row)
    for (var index = 0; index < items.length; index++) {
      if (items[index].text !== undefined
          && String(items[index].text) === value)
        return items[index]
    }
    return null
  }

  function visibleText(value) {
    var item = textItem(value)
    return item && item.visible
  }

  function init() {
    row = createTemporaryObject(rowComponent, testCase)
    verify(row)
    activatedSpy.target = row
    repositorySpy.target = row
    activatedSpy.clear()
    repositorySpy.clear()
    waitForRendering(row)
  }

  function cleanup() {
    activatedSpy.target = null
    repositorySpy.target = null
    if (row) row.destroy()
    row = null
  }

  function test_twoLinePresentation() {
    var name = textItem("Weather")
    var repository = textItem("alice/weather")
    var description = textItem("Forecast in the bar")
    verify(name)
    verify(repository)
    verify(description)
    verify(repository.visible)
    verify(!visibleText("io.example.weather"))
    verify(!visibleText("Alice"))
    verify(repository.font.pixelSize < name.font.pixelSize)

    var namePoint = name.mapToItem(row, 0, 0)
    var repositoryPoint = repository.mapToItem(row, 0, 0)
    var descriptionPoint = description.mapToItem(row, 0, 0)
    verify(repositoryPoint.x > namePoint.x)
    verify(Math.abs(repositoryPoint.y + repository.height / 2
      - (namePoint.y + name.height / 2)) < 1)
    verify(descriptionPoint.y > namePoint.y)
  }

  function test_repositoryLinkOwnsItsClick() {
    var repository = textItem("alice/weather")
    verify(repository)
    mouseClick(repository, Math.floor(repository.width / 2),
      Math.floor(repository.height / 2), Qt.LeftButton)
    compare(repositorySpy.count, 1)
    compare(repositorySpy.signalArguments[0][0], repositoryUrl)
    compare(activatedSpy.count, 0)
  }

  function test_descriptionActivatesRow() {
    var description = textItem("Forecast in the bar")
    verify(description)
    mouseClick(description, Math.floor(description.width / 2),
      Math.floor(description.height / 2), Qt.LeftButton)
    compare(activatedSpy.count, 1)
    compare(repositorySpy.count, 0)
  }

  function test_rightClickIsInert() {
    var repository = textItem("alice/weather")
    verify(repository)
    mouseClick(repository, Math.floor(repository.width / 2),
      Math.floor(repository.height / 2), Qt.RightButton)
    compare(repositorySpy.count, 0)
    compare(activatedSpy.count, 0)
  }

  function test_missingRepositoryLeavesNameRoom() {
    row.repository = ""
    waitForRendering(row)
    var name = textItem("Weather")
    verify(name)
    compare(name.width, name.implicitWidth)
    verify(!visibleText("alice/weather"))
  }

  function test_settingsRowsStayTextOnly() {
    row.settingsMenuOpen = true
    waitForRendering(row)
    verify(!visibleText("alice/weather"))
    verify(visibleText("Forecast in the bar"))
    verify(!visibleText("Alice"))
    verify(!visibleText("io.example.weather"))

    row.description = ""
    waitForRendering(row)
    verify(!visibleText("Bar widget"))
  }

  function test_descriptionFallsBackToKind() {
    row.description = ""
    waitForRendering(row)
    verify(visibleText("Bar widget"))
    verify(!visibleText("Alice"))
  }

  function test_narrowRowsKeepBothTitleItems() {
    row.width = 320
    row.pluginName = "A weather plugin with a deliberately long name"
    row.repository =
      "https://github.com/a-very-long-creator/weather-plugin-repository"
    waitForRendering(row)
    var name = textItem(row.pluginName)
    var repository = textItem(
      "a-very-long-creator/weather-plugin-repository")
    verify(name.width > 0)
    verify(repository.width > 0)
    verify(String(repository.text).indexOf("https://") !== 0)
    verify(name.x + name.width <= repository.x)
    verify(repository.x + repository.width <= repository.parent.width)
  }
}
