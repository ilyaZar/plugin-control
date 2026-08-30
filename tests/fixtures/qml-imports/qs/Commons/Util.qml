pragma Singleton
import QtQuick

QtObject {
  function alpha(colorValue, opacity) {
    return Qt.rgba(
      colorValue.r, colorValue.g, colorValue.b, opacity)
  }
}
