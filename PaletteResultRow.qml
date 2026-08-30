import QtQuick
import Quickshell
import qs.Commons

Rectangle {
  id: root

  required property int index
  required property string pluginName
  required property string pluginId
  required property string description
  required property string author
  required property string kind
  required property string stateLabel
  required property string sourceLabel
  required property string warning
  required property string version
  required property string releaseTag
  required property string repository
  required property bool separatorBefore
  required property bool dangerous

  property string previewThumbnailUrl: ""
  property string previewImageUrl: ""
  property bool installed: false
  property bool builtIn: false

  property bool selected: false
  property bool settingsMenuOpen: false
  property bool pointerInteractive: true
  property int rowHeight: Style.space(62)
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color urgent: Color.urgent
  property color accent: Color.accent

  signal hovered
  signal activated
  signal repositoryRequested(string url)

  height: rowHeight
  radius: Style.cornerRadius
  color: selected ? selectedBackground : "transparent"

  Rectangle {
    visible: root.separatorBefore
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Math.max(1, Style.space(1))
    color: Util.alpha(root.foreground, 0.18)
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.pointerInteractive ? Qt.PointingHandCursor : Qt.ArrowCursor
    onEntered: if (root.pointerInteractive)
      root.hovered()
    onClicked: if (root.pointerInteractive)
      root.activated()
  }

  // Left Section: Index Number
  Text {
    id: indexLabel
    visible: !root.settingsMenuOpen
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(26)
    text: String(root.index + 1)
    textFormat: Text.PlainText
    color: root.selected ? root.selectedText : Qt.darker(root.foreground, 1.45)
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    font.bold: true
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideNone
  }

  // Thumbnail Container
  Rectangle {
    id: thumbBox
    visible: !root.settingsMenuOpen
    anchors.left: indexLabel.right
    anchors.leftMargin: Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(48)
    height: Style.space(40)
    radius: Style.space(6)
    color: Util.alpha(root.foreground, 0.08)
    border.width: 1
    border.color: root.selected ? Util.alpha(root.selectedText, 0.35) : Util.alpha(root.foreground, 0.14)
    clip: true

    Image {
      id: thumbImage
      anchors.fill: parent
      anchors.margins: 1
      asynchronous: true
      cache: true
      fillMode: Image.PreserveAspectCrop
      mipmap: true
      source: {
        if (root.previewThumbnailUrl)
          return root.previewThumbnailUrl
        if (root.previewImageUrl)
          return root.previewImageUrl
        if (root.pluginId) {
          var cfg = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
          return "file://" + cfg + "/omarchy/plugins/" + root.pluginId + "/preview.png"
        }
        return ""
      }
    }

    Text {
      anchors.centerIn: parent
      visible: thumbImage.status !== Image.Ready
      text: {
        var id = root.pluginId.toLowerCase()
        if (id.indexOf("ram") >= 0 || id.indexOf("memory") >= 0)
          return "󰍛"
        if (id.indexOf("monitor") >= 0 || id.indexOf("display") >= 0)
          return "󰍹"
        if (id.indexOf("audio") >= 0 || id.indexOf("volume") >= 0)
          return "󰕾"
        if (id.indexOf("power") >= 0 || id.indexOf("battery") >= 0)
          return "󰁹"
        if (id.indexOf("weather") >= 0)
          return "󰖙"
        if (id.indexOf("wifi") >= 0 || id.indexOf("network") >= 0 || id.indexOf("tailscale") >= 0)
          return "󰖩"
        if (id.indexOf("bluetooth") >= 0)
          return "󰂯"
        if (id.indexOf("clock") >= 0 || id.indexOf("time") >= 0)
          return "󰥔"
        if (id.indexOf("agent") >= 0 || id.indexOf("ai") >= 0)
          return "󰚥"
        if (id.indexOf("bar") >= 0)
          return "󱊔"
        return "󰏗"
      }
      color: root.selected ? root.selectedText : root.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }
  }

  // Text Content Column
  Column {
    anchors.left: root.settingsMenuOpen ? parent.left : thumbBox.right
    anchors.leftMargin: root.settingsMenuOpen ? Style.spacing.md : Style.spacing.md
    anchors.right: badgeColumn.left
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Row {
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        width: Math.min(implicitWidth, parent.width * (root.settingsMenuOpen ? 1 : 0.52))
        text: root.pluginName
        textFormat: Text.PlainText
        color: root.selected ? root.selectedText : (root.dangerous ? root.urgent : root.foreground)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        visible: !root.settingsMenuOpen
        width: parent.width - x
        text: root.pluginId
        textFormat: Text.PlainText
        color: root.selected ? root.selectedText : root.foreground
        opacity: 0.60
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }

    Text {
      width: parent.width
      text: root.settingsMenuOpen ? root.description : root.author + " - " + (root.description || root.kind)
      textFormat: Text.PlainText
      color: root.selected ? root.selectedText : root.foreground
      opacity: 0.65
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignLeft
    }

    Text {
      id: repositoryText
      z: 2
      visible: !root.settingsMenuOpen && root.repository !== ""
      width: parent.width
      text: root.repository
      textFormat: Text.PlainText
      color: root.selected ? root.selectedText : root.foreground
      opacity: repositoryMouse.containsMouse ? 0.90 : 0.48
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.underline: repositoryMouse.containsMouse
      elide: Text.ElideRight
      horizontalAlignment: Text.AlignLeft

      MouseArea {
        id: repositoryMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.pointerInteractive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: if (root.pointerInteractive)
          root.hovered()
        onClicked: if (root.pointerInteractive)
          root.repositoryRequested(root.repository)
      }
    }
  }

  // Badges Column on Right
  Column {
    id: badgeColumn
    visible: !root.settingsMenuOpen
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    width: visible ? Style.space(178) : 0
    spacing: Style.space(2)

    Text {
      width: parent.width
      text: root.stateLabel + (root.version ? "  " + root.version : "") + (root.releaseTag ? "  " + root.releaseTag : "")
      textFormat: Text.PlainText
      color: root.selected ? root.selectedText : root.foreground
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
    }

    Text {
      width: parent.width
      text: root.sourceLabel + (root.warning ? " - " + root.warning : "")
      textFormat: Text.PlainText
      color: root.warning ? root.urgent : (root.selected ? root.selectedText : root.foreground)
      opacity: root.warning ? 1 : 0.55
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }
}
