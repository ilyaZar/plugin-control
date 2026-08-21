import QtQuick
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
  readonly property bool trayIconHidden:
    setting("trayIconHidden", false) === true

  visible: !trayIconHidden
  implicitWidth: trayIconHidden ? 0 : button.implicitWidth
  implicitHeight: trayIconHidden ? 0 : button.implicitHeight

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
    if (root.bar && root.bar.shell
        && typeof root.bar.shell.toggle === "function") {
      root.bar.shell.toggle(root.moduleName, '{"settings":true}')
    }
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
    padding: Style.spacing.xl
    contentWidth: settingsPopup.fittedContentWidth(Style.space(144))
    contentHeight: settingsPopup.fittedContentHeight(settingsColumn.implicitHeight)

    Column {
      id: settingsColumn
      anchors.fill: parent
      spacing: Style.space(4)

      Button {
        id: settingsButton
        width: parent.width
        text: "Settings"
        leftAlign: false
        verticalPadding: Style.spacing.sm
        onClicked: root.openSettings()
      }

    }
  }
}
