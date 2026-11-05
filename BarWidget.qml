import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy-window-holster"

  readonly property string scriptPath: Qt.resolvedUrl("bin/omarchy-window-holster").toString().replace(/^file:\/\//, "")
  property var holsteredWindows: []
  property int windowCount: holsteredWindows.length

  function refresh() {
    listProc.running = true
  }

  Process {
    id: listProc
    command: [root.scriptPath, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (Array.isArray(data)) {
            root.holsteredWindows = data
          }
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 2500
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  // ---- Panel integration contract (open/close/opened) ----
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && typeof panelLoader.item.open === "function")
      panelLoader.item.open()
  }
  function close() {
    if (panelLoader.item && typeof panelLoader.item.close === "function")
      panelLoader.item.close()
  }
  function togglePanel() {
    if (!panelLoader.item) return
    if (panelLoader.item.opened) {
      panelLoader.item.close()
    } else {
      panelLoader.item.open()
    }
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "omarchy-window-holster.widget"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.windowCount > 0 ? ("󰖲 " + root.windowCount) : "󰖲"
    labelVisible: true
    horizontalMargin: 8
    verticalPadding: 6

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.togglePanel()
      } else {
        // Left click: cycle holstered windows
        Quickshell.execDetached([root.scriptPath, "cycle"])
        Qt.callLater(root.refresh)
      }
    }
  }
}
