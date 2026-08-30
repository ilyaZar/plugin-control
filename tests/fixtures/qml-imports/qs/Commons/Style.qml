pragma Singleton
import QtQuick

QtObject {
  property int cornerRadius: 6

  readonly property QtObject font: QtObject {
    property string family: "monospace"
    property string menuFamily: "sans-serif"
    property int bodySmall: 11
    property int body: 12
    property int caption: 10
    property int subtitle: 13
    property int title: 14
    property int heading: 16
    property int iconLarge: 18
  }

  readonly property QtObject spacing: QtObject {
    property int sm: 8
    property int md: 12
    property int panelPadding: 16
  }

  function space(value) {
    return value
  }
}
