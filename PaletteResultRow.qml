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
  required property string warningLabel
  required property string version
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
  readonly property string repositoryLabel: {
    var value = root.repository.replace(/\/$/, "")
    var githubPrefix = "https://github.com/"
    return value.indexOf(githubPrefix) === 0
      ? value.slice(githubPrefix.length) : value
  }
  readonly property int titleLineHeight: Math.ceil(titleFontMetrics.height)
  readonly property int detailLineHeight: Math.ceil(detailFontMetrics.height)
  readonly property int rightColumnWidth:
    Math.ceil(rightColumnMetrics.advanceWidth)
  readonly property int detailLineCount: settingsMenuOpen ? 1 : 2
  readonly property int contentHeight: titleLineHeight + Style.space(2)
    + detailLineHeight * detailLineCount

  signal hovered()
  signal activated()
  signal repositoryRequested(string url)

  FontMetrics {
    id: titleFontMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.title
  }

  FontMetrics {
    id: detailFontMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.bodySmall
  }

  TextMetrics {
    id: rightColumnMetrics
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.title
    text: "Marketplace listed"
  }

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

  Item {
    id: contentFrame
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.md
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    height: root.contentHeight

    Item {
      id: leftColumn
      anchors.left: parent.left
      anchors.right: root.settingsMenuOpen
        ? parent.right : badgeColumn.left
      anchors.rightMargin: root.settingsMenuOpen ? 0 : Style.spacing.sm
      anchors.top: parent.top
      anchors.bottom: parent.bottom

      Row {
        id: titleRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.titleLineHeight
        spacing: Style.spacing.sm

        Text {
          id: pluginNameText
          objectName: "pluginNameText"
          width: Math.min(implicitWidth, parent.width
            * (repositoryText.visible ? 0.52 : 1))
          height: parent.height
          text: root.pluginName
          textFormat: Text.PlainText
          color: root.selected ? root.selectedText
            : (root.dangerous ? root.urgent : root.foreground)
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.title
          font.bold: true
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }

        Text {
          id: repositoryText
          objectName: "repositoryText"
          z: 2
          visible: !root.settingsMenuOpen && root.repository !== ""
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, Math.max(0, parent.width - x))
          text: root.repositoryLabel
          textFormat: Text.PlainText
          color: root.selected ? root.selectedText : root.foreground
          opacity: repositoryMouse.containsMouse ? 0.90 : 0.48
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.underline: repositoryMouse.containsMouse
          elide: Text.ElideRight

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

      Text {
        id: descriptionText
        objectName: "descriptionText"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleRow.bottom
        anchors.topMargin: Style.space(2)
        height: root.detailLineHeight * root.detailLineCount
        text: root.settingsMenuOpen ? root.description
          : (root.description || root.kind)
        textFormat: Text.PlainText
        color: root.selected ? root.selectedText : root.foreground
        opacity: 0.65
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        lineHeightMode: Text.FixedHeight
        lineHeight: root.detailLineHeight
        wrapMode: root.settingsMenuOpen ? Text.NoWrap : Text.Wrap
        maximumLineCount: root.detailLineCount
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignTop
      }
    }

    Item {
      id: badgeColumn
      objectName: "badgeColumn"
      visible: !root.settingsMenuOpen
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: visible ? root.rightColumnWidth : 0

      Text {
        id: stateText
        objectName: "stateText"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.titleLineHeight
        text: root.stateLabel
          + (root.version ? " " + root.version : "")
        textFormat: Text.PlainText
        color: root.selected ? root.selectedText : root.foreground
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.title
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
      }

      Text {
        id: sourceText
        objectName: "sourceText"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: stateText.bottom
        anchors.topMargin: Style.space(2)
        height: root.detailLineHeight
        text: root.sourceLabel
        textFormat: Text.PlainText
        color: root.selected ? root.selectedText : root.foreground
        opacity: 0.55
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
      }

      Text {
        id: warningText
        objectName: "warningText"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: sourceText.bottom
        height: root.detailLineHeight
        text: root.warningLabel ? "(" + root.warningLabel + ")" : ""
        textFormat: Text.PlainText
        color: root.urgent
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
        verticalAlignment: Text.AlignVCenter
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideMiddle
      }
    }
  }
}
