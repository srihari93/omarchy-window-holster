import QtQuick
import QtQuick.Effects
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
  property bool hasActiveWindow: false
  property string scHolster: "Super + Shift + \\"

  readonly property string iconState: {
    if (root.opened || root.hasActiveWindow) {
      return "open"
    } else if (root.windowCount > 0) {
      return "stashed"
    } else {
      return "empty"
    }
  }

  readonly property url iconSource: Qt.resolvedUrl("icons/holster/" + root.iconState + ".svg")

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
            var act = false
            for (var i = 0; i < data.length; i++) {
              if (data[i].active) {
                act = true
                break
              }
            }
            root.hasActiveWindow = act
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
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item && typeof panelLoader.item.closeForPopoutSwitch === "function")
      panelLoader.item.closeForPopoutSwitch()
    else
      root.close()
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
    function refresh(): void { root.broadcast("refresh") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    hasVisualContent: true
    labelVisible: false
    fixedWidth: root.vertical ? -1 : (contentRow.implicitWidth + button.scaledHorizontalMargin * 2)
    tooltipText: root.windowCount > 0
      ? ("Window Holster (" + root.windowCount + " " + (root.windowCount === 1 ? "window" : "windows") + ")\n• Left click: drawer settings\n• Right click: cycle windows")
      : ("Window Holster (Empty)\n• " + root.scHolster + ": holster window\n• Left click: drawer settings")
    horizontalMargin: 8
    verticalPadding: 6

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        // Right click: cycle holstered windows
        Quickshell.execDetached([root.scriptPath, "cycle"])
        Qt.callLater(root.refresh)
      } else {
        // Left click: toggle drawer settings / management panel
        root.togglePanel()
      }
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Item {
        width: Style.space(16)
        height: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter

        Image {
          id: holsterSvg
          anchors.fill: parent
          source: root.iconSource
          sourceSize.width: Style.space(16)
          sourceSize.height: Style.space(16)
          fillMode: Image.PreserveAspectFit
          opacity: root.windowCount === 0 ? 0.55 : 1.0
          layer.enabled: true
          layer.effect: MultiEffect {
            brightness: 1.0
            colorization: 1.0
            colorizationColor: root.hasActiveWindow ? Commons.Color.accent : button.foreground
          }
        }
      }

      Text {
        id: countLabel
        visible: root.windowCount > 0
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.windowCount)
        color: root.hasActiveWindow ? Commons.Color.accent : button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: true
      }
    }
  }
}
