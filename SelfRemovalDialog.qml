import QtQuick
import qs.Commons

FocusScope {
  id: root

  property bool opened: false
  property bool busy: false
  property int selectedChoice: 2
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color warningColor: Color.urgent

  signal removeRequested(bool deleteUserData)
  signal canceled()

  function openDialog() {
    selectedChoice = 2
    opened = true
  }

  function closeDialog() {
    opened = false
  }

  function choose() {
    if (busy && selectedChoice !== 2) return
    if (selectedChoice === 0) removeRequested(false)
    else if (selectedChoice === 1) removeRequested(true)
    else canceled()
  }

  function handleKey(event) {
    if (!opened) return false
    if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
      selectedChoice = (selectedChoice + 2) % 3
      return true
    }
    if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
      selectedChoice = (selectedChoice + 1) % 3
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

  Rectangle {
    anchors.fill: parent
    color: Util.alpha(root.background, 0.88)

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      cursorShape: Qt.ArrowCursor
      onClicked: {}
    }

    Rectangle {
      width: Math.min(parent.width - Style.spacing.panelPadding * 2,
        Style.space(480))
      height: confirmationColumn.implicitHeight + Style.spacing.panelPadding * 2
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: root.background
      border.width: Math.max(1, Style.space(1))
      border.color: Util.alpha(root.foreground, 0.18)

      Column {
        id: confirmationColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.space(3)

        Text {
          width: parent.width
          bottomPadding: Style.spacing.sm
          text: "Sure to remove Plugin Control?"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Repeater {
          model: [
            "Yes (preserve user data)",
            "Yes (delete user data)",
            "No / abort"
          ]

          delegate: Rectangle {
            id: choiceRow
            required property int index
            required property string modelData
            readonly property bool pointerEnabled: !root.busy || index === 2

            width: confirmationColumn.width
            height: Style.space(40)
            radius: Style.cornerRadius
            color: root.selectedChoice === index
              ? root.selectedBackground : "transparent"
            opacity: pointerEnabled ? 1 : 0.42

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: choiceRow.modelData
              textFormat: Text.PlainText
              color: root.selectedChoice === choiceRow.index
                ? root.selectedText
                : (choiceRow.index === 1 ? root.warningColor : root.foreground)
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.title
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton
              enabled: choiceRow.pointerEnabled
              hoverEnabled: true
              cursorShape: enabled
                ? Qt.PointingHandCursor : Qt.ArrowCursor
              onEntered: root.selectedChoice = choiceRow.index
              onClicked: {
                root.selectedChoice = choiceRow.index
                root.choose()
              }
            }
          }
        }
      }
    }
  }
}
