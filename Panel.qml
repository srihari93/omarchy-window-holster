import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy-window-holster"
  ipcTarget: "omarchy-window-holster.panel"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string scriptPath: Qt.resolvedUrl("bin/omarchy-window-holster").toString().replace(/^file:\/\//, "")

  // Explicit reactive properties for real-time binding without spring-back
  property string cfgPosition: "top"
  property int cfgWidth: 100
  property int cfgHeight: 40

  // Live shortcut hint properties
  property string scToggle: "SUPER + \\"
  property string scCycle: "SUPER + ] / ["
  property string scHolster: "SUPER + ALT + \\"
  property string scSelect: "SUPER + SHIFT + \\"

  property var holsteredWindows: []

  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    configProc.running = true
    listProc.running = true
  }

  function saveConfig() {
    var payload = JSON.stringify({
      "position": root.cfgPosition,
      "width": root.cfgWidth,
      "height": root.cfgHeight
    })
    Quickshell.execDetached([root.scriptPath, "set-config", payload])
  }

  Process {
    id: configProc
    command: [root.scriptPath, "get-config"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var cfg = JSON.parse(text)
          if (cfg && typeof cfg === "object") {
            if (cfg.position !== undefined) root.cfgPosition = cfg.position
            if (cfg.width !== undefined) {
              root.cfgWidth = cfg.width
              widthSlider.value = cfg.width
            }
            if (cfg.height !== undefined) {
              root.cfgHeight = cfg.height
              heightSlider.value = cfg.height
            }
            if (cfg.shortcuts) {
              if (cfg.shortcuts.toggle) root.scToggle = cfg.shortcuts.toggle.toUpperCase()
              if (cfg.shortcuts.cycle) root.scCycle = cfg.shortcuts.cycle.toUpperCase()
              if (cfg.shortcuts.toggle_role) root.scHolster = cfg.shortcuts.toggle_role.toUpperCase()
              if (cfg.shortcuts.select) root.scSelect = cfg.shortcuts.select.toUpperCase()
            }
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: listProc
    command: [root.scriptPath, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var list = JSON.parse(text)
          if (Array.isArray(list)) {
            root.holsteredWindows = list
          }
        } catch (e) {}
      }
    }
  }

  onOpenedChanged: if (opened) refresh()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(mainCol.implicitHeight + Style.space(24))

    Column {
      id: mainCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(12)
      spacing: Style.space(12)

      // Header
      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "󰖲"
          color: Commons.Color.accent
          font.pixelSize: Style.font.title
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "Window Holster"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            text: "Quake drawer for any window"
            color: root.contentForeground
            opacity: 0.6
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator { width: parent.width }

      // Position Dropdown
      Text {
        text: "Position & Edge"
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Dropdown {
        width: parent.width
        value: root.cfgPosition
        options: [
          { value: "top", label: "Top (Drop-down)" },
          { value: "center-top", label: "Center-Top" },
          { value: "bottom", label: "Bottom (Rise-up)" },
          { value: "center-bottom", label: "Center-Bottom" },
          { value: "left", label: "Left Edge (Drawer)" },
          { value: "center-left", label: "Center-Left" },
          { value: "right", label: "Right Edge (Drawer)" },
          { value: "center-right", label: "Center-Right" },
          { value: "center", label: "Center (Modal)" }
        ]
        onChanged: function(val) {
          if (root.cfgPosition !== val) {
            root.cfgPosition = val
            root.saveConfig()
          }
        }
      }

      // Width Slider
      Text {
        text: "Width: " + (widthSlider.dragging ? Math.round(widthSlider.liveValue) : root.cfgWidth) + "%"
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSlider {
        id: widthSlider
        width: parent.width
        bar: root.bar
        minimum: 20
        maximum: 100
        step: 5
        integer: true
        value: root.cfgWidth
        onMoved: function(v) {
          widthSlider.value = Math.round(v)
          root.cfgWidth = Math.round(v)
        }
        onReleased: function(v) {
          widthSlider.value = Math.round(v)
          root.cfgWidth = Math.round(v)
          root.saveConfig()
        }
      }

      // Height Slider
      Text {
        text: "Height: " + (heightSlider.dragging ? Math.round(heightSlider.liveValue) : root.cfgHeight) + "%"
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSlider {
        id: heightSlider
        width: parent.width
        bar: root.bar
        minimum: 10
        maximum: 100
        step: 5
        integer: true
        value: root.cfgHeight
        onMoved: function(v) {
          heightSlider.value = Math.round(v)
          root.cfgHeight = Math.round(v)
        }
        onReleased: function(v) {
          heightSlider.value = Math.round(v)
          root.cfgHeight = Math.round(v)
          root.saveConfig()
        }
      }

      PanelSeparator { width: parent.width }

      // Holstered Windows Pool
      Row {
        width: parent.width
        Text {
          text: "Holstered Windows (" + root.holsteredWindows.length + ")"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        Item { width: Style.space(12); height: 1 }
        Button {
          visible: root.holsteredWindows.length > 0
          text: "Restore All"
          fontSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
          onClicked: {
            Quickshell.execDetached([root.scriptPath, "reset-all"])
            Qt.callLater(root.refresh)
          }
        }
      }

      Repeater {
        model: root.holsteredWindows
        delegate: Item {
          required property var modelData
          width: parent.width
          height: Style.space(32)

          Row {
            anchors.fill: parent
            spacing: Style.space(6)

            Text {
              text: "[" + modelData.slot + "]"
              color: Commons.Color.accent
              font.family: root.contentFontFamily
              font.bold: true
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: modelData.title
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: Style.space(200)
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              text: "Unholster"
              fontSize: Style.font.caption
              onClicked: {
                Quickshell.execDetached([root.scriptPath, "unholster", modelData.address])
                Qt.callLater(root.refresh)
              }
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }

      Text {
        visible: root.holsteredWindows.length === 0
        text: "No windows holstered.\nFocus a window and press " + root.scHolster
        color: root.contentForeground
        opacity: 0.5
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { width: parent.width }

      // Shortcuts reference
      Column {
        width: parent.width
        spacing: Style.space(2)

        Text {
          text: "Active Shortcuts:"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Text {
          text: "• " + root.scToggle + " : Toggle drop-down (show/hide)"
          color: root.contentForeground
          opacity: 0.7
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          text: "• " + root.scCycle + " : Cycle next / previous"
          color: root.contentForeground
          opacity: 0.7
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          text: "• " + root.scHolster + " : Holster / unholster window"
          color: root.contentForeground
          opacity: 0.7
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          text: "• " + root.scSelect + " : Interactive HUD (1-0 jumps)"
          color: root.contentForeground
          opacity: 0.7
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          text: "Customize anytime in ~/.config/hypr/bindings.lua"
          color: Commons.Color.accent
          opacity: 0.8
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
