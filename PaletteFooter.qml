import QtQuick
import qs.Commons

Item {
  id: root

  property string marketplaceLabel: "Marketplace"
  property color foreground: Color.menu.text
  property color shortcutColor: "#e5c07b"

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
        { keyLabel: "[Ctrl+I]", label: "Info" },
        { keyLabel: "[Ctrl+W]", label: root.marketplaceLabel },
        { keyLabel: "[Ctrl+G]", label: "GitHub source" },
        { keyLabel: "[Ctrl+R]", label: "Refresh" },
        { keyLabel: "[Ctrl+S]", label: "Settings" }
      ]

      delegate: Item {
        required property var modelData
        width: footerRow.width / 5
        height: footerRow.height

        Column {
          anchors.centerIn: parent
          spacing: Style.space(2)

          Rectangle {
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
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: modelData.label
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.72
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
