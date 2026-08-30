pragma Singleton
import QtQuick

QtObject {
  property color accent: "#9fc5e8"
  property color urgent: "#e06c75"
  property color muted: "#777777"

  readonly property QtObject menu: QtObject {
    property color background: "#202020"
    property color text: "#eeeeee"
    property color selectedBackground: "#444444"
    property color selectedText: "#ffffff"
  }
}
