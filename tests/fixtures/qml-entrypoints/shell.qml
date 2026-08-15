import QtQuick
import Quickshell

ShellRoot {
  id: root

  readonly property string sourceDir:
    Quickshell.env("PLUGIN_CONTROL_SOURCE_DIR")
  property var createdObjects: []
  property var serviceObject: null

  function manifestData() {
    return {
      schemaVersion: 1,
      id: "io.github.ilyazar.plugin-control",
      name: "Plugin Control",
      version: "test",
      kinds: ["service", "overlay", "bar-widget"],
      entryPoints: {
        service: "Service.qml",
        overlay: "PluginControl.qml",
        barWidget: "PluginControlBar.qml"
      },
      __sourceDir: sourceDir
    }
  }

  function loadEntry(fileName, kind) {
    var url = encodeURI("file://" + sourceDir + "/" + fileName)
    var component = Qt.createComponent(url, Component.PreferSynchronous)
    if (component.status !== Component.Ready) {
      console.error("PLUGIN_CONTROL_LOAD_ERROR " + kind + ": "
        + component.errorString())
      return null
    }
    var object = component.createObject(host)
    if (!object) {
      console.error("PLUGIN_CONTROL_CREATE_ERROR " + kind + ": "
        + component.errorString())
      return null
    }
    if ("manifest" in object) object.manifest = manifestData()
    if ("shell" in object) object.shell = mockShell
    createdObjects.push(object)
    console.log("PLUGIN_CONTROL_LOAD_OK " + kind)
    return object
  }

  Item { id: host }

  QtObject {
    id: mockBar
    property string position: "top"
    property bool barHidden: false
    property bool vertical: false
    property int barSize: 32
    property string fontFamily: "JetBrainsMono Nerd Font"
    property color barForeground: "white"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    property var shell: mockShell
    function showTooltip(item, text) {}
    function hideTooltip(item) {}
    function registerClickTarget(item) {}
    function unregisterClickTarget(item) {}
  }

  QtObject {
    id: mockShell
    property var bar: mockBar
    property string lastToggleId: ""
    property string lastTogglePayload: ""
    function hide(pluginId) { return true }
    function isPluginOpen(pluginId) { return false }
    function toggle(pluginId, payloadJson) {
      lastToggleId = pluginId
      lastTogglePayload = payloadJson
    }
  }

  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: {
      root.serviceObject = root.loadEntry("Service.qml", "service")
      var overlay = root.loadEntry("PluginControl.qml", "overlay")
      if (overlay && "service" in overlay) overlay.service = root.serviceObject
      var barWidget = root.loadEntry("PluginControlBar.qml", "bar-widget")
      if (barWidget) {
        barWidget.bar = mockBar
        barWidget.openPalette()
        if (mockShell.lastToggleId
            !== "io.github.ilyazar.plugin-control"
            || mockShell.lastTogglePayload !== "{}") {
          console.error("PLUGIN_CONTROL_LOAD_ERROR bar-widget command")
        }
      }
      Qt.callLater(Qt.quit)
    }
  }
}
