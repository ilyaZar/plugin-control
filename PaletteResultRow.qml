import QtQuick
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

  property bool selected: false
  property bool settingsMenuOpen: false
  property bool pointerInteractive: true
  property int rowHeight: Style.space(60)
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color urgent: Color.urgent

  signal hovered()
  signal activated()
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
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    cursorShape: root.pointerInteractive
      ? Qt.PointingHandCursor : Qt.ArrowCursor
    onEntered: if (root.pointerInteractive) root.hovered()
    onClicked: if (root.pointerInteractive) root.activated()
  }

  Column {
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.md
    anchors.right: badgeColumn.left
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Row {
      width: parent.width
      spacing: Style.spacing.sm

      Text {
        width: Math.min(implicitWidth, parent.width
          * (root.settingsMenuOpen ? 1 : 0.52))
        text: root.pluginName
        textFormat: Text.PlainText
        color: root.selected ? root.selectedText
          : (root.dangerous ? root.urgent : root.foreground)
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
      text: root.settingsMenuOpen ? root.description
        : root.author + " - " + (root.description || root.kind)
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
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: root.pointerInteractive
          ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: if (root.pointerInteractive) root.hovered()
        onClicked: if (root.pointerInteractive)
          root.repositoryRequested(root.repository)
      }
    }
  }

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
      text: root.stateLabel
        + (root.version ? "  " + root.version : "")
        + (root.releaseTag ? "  " + root.releaseTag : "")
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
      color: root.warning ? root.urgent
        : (root.selected ? root.selectedText : root.foreground)
      opacity: root.warning ? 1 : 0.55
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }
}
