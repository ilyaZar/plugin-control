import QtQuick
import qs.Commons
import qs.Ui
import "CatalogModel.js" as CatalogModel
import "PaletteViewModel.js" as PaletteViewModel

FocusScope {
  id: root

  property bool opened: false
  property var plugin: null
  property string selfId: ""
  property bool readOnly: false
  property bool busy: false
  property bool installInTerminal: false
  property bool previewLoading: false
  property bool previewFailed: false
  property string previewCardSource: ""
  property string previewDetailSource: ""
  property int selectedChoice: 0
  property string helpText: ""
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color warningColor: Color.urgent
  property string fontFamily: Style.font.menuFamily
  readonly property color marketplaceOrange: "#ff5a36"
  readonly property color marketplaceGreen: "#b4c96f"
  readonly property color marketplaceYellow: "#ffb000"

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
  readonly property string activityState: CatalogModel.activityState(
    plugin, Date.now())
  readonly property bool starsAvailable: root.listedUserPlugin && plugin
    && plugin.stars !== null && plugin.stars !== undefined
  readonly property string previewImageUrl: String(plugin
    && plugin.previewImageUrl || "")
  readonly property string previewThumbnailUrl: String(plugin
    && plugin.previewThumbnailUrl || previewImageUrl)
  readonly property int previewWidth: Number(plugin
    && plugin.previewWidth || 0)
  readonly property int previewHeight: Number(plugin
    && plugin.previewHeight || 0)
  readonly property bool hasPreview: readOnly
    && previewImageUrl.length > 0 && previewThumbnailUrl.length > 0
  readonly property bool previewReady: hasPreview
    && previewCardSource.length > 0 && previewDetailSource.length > 0
  readonly property int preferredReadOnlyHeight:
    Style.spacing.panelPadding * 2 + contentColumn.implicitHeight
      + Style.space(7) + Style.space(38)
  readonly property var badgeItems: {
    var values = []
    if (activityState === "updated") values.push({
      label: "UPDATED", color: marketplaceYellow, tooltip: "Version updated "
        + "within the last 12 hours"
    })
    else if (activityState === "new") values.push({
      label: "NEW", color: marketplaceGreen, tooltip: "Listed within the "
        + "last 12 hours"
    })
    if (listedUserPlugin) values.push({
      label: verificationStatus === "verified" ? "VERIFIED" : "UNVERIFIED",
      color: verificationStatus === "verified"
        ? marketplaceGreen : marketplaceOrange,
      tooltip: verificationHelp
    })
    return values
  }
  readonly property var metricItems: {
    var values = []
    if (starsAvailable) values.push({
      label: "stars", icon: "\uf005", value: CatalogModel.formatCount(
        plugin.stars), color: marketplaceYellow,
      tooltip: "GitHub repository stars"
    })
    if (metricsAvailable && plugin) {
      values.push({ label: "views", icon: "\uf441",
        value: CatalogModel.formatCount(plugin.views),
        color: marketplaceOrange, tooltip: "Marketplace detail views" })
      values.push({ label: "copies", icon: "\uf0c5",
        value: CatalogModel.formatCount(plugin.copies),
        color: marketplaceOrange, tooltip: "Successful command copies" })
      values.push({ label: "hearts", icon: "\uf004",
        value: CatalogModel.formatCount(plugin.hearts),
        color: marketplaceOrange, tooltip: "Anonymous marketplace hearts" })
    }
    return values
  }
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
  signal previewRequested(string url, string name, int width, int height)
  signal terminalInstallToggled(bool enabled)

  function openDialog() {
    selectedChoice = 0
    helpText = ""
    helpDelay.stop()
    contentFlick.contentY = 0
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
    if (readOnly) {
      canceled()
      return
    }
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
    if (event.key === Qt.Key_Escape
        || (readOnly && event.modifiers === Qt.NoModifier
          && event.key === Qt.Key_Q)) {
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

  function requestPreview() {
    if (!previewReady) return
    previewRequested(previewDetailSource,
      String(plugin && plugin.name || "Plugin preview"),
      previewWidth, previewHeight)
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

    Flickable {
      id: contentFlick
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.bottom: actionRow.top
      anchors.left: parent.left
      anchors.topMargin: Style.spacing.panelPadding
      anchors.rightMargin: Style.spacing.panelPadding
      anchors.bottomMargin: Style.space(7)
      anchors.leftMargin: Style.spacing.panelPadding
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: contentColumn
        width: contentFlick.width
        spacing: Style.space(7)

      Text {
        width: parent.width
        text: root.readOnly ? "PLUGIN INFORMATION" : "PLUGIN ACTIONS"
        textFormat: Text.PlainText
        color: root.marketplaceOrange
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        font.letterSpacing: Style.space(1)
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: String(root.plugin && root.plugin.name || "")
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading + Style.space(2)
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: String(root.plugin && root.plugin.id || "")
        textFormat: Text.PlainText
        color: root.marketplaceOrange
        opacity: 0.88
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        visible: String(root.plugin && root.plugin.description || "").length > 0
        width: parent.width
        text: String(root.plugin && root.plugin.description || "")
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.90
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        lineHeight: 1.25
        wrapMode: Text.Wrap
        maximumLineCount: root.readOnly ? 100 : 2
        elide: root.readOnly ? Text.ElideNone : Text.ElideRight
      }

      Rectangle {
        visible: root.hasPreview
        width: parent.width
        height: visible ? Style.space(250) : 0
        radius: Style.cornerRadius
        color: "#09090b"
        border.width: Math.max(1, Style.space(1))
        border.color: Util.alpha(root.marketplaceOrange, 0.48)
        clip: true

        Image {
          id: previewThumbnail
          anchors.fill: parent
          anchors.margins: Math.max(1, Style.space(1))
          source: root.opened && root.previewReady
            ? root.previewCardSource : ""
          asynchronous: true
          cache: true
          fillMode: Image.PreserveAspectFit
          mipmap: true
        }

        Text {
          anchors.centerIn: parent
          visible: root.hasPreview && (root.previewLoading
            || previewThumbnail.status === Image.Null
            || previewThumbnail.status === Image.Loading
            || previewThumbnail.status === Image.Error
          )
          text: root.previewFailed || (!root.previewLoading
            && previewThumbnail.status === Image.Error)
            ? "Preview could not be loaded" : "Loading preview..."
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.72
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Rectangle {
          visible: root.previewReady
            && previewThumbnail.status === Image.Ready
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.spacing.sm
          width: previewHint.implicitWidth + Style.spacing.md
          height: Style.space(28)
          radius: Style.space(4)
          color: Util.alpha(root.background, 0.90)
          border.width: Math.max(1, Style.space(1))
          border.color: Util.alpha(root.marketplaceOrange, 0.62)

          Text {
            id: previewHint
            anchors.centerIn: parent
            text: "\uf065  Enlarge"
            textFormat: Text.PlainText
            color: root.marketplaceOrange
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: root.previewReady
            && previewThumbnail.status === Image.Ready
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.requestPreview()
        }
      }

      Rectangle {
        width: parent.width
        height: Math.max(1, Style.space(1))
        color: Util.alpha(root.foreground, 0.16)
      }

      Row {
        width: parent.width
        height: Style.space(38)
        spacing: Style.spacing.md

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.space(2)

          Text {
            text: "AUTHOR"
            textFormat: Text.PlainText
            color: root.marketplaceOrange
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            width: parent.width
            text: String(root.plugin && root.plugin.author || "Unknown")
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            elide: Text.ElideRight
          }
        }

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.space(2)

          Text {
            text: "VERSION"
            textFormat: Text.PlainText
            color: root.marketplaceOrange
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            width: parent.width
            text: String(root.plugin && root.plugin.version || "Unknown")
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            elide: Text.ElideRight
          }
        }
      }

      Text {
        width: parent.width
        text: "SOURCE  " + String(root.plugin
          && root.plugin.sourceLabel || "Unknown")
          + (String(root.plugin && root.plugin.warning || "")
            ? "    " + String(root.plugin.warning) : "")
        textFormat: Text.PlainText
        color: String(root.plugin && root.plugin.warning || "")
          ? root.marketplaceOrange : root.foreground
        opacity: 0.88
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight
      }

      Rectangle {
        width: parent.width
        height: Style.space(root.reviewedCommit.length > 0 ? 62 : 38)
        radius: Style.cornerRadius
        color: Util.alpha(root.foreground, 0.055)
        border.width: Math.max(1, Style.space(1))
        border.color: Util.alpha(root.foreground, 0.12)

        Column {
          anchors.fill: parent
          anchors.margins: Style.spacing.sm
          spacing: Style.space(4)

          Row {
            width: parent.width
            height: Style.space(18)

            Text {
              width: Style.space(92)
              text: "REPOSITORY"
              textFormat: Text.PlainText
              color: root.marketplaceOrange
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              width: parent.width - Style.space(92)
              text: String(root.plugin
                && root.plugin.repository || "Not supplied")
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideMiddle
            }
          }

          Row {
            visible: root.reviewedCommit.length > 0
            width: parent.width
            height: visible ? Style.space(18) : 0

            Text {
              width: Style.space(92)
              text: "REVIEWED"
              textFormat: Text.PlainText
              color: root.marketplaceOrange
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              width: parent.width - Style.space(92)
              text: root.reviewedCommit
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.78
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideMiddle
            }
          }
        }
      }

      Flow {
        id: badgeFlow
        visible: root.badgeItems.length > 0
        width: parent.width
        height: visible ? Style.space(24) : 0
        spacing: Style.space(6)

        Repeater {
          model: root.badgeItems

          delegate: Rectangle {
            id: statusBadge
            required property var modelData
            width: badgeText.implicitWidth + Style.spacing.md
            height: Style.space(24)
            radius: Style.space(3)
            color: Util.alpha(modelData.color, 0.10)
            border.width: Math.max(1, Style.space(1))
            border.color: Util.alpha(modelData.color, 0.72)

            Text {
              id: badgeText
              anchors.centerIn: parent
              text: statusBadge.modelData.label
              textFormat: Text.PlainText
              color: statusBadge.modelData.color
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              font.letterSpacing: Style.space(1)
            }

            MouseArea {
              id: badgeHover
              anchors.fill: parent
              hoverEnabled: true
            }

            PanelToolTip {
              visible: badgeHover.containsMouse
              text: String(statusBadge.modelData.tooltip || "")
              fontFamily: root.fontFamily
            }
          }
        }
      }

      Flow {
        id: metricFlow
        readonly property int columnCount: width < Style.space(560) ? 2 : 4
        readonly property real chipWidth: (width - spacing
          * (columnCount - 1)) / columnCount
        visible: root.metricItems.length > 0
        width: parent.width
        height: visible ? Math.ceil(root.metricItems.length / columnCount)
          * Style.space(42) + Math.max(0,
            Math.ceil(root.metricItems.length / columnCount) - 1) * spacing : 0
        spacing: Style.space(7)

        Repeater {
          model: root.metricItems

          delegate: Rectangle {
            id: metricChip
            required property var modelData
            width: metricFlow.chipWidth
            height: Style.space(42)
            radius: Style.cornerRadius
            color: Util.alpha(modelData.color, 0.075)
            border.width: Math.max(1, Style.space(1))
            border.color: Util.alpha(modelData.color, 0.46)

            Row {
              anchors.centerIn: parent
              spacing: Style.space(7)

              Text {
                text: metricChip.modelData.icon
                textFormat: Text.PlainText
                color: metricChip.modelData.color
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
              }

              Text {
                text: metricChip.modelData.value + "  "
                  + metricChip.modelData.label
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
            }

            MouseArea {
              id: metricHover
              anchors.fill: parent
              hoverEnabled: true
            }

            PanelToolTip {
              visible: metricHover.containsMouse
              text: String(metricChip.modelData.tooltip || "")
              fontFamily: root.fontFamily
            }
          }
        }
      }

      Text {
        visible: root.marketplaceListed && !root.metricsAvailable
        width: parent.width
        text: "Interaction totals are not cached yet"
        textFormat: Text.PlainText
        color: root.marketplaceOrange
        opacity: 0.82
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        visible: !root.marketplaceListed
        width: parent.width
        text: "Not listed on Omarchy Plugins"
        textFormat: Text.PlainText
        color: root.marketplaceOrange
        opacity: 0.82
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
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
            height: Style.space(24)
            radius: Style.space(4)
            color: Util.alpha(root.marketplaceOrange, 0.065)
            border.width: Math.max(1, Style.space(1))
            border.color: Util.alpha(root.marketplaceOrange, 0.34)

            Text {
              id: tagText
              anchors.centerIn: parent
              text: modelData
              textFormat: Text.PlainText
              color: root.marketplaceOrange
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
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

      }
    }

    Row {
      id: actionRow
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.rightMargin: Style.spacing.panelPadding
      anchors.bottomMargin: Style.spacing.panelPadding
      anchors.leftMargin: Style.spacing.panelPadding
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
