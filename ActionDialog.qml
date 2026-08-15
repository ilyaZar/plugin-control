import QtQuick
import qs.Commons
import qs.Ui

FocusScope {
  id: root

  property bool opened: false
  property var plugin: null
  property string operation: "browse"
  property bool busy: false
  property bool installInTerminal: false
  property int selectedChoice: 0
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color warningColor: Color.urgent
  property string fontFamily: Style.font.menuFamily

  readonly property bool dirtyBlocked: plugin && plugin.dirty === true
    && operation === "remove"
  readonly property bool terminalAllowed: operation === "install"
    && String(plugin && plugin.repository || "").length > 0
    && String(plugin && plugin.source || "") !== "submission"
  readonly property bool terminalInstall: terminalAllowed && installInTerminal
  readonly property bool mutating: ["install", "remove", "enable", "disable",
    "add-bar"].indexOf(operation) >= 0
  readonly property bool canConfirm: mutating && !busy && !dirtyBlocked
  readonly property string reviewedCommit: String(plugin
    && (plugin.commit || plugin.listingValidatedCommit) || "")
  readonly property string title: {
    if (operation === "install") return "Install and enable plugin?"
    if (operation === "remove") return "Remove plugin?"
    if (operation === "enable") return "Enable built-in plugin?"
    if (operation === "disable") return "Disable built-in plugin?"
    if (operation === "add-bar") return "Add built-in widget to bar?"
    return "Plugin details"
  }
  readonly property string confirmLabel: {
    if (operation === "install")
      return terminalInstall ? "Open terminal" : "Install"
    if (operation === "remove") return "Remove"
    if (operation === "enable") return "Enable"
    if (operation === "disable") return "Disable"
    if (operation === "add-bar") return "Add to bar"
    return "Close"
  }
  readonly property string operationText: {
    if (operation === "install") return terminalInstall
      ? "omarchy plugin add <repository> --enable"
      : "omarchy plugin add <repository> --enable --yes"
    if (operation === "remove") return "omarchy plugin remove "
      + String(plugin && plugin.id || "") + " --yes"
    if (operation === "enable") return "omarchy plugin enable "
      + String(plugin && plugin.id || "")
    if (operation === "disable") return "omarchy plugin disable "
      + String(plugin && plugin.id || "")
    if (operation === "add-bar") return "omarchy bar put "
      + String(plugin && plugin.id || "")
    return "No system change"
  }

  signal confirmed()
  signal canceled()
  signal terminalInstallToggled(bool enabled)

  function openDialog() {
    selectedChoice = 0
    opened = true
    Qt.callLater(forceActiveFocus)
  }

  function closeDialog() {
    opened = false
  }

  function handleKey(event) {
    if (!opened) return false
    if (event.key === Qt.Key_Escape) {
      canceled()
      return true
    }
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
        || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      if (canConfirm) selectedChoice = selectedChoice === 0 ? 1 : 0
      return true
    }
    if (event.key === Qt.Key_T && terminalAllowed && !busy) {
      terminalInstallToggled(!installInTerminal)
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space) {
      if (selectedChoice === 1 && canConfirm) confirmed()
      else canceled()
      return true
    }
    return true
  }

  visible: opened
  focus: opened

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (root.handleKey(event)) event.accepted = true
  }

  Rectangle {
    anchors.fill: parent
    color: root.background
    radius: Style.cornerRadius

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.spacing.sm

      Text {
        width: parent.width
        text: root.title
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: String(root.plugin && root.plugin.name || "") + "  "
          + String(root.plugin && root.plugin.id || "")
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: "Author: " + String(root.plugin && root.plugin.author || "Unknown")
          + "    Version: " + String(root.plugin && root.plugin.version || "Unknown")
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: "Source: " + String(root.plugin && root.plugin.sourceLabel || "Unknown")
          + "    Trust: " + (String(root.plugin && root.plugin.warning || "") || "No catalog warning")
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: "Repository: " + String(root.plugin && root.plugin.repository || "Not supplied")
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }

      Text {
        visible: root.reviewedCommit.length > 0
        width: parent.width
        text: "Reviewed commit: " + root.reviewedCommit
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }

      Item {
        visible: root.terminalAllowed
        width: parent.width
        height: visible ? Style.space(30) : 0

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Run in Omarchy terminal  (T)"
          textFormat: Text.PlainText
          color: root.installInTerminal ? root.foreground : Color.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        ToggleSwitch {
          id: terminalToggle
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          trackHeight: Style.space(18)
          cursorPad: Style.space(3)
          checked: root.installInTerminal
          foreground: root.foreground
          onToggled: root.terminalInstallToggled(!checked)

          PanelToolTip {
            visible: terminalToggle.containsMouse
            text: root.installInTerminal
              ? "Use the faster background installer"
              : "Stream output and use native interactive prompts"
            fontFamily: root.fontFamily
          }
        }
      }

      Rectangle {
        width: parent.width
        height: Style.space(root.operation === "install" ? 52 : 38)
        radius: Style.cornerRadius
        color: Util.alpha(root.operation === "install"
          ? root.warningColor : root.foreground, 0.10)

        Text {
          anchors.fill: parent
          anchors.margins: Style.spacing.sm
          text: root.operation === "install"
            ? "Plugins run unsandboxed inside the long-running shell. "
              + "Marketplace validation is not a security audit.\n"
              + root.operationText
            : root.operationText
          textFormat: Text.PlainText
          color: root.operation === "install" ? root.warningColor : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
          elide: Text.ElideRight
        }
      }

      Text {
        visible: root.dirtyBlocked
        width: parent.width
        text: "Removal is blocked because this Git checkout has local changes. Commit, stash, or discard them first."
        textFormat: Text.PlainText
        color: root.warningColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }

      Item {
        width: parent.width
        height: Math.max(0, parent.height - y - Style.space(42))
      }

      Row {
        width: parent.width
        height: Style.space(38)
        spacing: Style.spacing.sm

        Rectangle {
          width: root.canConfirm ? (parent.width - parent.spacing) / 2 : parent.width
          height: parent.height
          radius: Style.cornerRadius
          color: root.selectedChoice === 0
            ? root.selectedBackground : "transparent"

          Text {
            anchors.centerIn: parent
            text: root.mutating ? "Cancel" : "Close"
            color: root.selectedChoice === 0
              ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.selectedChoice = 0
            onClicked: root.canceled()
          }
        }

        Rectangle {
          visible: root.canConfirm
          width: visible ? (parent.width - parent.spacing) / 2 : 0
          height: parent.height
          radius: Style.cornerRadius
          color: root.selectedChoice === 1
            ? root.selectedBackground : "transparent"

          Text {
            anchors.centerIn: parent
            text: root.busy ? "Working..." : root.confirmLabel
            color: root.selectedChoice === 1
              ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
          MouseArea {
            anchors.fill: parent
            enabled: root.canConfirm
            hoverEnabled: true
            onEntered: root.selectedChoice = 1
            onClicked: root.confirmed()
          }
        }
      }
    }
  }
}
