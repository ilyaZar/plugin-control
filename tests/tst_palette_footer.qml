import QtQuick
import QtTest
import ".."

TestCase {
  id: testCase

  name: "PaletteFooter"
  width: 800
  height: 100
  visible: true
  when: windowShown

  property var footer: null

  Component {
    id: footerComponent

    PaletteFooter {
      width: 720
      height: 42
    }
  }

  SignalSpy {
    id: shortcutSpy
    signalName: "shortcutActivated"
  }

  function init() {
    footer = createTemporaryObject(footerComponent, testCase)
    verify(footer)
    shortcutSpy.target = footer
    shortcutSpy.clear()
    waitForRendering(footer)
  }

  function cleanup() {
    shortcutSpy.target = null
    if (footer) footer.destroy()
    footer = null
  }

  function test_shortcutCells() {
    var shortcuts = [
      Qt.Key_U, Qt.Key_I, Qt.Key_W,
      Qt.Key_G, Qt.Key_R, Qt.Key_S
    ]
    var widths = [720, 320]
    for (var widthIndex = 0; widthIndex < widths.length; widthIndex++) {
      footer.width = widths[widthIndex]
      wait(50)
      for (var index = 0; index < shortcuts.length; index++) {
        shortcutSpy.clear()
        mouseClick(footer,
          Math.floor((index + 0.5) * footer.width / 6),
          Math.floor(footer.height / 2),
          Qt.LeftButton)
        var context = widths[widthIndex] + " px cell " + index
        compare(shortcutSpy.count, 1, context)
        compare(shortcutSpy.signalArguments[0][0], shortcuts[index], context)
      }
    }
  }

  function test_disabledFooterDoesNotActivate() {
    footer.enabled = false
    mouseClick(footer, footer.width / 12, footer.height / 2, Qt.LeftButton)
    compare(shortcutSpy.count, 0)
  }

  function test_rightClickDoesNotActivate() {
    mouseClick(footer, footer.width / 12, footer.height / 2, Qt.RightButton)
    compare(shortcutSpy.count, 0)
  }
}
