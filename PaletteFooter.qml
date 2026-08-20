import QtQuick
import qs.Commons

Item {
  id: root

  property string marketplaceLabel: "Marketplace"
  property color foreground: Color.menu.text
  property color shortcutColor: Color.accent
  readonly property bool compact: width < Style.space(690)
  readonly property int footerFontSize: Math.max(9,
    Style.font.caption - (compact ? 1 : 0))

  Rectangle {
    anchors.top: parent.top
    width: parent.width
    height: 1
    color: Util.alpha(root.foreground, 0.16)
  }

  Row {
    id: footerRow
    anchors.fill: parent
    anchors.topMargin: Style.space(6)

    Repeater {
      model: [
        { keyLabel: "[Ctrl+u]", label: "Check for plugin updates" },
        { keyLabel: "[Ctrl+i]", label: "Plugin info" },
        { keyLabel: "[Ctrl+w]", label: root.marketplaceLabel },
        { keyLabel: "[Ctrl+g]", label: "GitHub plugin source" },
        { keyLabel: "[Ctrl+r]", label: "Refresh cache" },
        { keyLabel: "[Ctrl+s]", label: "Settings" }
      ]

      delegate: Item {
        required property var modelData
        width: footerRow.width / 6
        height: footerRow.height

        Column {
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: keyText.implicitWidth + Style.spacing.sm
            height: Style.space(22)
            radius: Style.space(4)
            color: Util.alpha(root.shortcutColor, 0.10)
            border.width: 1
            border.color: Util.alpha(root.shortcutColor, 0.70)

            Text {
              id: keyText
              anchors.centerIn: parent
              text: modelData.keyLabel
              textFormat: Text.PlainText
              color: root.shortcutColor
              font.family: Style.font.family
              font.pixelSize: root.footerFontSize
              font.bold: true
            }
          }

          Text {
            width: parent.width - Style.space(4)
            text: modelData.label
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.72
            horizontalAlignment: Text.AlignHCenter
            font.family: Style.font.menuFamily
            font.pixelSize: root.footerFontSize
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Math.max(8, root.footerFontSize - 2)
          }
        }
      }
    }
  }
}
