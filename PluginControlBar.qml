import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.ilyazar.plugin-control"

  property bool settingsMenuOpen: false
  readonly property var service: root.bar && root.bar.shell
    && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor(root.moduleName) : null
  readonly property bool actionFailed: root.service && root.service.actionState
    && root.service.actionState.ok === false
    && root.service.actionState.acknowledged === false
  readonly property var pluginMetadata: root.bar
    && root.bar.barWidgetRegistry
    && typeof root.bar.barWidgetRegistry.metadataFor === "function"
    ? root.bar.barWidgetRegistry.metadataFor(root.moduleName) : null
  readonly property string sourceDir: String(root.pluginMetadata
    && root.pluginMetadata.sourceDir || "")

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function openPalette() {
    if (root.bar && root.bar.shell
        && typeof root.bar.shell.toggle === "function") {
      root.bar.shell.toggle(root.moduleName, "{}")
    }
  }

  function close() {
    settingsMenuOpen = false
  }

  function openSettings() {
    close()
    if (!sourceDir) return
    Quickshell.execDetached([sourceDir + "/scripts/open-settings.sh", sourceDir])
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏖"
    tooltipText: "Plugin Control"
    // Keep red bounded to the failed-action notice, not the palette lifetime.
    active: root.actionFailed
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.openPalette()
      else if (buttonCode === Qt.RightButton)
        root.settingsMenuOpen = !root.settingsMenuOpen
    }
  }

  PopupCard {
    id: settingsPopup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.settingsMenuOpen
    contentWidth: settingsPopup.fittedContentWidth(Style.space(160))
    contentHeight: settingsPopup.fittedContentHeight(settingsButton.implicitHeight)

    Button {
      id: settingsButton
      anchors.fill: parent
      text: "Settings"
      leftAlign: true
      onClicked: root.openSettings()
    }
  }
}
