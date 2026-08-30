import QtQuick
import QtTest
import ".."

TestCase {
  id: testCase

  name: "ActionDialogPointer"
  width: 800
  height: 620
  visible: true
  when: windowShown

  property var dialog: null

  Component {
    id: dialogComponent

    ActionDialog {
      width: 720
      height: 540
    }
  }

  SignalSpy {
    id: actionSpy
    signalName: "actionRequested"
  }

  SignalSpy {
    id: canceledSpy
    signalName: "canceled"
  }

  function init() {
    dialog = createTemporaryObject(dialogComponent, testCase)
    verify(dialog)
    actionSpy.target = dialog
    canceledSpy.target = dialog
    clearSpies()
  }

  function cleanup() {
    actionSpy.target = null
    canceledSpy.target = null
    if (dialog) dialog.destroy()
    dialog = null
  }

  function clearSpies() {
    actionSpy.clear()
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

  function actionButton(operation) {
    var items = descendants(dialog)
    for (var index = 0; index < items.length; index++) {
      var modelData = items[index].modelData
      if (modelData && typeof modelData === "object"
          && String(modelData.operation || "") === operation
          && items[index].index !== undefined)
        return items[index]
    }
    return null
  }

  function configure(plugin, readOnly, width) {
    dialog.width = width
    dialog.readOnly = readOnly === true
    dialog.plugin = plugin
    dialog.openDialog()
    wait(1)
    waitForRendering(dialog)
  }

  function assertNoDispatch(context) {
    compare(actionSpy.count, 0, context + " action")
    compare(canceledSpy.count, 0, context + " cancel")
  }

  function assertButtonDispatch(button, operation, context) {
    verify(button, context + " exists")
    verify(button.width > 2, context + " width")
    verify(button.height > 2, context + " height")
    clearSpies()
    dialog.selectedChoice = (button.index + 1) % dialog.actions.length
    mouseClick(button, Math.floor(button.width / 2),
      Math.floor(button.height / 2), Qt.LeftButton)
    compare(dialog.selectedChoice, button.index, context + " selection")
    if (operation === "cancel" || operation === "close") {
      compare(canceledSpy.count, 1, context + " canceled")
      compare(actionSpy.count, 0, context + " action")
    } else {
      compare(actionSpy.count, 1, context + " action")
      compare(actionSpy.signalArguments[0][0], operation,
        context + " operation")
      compare(canceledSpy.count, 0, context + " canceled")
    }
  }

  function test_actionMatrix_data() {
    return [
      {
        tag: "information",
        plugin: { id: "io.example.info" },
        readOnly: true,
        operations: ["close"]
      },
      {
        tag: "installable",
        plugin: { id: "io.example.add", installable: true },
        operations: ["cancel", "add"]
      },
      {
        tag: "installed-enabled",
        plugin: { id: "io.example.enabled", installed: true, enabled: true,
          canDisable: true, removable: true, updateStatus: "current" },
        operations: ["cancel", "update", "disable", "remove"]
      },
      {
        tag: "installed-disabled",
        plugin: { id: "io.example.disabled", installed: true, enabled: false,
          canDisable: true, removable: true, updateStatus: "current" },
        operations: ["cancel", "update", "enable", "remove"]
      },
      {
        tag: "builtin-enabled",
        plugin: { id: "omarchy.example", builtIn: true, enabled: true,
          canDisable: true },
        operations: ["cancel", "disable"]
      },
      {
        tag: "builtin-disabled",
        plugin: { id: "omarchy.example", builtIn: true, enabled: false,
          canDisable: true },
        operations: ["cancel", "enable"]
      },
      {
        tag: "full-bar-enabled",
        plugin: { id: "omarchy.bar", builtIn: true, fullBar: true,
          enabled: true },
        operations: ["cancel"]
      },
      {
        tag: "full-bar-disabled",
        plugin: { id: "io.example.bar", installed: true, fullBar: true,
          enabled: false },
        operations: ["cancel", "enable"]
      },
      {
        tag: "browse-only",
        plugin: { id: "io.example.browse" },
        operations: ["cancel"]
      }
    ]
  }

  function test_actionMatrix(data) {
    var widths = [720, 320]
    for (var widthIndex = 0; widthIndex < widths.length; widthIndex++) {
      configure(data.plugin, data.readOnly === true, widths[widthIndex])
      compare(dialog.actions.length, data.operations.length,
        widths[widthIndex] + " px action count")
      for (var index = 0; index < data.operations.length; index++) {
        var operation = data.operations[index]
        var context = widths[widthIndex] + " px " + operation
        assertButtonDispatch(actionButton(operation), operation, context)
      }
    }
  }

  function test_buttonRectangleEdgesAndGaps() {
    configure({ id: "io.example.add", installable: true }, false, 320)
    var addButton = actionButton("add")
    var cancelButton = actionButton("cancel")
    verify(addButton)
    verify(cancelButton)

    var points = [
      { x: 1, y: 1 },
      { x: Math.floor(addButton.width - 2),
        y: Math.floor(addButton.height - 2) }
    ]
    for (var pointIndex = 0; pointIndex < points.length; pointIndex++) {
      clearSpies()
      dialog.selectedChoice = cancelButton.index
      mouseClick(addButton, points[pointIndex].x, points[pointIndex].y,
        Qt.LeftButton)
      compare(actionSpy.count, 1, "inside edge " + pointIndex)
      compare(actionSpy.signalArguments[0][0], "add",
        "inside edge operation " + pointIndex)
      compare(canceledSpy.count, 0, "inside edge cancel " + pointIndex)
    }

    var actionRow = addButton.parent
    verify(actionRow.spacing > 0)
    var gapX = cancelButton.x + cancelButton.width
      + actionRow.spacing / 2
    clearSpies()
    mouseClick(actionRow, Math.floor(gapX),
      Math.floor(actionRow.height / 2), Qt.LeftButton)
    assertNoDispatch("button gap")

    var above = actionRow.mapToItem(dialog,
      actionRow.width / 2, -2)
    clearSpies()
    mouseClick(dialog, Math.floor(above.x), Math.floor(above.y),
      Qt.LeftButton)
    assertNoDispatch("above action row")
  }

  function test_rightClicksDoNotDispatch() {
    configure({ id: "io.example.enabled", installed: true, enabled: true,
      canDisable: true, removable: true, updateStatus: "current" },
      false, 720)
    var operations = ["cancel", "update", "disable", "remove"]
    for (var index = 0; index < operations.length; index++) {
      var button = actionButton(operations[index])
      verify(button)
      dialog.selectedChoice = 0
      clearSpies()
      mouseClick(button, Math.floor(button.width / 2),
        Math.floor(button.height / 2), Qt.RightButton)
      assertNoDispatch("right-click " + operations[index])
      compare(dialog.selectedChoice, 0,
        "right-click selection " + operations[index])
    }
  }

  function test_unavailableButtonsExplainWithoutDispatch() {
    var updateReason = "This manually installed plugin cannot be updated."
    configure({ id: "io.example.manual", installed: true, removable: true,
      dirty: true, updateStatus: "manual", updateReason: updateReason },
      false, 720)
    var expected = {
      update: updateReason,
      remove: "Removal is blocked because this Git checkout has local changes."
    }
    var operations = ["update", "remove"]
    for (var index = 0; index < operations.length; index++) {
      var operation = operations[index]
      var button = actionButton(operation)
      verify(button)
      dialog.selectedChoice = 0
      dialog.helpText = ""
      clearSpies()
      mouseClick(button, Math.floor(button.width / 2),
        Math.floor(button.height / 2), Qt.LeftButton)
      compare(dialog.selectedChoice, button.index,
        operation + " unavailable selection")
      compare(dialog.helpText, expected[operation],
        operation + " unavailable reason")
      assertNoDispatch(operation + " unavailable")
    }
  }

  function test_busyMutationsStayInertButCancelWorks() {
    configure({ id: "io.example.enabled", installed: true, enabled: true,
      canDisable: true, removable: true, updateStatus: "current" },
      false, 720)
    dialog.busy = true
    var operations = ["update", "disable", "remove"]
    for (var index = 0; index < operations.length; index++) {
      var button = actionButton(operations[index])
      verify(button)
      clearSpies()
      mouseClick(button, Math.floor(button.width / 2),
        Math.floor(button.height / 2), Qt.LeftButton)
      assertNoDispatch("busy " + operations[index])
    }

    var cancelButton = actionButton("cancel")
    clearSpies()
    mouseClick(cancelButton, Math.floor(cancelButton.width / 2),
      Math.floor(cancelButton.height / 2), Qt.LeftButton)
    compare(canceledSpy.count, 1, "busy cancel")
    compare(actionSpy.count, 0, "busy cancel action")

    configure({ id: "io.example.info" }, true, 720)
    dialog.busy = true
    var closeButton = actionButton("close")
    clearSpies()
    mouseClick(closeButton, Math.floor(closeButton.width / 2),
      Math.floor(closeButton.height / 2), Qt.LeftButton)
    compare(canceledSpy.count, 1, "busy read-only close")
    compare(actionSpy.count, 0, "busy read-only action")
  }
}
