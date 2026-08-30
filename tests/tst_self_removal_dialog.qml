import QtQuick
import QtTest
import ".."

TestCase {
  id: testCase

  name: "SelfRemovalDialogPointer"
  width: 800
  height: 360
  visible: true
  when: windowShown

  property var dialog: null

  Component {
    id: dialogComponent

    SelfRemovalDialog {
      width: 720
      height: 280
    }
  }

  SignalSpy {
    id: removeSpy
    signalName: "removeRequested"
  }

  SignalSpy {
    id: canceledSpy
    signalName: "canceled"
  }

  function init() {
    dialog = createTemporaryObject(dialogComponent, testCase)
    verify(dialog)
    removeSpy.target = dialog
    canceledSpy.target = dialog
    dialog.openDialog()
    waitForRendering(dialog)
    clearSpies()
  }

  function cleanup() {
    removeSpy.target = null
    canceledSpy.target = null
    if (dialog) dialog.destroy()
    dialog = null
  }

  function clearSpies() {
    removeSpy.clear()
    canceledSpy.clear()
  }

  function descendants(parent) {
    var values = []
    var children = parent && parent.children ? parent.children : []
    for (var index = 0; index < children.length; index++) {
      var child = children[index]
      values.push(child)
      var nested = descendants(child)
      for (var nestedIndex = 0; nestedIndex < nested.length; nestedIndex++)
        values.push(nested[nestedIndex])
    }
    return values
  }

  function choice(index) {
    var items = descendants(dialog)
    for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
      if (items[itemIndex].index === index
          && typeof items[itemIndex].modelData === "string")
        return items[itemIndex]
    }
    return null
  }

  function assertNoDispatch(context) {
    compare(removeSpy.count, 0, context + " remove")
    compare(canceledSpy.count, 0, context + " cancel")
  }

  function assertChoiceDispatch(index, context) {
    var button = choice(index)
    verify(button, context + " exists")
    dialog.selectedChoice = (index + 1) % 3
    clearSpies()
    mouseClick(button, Math.floor(button.width / 2),
      Math.floor(button.height / 2), Qt.LeftButton)
    compare(dialog.selectedChoice, index, context + " selection")
    if (index === 2) {
      compare(canceledSpy.count, 1, context + " canceled")
      compare(removeSpy.count, 0, context + " remove")
    } else {
      compare(removeSpy.count, 1, context + " remove")
      compare(removeSpy.signalArguments[0][0], index === 1,
        context + " delete flag")
      compare(canceledSpy.count, 0, context + " canceled")
    }
  }

  function test_allChoicesDispatchClickedIndex() {
    var widths = [720, 320]
    for (var widthIndex = 0; widthIndex < widths.length; widthIndex++) {
      dialog.width = widths[widthIndex]
      wait(1)
      for (var index = 0; index < 3; index++)
        assertChoiceDispatch(index, widths[widthIndex] + " px choice " + index)
    }
  }

  function test_choiceRectangleEdges() {
    for (var index = 0; index < 3; index++) {
      var button = choice(index)
      verify(button)
      var points = [
        { x: 1, y: 1 },
        { x: Math.floor(button.width - 2),
          y: Math.floor(button.height - 2) }
      ]
      for (var pointIndex = 0; pointIndex < points.length; pointIndex++) {
        dialog.selectedChoice = (index + 1) % 3
        clearSpies()
        mouseClick(button, points[pointIndex].x, points[pointIndex].y,
          Qt.LeftButton)
        compare(dialog.selectedChoice, index,
          "choice " + index + " edge " + pointIndex + " selection")
        if (index === 2) {
          compare(canceledSpy.count, 1)
          compare(removeSpy.count, 0)
        } else {
          compare(removeSpy.count, 1)
          compare(removeSpy.signalArguments[0][0], index === 1)
          compare(canceledSpy.count, 0)
        }
      }
    }
  }

  function test_gapsAndRightClicksAreInert() {
    var first = choice(0)
    var second = choice(1)
    var column = first.parent
    verify(first)
    verify(second)
    verify(column.spacing > 0)

    var gapX = column.width / 2
    var gapY = first.y + first.height + column.spacing / 2
    clearSpies()
    mouseClick(column, Math.floor(gapX), Math.floor(gapY), Qt.LeftButton)
    assertNoDispatch("choice gap")

    var titlePoint = first.mapToItem(dialog, first.width / 2, -10)
    clearSpies()
    mouseClick(dialog, Math.floor(titlePoint.x), Math.floor(titlePoint.y),
      Qt.LeftButton)
    assertNoDispatch("confirmation title")

    for (var index = 0; index < 3; index++) {
      var button = choice(index)
      dialog.selectedChoice = 2
      clearSpies()
      mouseClick(button, Math.floor(button.width / 2),
        Math.floor(button.height / 2), Qt.RightButton)
      assertNoDispatch("right-click choice " + index)
      compare(dialog.selectedChoice, 2,
        "right-click choice " + index + " selection")
    }
  }

  function test_busyMutationsStayInertButAbortWorks() {
    dialog.busy = true
    for (var index = 0; index < 2; index++) {
      var button = choice(index)
      dialog.selectedChoice = 2
      clearSpies()
      mouseClick(button, Math.floor(button.width / 2),
        Math.floor(button.height / 2), Qt.LeftButton)
      assertNoDispatch("busy choice " + index)
      compare(dialog.selectedChoice, 2,
        "busy choice " + index + " selection")
    }

    var abortButton = choice(2)
    clearSpies()
    mouseClick(abortButton, Math.floor(abortButton.width / 2),
      Math.floor(abortButton.height / 2), Qt.LeftButton)
    compare(canceledSpy.count, 1, "busy abort")
    compare(removeSpy.count, 0, "busy abort remove")
  }
}
