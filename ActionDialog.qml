import QtQuick
import qs.Commons
import qs.Ui
import "PaletteViewModel.js" as PaletteViewModel

FocusScope {
  id: root

  property bool opened: false
  property var plugin: null
  property string selfId: ""
  property bool readOnly: false
  property bool busy: false
  property bool installInTerminal: false
  property int selectedChoice: 0
  property string helpText: ""
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color warningColor: Color.urgent
  property string fontFamily: Style.font.menuFamily

  readonly property var actions: PaletteViewModel.actionOptions(plugin, readOnly)
  readonly property var selectedAction: selectedChoice >= 0
    && selectedChoice < actions.length ? actions[selectedChoice] : null
  readonly property bool helpDelayRunning: helpDelay.running
  readonly property string selectedOperation: String(
    selectedAction && selectedAction.operation || "cancel")
  readonly property bool terminalAllowed: !readOnly && plugin
    && plugin.installable === true
    && String(plugin.repository || "").length > 0
    && String(plugin.source || "") !== "submission"
  readonly property bool terminalInstall: terminalAllowed && installInTerminal
  readonly property string reviewedCommit: String(plugin
    && (plugin.commit || plugin.listingValidatedCommit) || "")
  readonly property bool marketplaceListed: plugin
    && plugin.marketplaceListed === true
  readonly property bool listedUserPlugin: marketplaceListed
    && plugin.builtIn !== true
  readonly property bool metricsAvailable: marketplaceListed
    && plugin.metricsAvailable === true
  readonly property string verificationStatus: String(plugin
    && plugin.verificationStatus || "")
  readonly property string verificationHelp: verificationStatus === "verified"
    ? "Verified means automated or maintainer checks were associated with "
      + "the listed commit. It is not a security audit."
    : "Unverified means there is no current verification. It does not mean "
      + "the plugin is malicious."
  readonly property string operationText: {
    var id = String(plugin && plugin.id || "")
    if (selectedOperation === "add") return terminalInstall
      ? "omarchy plugin add <repository> --enable"
      : "omarchy plugin add <repository> --enable --yes"
    if (selectedOperation === "remove")
      return "omarchy plugin remove " + id + " --yes"
    if (selectedOperation === "update")
      return "omarchy plugin update " + id + " --yes"
    if (selectedOperation === "enable")
      return "omarchy plugin enable " + id
    if (selectedOperation === "disable")
      return "omarchy plugin disable " + id
    return "No system change"
  }
  readonly property bool selectedMutates: ["add", "remove", "update",
    "enable", "disable"].indexOf(selectedOperation) >= 0

  signal actionRequested(string operation)
  signal canceled()
  signal terminalInstallToggled(bool enabled)

  function openDialog() {
    selectedChoice = 0
    helpText = ""
    helpDelay.stop()
    opened = true
    Qt.callLater(forceActiveFocus)
  }

  function closeDialog() {
    helpDelay.stop()
    helpText = ""
    opened = false
  }

  function selectChoice(index, immediateHelp) {
    if (index < 0 || index >= actions.length) return
    selectedChoice = index
    helpDelay.stop()
    helpText = ""
    var action = actions[index]
    if (action.available === false && String(action.reason || "")) {
      if (immediateHelp === true) helpText = String(action.reason)
      else helpDelay.restart()
    }
  }

  function moveChoice(offset) {
    if (actions.length === 0) return
    selectChoice((selectedChoice + offset + actions.length)
      % actions.length, false)
  }

  function choose() {
    var action = selectedAction
    if (!action) return
    if (action.available === false) {
      selectChoice(selectedChoice, true)
      return
    }
    if (action.operation === "cancel" || action.operation === "close") {
      canceled()
      return
    }
    if (!busy) actionRequested(String(action.operation))
  }

  function handleKey(event) {
    if (!opened) return false
    if (event.key === Qt.Key_Escape) {
      canceled()
      return true
    }
    if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
      moveChoice(-1)
      return true
    }
    if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
      moveChoice(1)
      return true
    }
    if (event.key === Qt.Key_T && terminalAllowed && !busy) {
      terminalInstallToggled(!installInTerminal)
      return true
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
        || event.key === Qt.Key_Space) {
      choose()
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

  Timer {
    id: helpDelay
    interval: 1000
    repeat: false
    onTriggered: {
      var action = root.selectedAction
      if (action && action.available === false)
        root.helpText = String(action.reason || "")
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.background
    radius: Style.cornerRadius

    Column {
      anchors.fill: parent
      anchors.margins: Style.spacing.panelPadding
      spacing: Style.space(5)

      Text {
        width: parent.width
        text: root.readOnly ? "Plugin information" : "Plugin actions"
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
        visible: String(root.plugin && root.plugin.description || "").length > 0
        width: parent.width
        text: String(root.plugin && root.plugin.description || "")
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.82
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: "Author: " + String(root.plugin
          && root.plugin.author || "Unknown") + "    Version: "
          + String(root.plugin && root.plugin.version || "Unknown")
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: "Source: " + String(root.plugin
          && root.plugin.sourceLabel || "Unknown")
          + (String(root.plugin && root.plugin.warning || "")
            ? "    Warning: " + String(root.plugin.warning) : "")
        textFormat: Text.PlainText
        color: String(root.plugin && root.plugin.warning || "")
          ? root.warningColor : root.foreground
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: "Repository: " + String(root.plugin
          && root.plugin.repository || "Not supplied")
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

      Text {
        id: verificationText
        visible: root.listedUserPlugin
        width: parent.width
        text: "Marketplace: " + (root.verificationStatus === "verified"
          ? "Verified" : "Unverified")
          + (root.plugin && root.plugin.stars !== null
            ? "    Repository stars: " + root.plugin.stars : "")
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight

        MouseArea {
          id: verificationHover
          anchors.fill: parent
          hoverEnabled: true
        }

        PanelToolTip {
          visible: verificationHover.containsMouse
          text: root.verificationHelp
          fontFamily: root.fontFamily
        }
      }

      Text {
        visible: root.metricsAvailable
        width: parent.width
        text: root.plugin
          ? "Marketplace interactions: Views " + root.plugin.views
            + "    Command copies " + root.plugin.copies
            + "    Anonymous hearts " + root.plugin.hearts
          : ""
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.72
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        visible: root.marketplaceListed && !root.metricsAvailable
        width: parent.width
        text: "Marketplace interaction totals are not cached yet"
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.58
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        visible: !root.marketplaceListed
        width: parent.width
        text: "Not listed on Omarchy Plugins"
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.68
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Flow {
        visible: root.marketplaceListed && root.plugin
          && Array.isArray(root.plugin.tags) && root.plugin.tags.length > 0
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.plugin && Array.isArray(root.plugin.tags)
            ? root.plugin.tags : []

          delegate: Rectangle {
            required property string modelData
            width: tagText.implicitWidth + Style.spacing.sm
            height: Style.space(22)
            radius: Style.space(4)
            color: Util.alpha(root.foreground, 0.10)

            Text {
              id: tagText
              anchors.centerIn: parent
              text: modelData
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Item {
        visible: root.terminalAllowed
        width: parent.width
        height: visible ? Style.space(28) : 0

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Run Add in Omarchy terminal  (T)"
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
        visible: root.selectedMutates
        width: parent.width
        height: visible ? Style.space(root.selectedOperation === "add"
          ? 48 : 34) : 0
        radius: Style.cornerRadius
        color: Util.alpha(root.selectedOperation === "add"
          ? root.warningColor : root.foreground, 0.10)

        Text {
          anchors.fill: parent
          anchors.margins: Style.spacing.sm
          text: root.selectedOperation === "add"
            ? "Plugins run unsandboxed. Marketplace checks are not a "
              + "security audit.\n" + root.operationText
            : root.operationText
          textFormat: Text.PlainText
          color: root.selectedOperation === "add"
            ? root.warningColor : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
          elide: Text.ElideRight
        }
      }

      Rectangle {
        visible: root.helpText.length > 0
        width: parent.width
        height: visible ? Style.space(42) : 0
        radius: Style.cornerRadius
        color: Util.alpha(root.warningColor, 0.12)

        Text {
          anchors.fill: parent
          anchors.margins: Style.spacing.sm
          text: root.helpText
          textFormat: Text.PlainText
          color: root.warningColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
          elide: Text.ElideRight
        }
      }

      Item {
        width: parent.width
        height: Math.max(0, parent.height - y - Style.space(42))
      }

      Row {
        id: actionRow
        width: parent.width
        height: Style.space(38)
        spacing: Style.spacing.sm

        Repeater {
          model: root.actions

          delegate: Rectangle {
            id: actionButton
            required property var modelData
            required property int index
            width: (actionRow.width - actionRow.spacing
              * Math.max(0, root.actions.length - 1))
              / Math.max(1, root.actions.length)
            height: parent.height
            radius: Style.cornerRadius
            color: root.selectedChoice === index
              ? root.selectedBackground : "transparent"
            opacity: modelData.available === false
              && root.selectedChoice !== index ? 0.42 : 1

            Text {
              anchors.centerIn: parent
              text: root.busy && root.selectedChoice === actionButton.index
                && actionButton.modelData.operation !== "cancel"
                && actionButton.modelData.operation !== "close"
                ? "Working..." : actionButton.modelData.label
              color: root.selectedChoice === actionButton.index
                ? root.selectedText
                : (actionButton.modelData.dangerous === true
                  ? root.warningColor : root.foreground)
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectChoice(actionButton.index, false)
              onClicked: {
                root.selectChoice(actionButton.index,
                  actionButton.modelData.available === false)
                root.choose()
              }
            }
          }
        }
      }
    }
  }
}
