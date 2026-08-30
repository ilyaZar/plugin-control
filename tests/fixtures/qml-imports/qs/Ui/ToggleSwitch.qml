import QtQuick

Item {
  id: root

  property bool checked: false
  property int trackHeight: 18
  property int cursorPad: 3
  property color foreground: "white"
  readonly property alias containsMouse: pointer.containsMouse

  signal toggled()

  implicitWidth: trackHeight * 2 + cursorPad * 2
  implicitHeight: trackHeight + cursorPad * 2

  MouseArea {
    id: pointer
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    onClicked: root.toggled()
  }
}
