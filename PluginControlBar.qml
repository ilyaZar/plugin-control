import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.ilyazar.plugin-control"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function openPalette() {
    if (root.bar && root.bar.shell
        && typeof root.bar.shell.toggle === "function") {
      root.bar.shell.toggle(root.moduleName, "{}")
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰏖"
    tooltipText: "Plugin Control"
    active: root.bar && root.bar.shell
      && typeof root.bar.shell.isPluginOpen === "function"
      && root.bar.shell.isPluginOpen(root.moduleName)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.openPalette()
    }
  }
}
