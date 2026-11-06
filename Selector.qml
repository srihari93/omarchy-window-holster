import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Interactive Selector HUD for Omarchy Window Holster
// Overlay layer-shell surface with instant slot jumping, search filtering, and click-outside dismissal.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var service: null

  readonly property string scriptPath: Qt.resolvedUrl("bin/omarchy-window-holster").toString().replace(/^file:\/\//, "")

  property bool opened: false
  property bool searchMode: false
  property string filterText: ""
  property int selectedIndex: 0
  property var items: []

  // Live shortcut hint properties
  property string scToggle: "Super + \\"
  property string scCycle: "Super + [ / ]"
  property string scHolster: "Super + Shift + \\"

  // Shared Omarchy theme surface tokens
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(540), panel.width - Style.gapsOut * 2)

  property bool cursorBlink: true
  Timer {
    interval: 500
    running: root.opened && root.searchMode
    repeat: true
    onTriggered: root.cursorBlink = !root.cursorBlink
  }

  readonly property var filteredItems: {
    if (!root.searchMode || !root.filterText.trim()) {
      return root.items
    }
    var q = root.filterText.toLowerCase().trim()
    var res = []
    for (var i = 0; i < root.items.length; i++) {
      var item = root.items[i]
      var title = (item.title || "").toLowerCase()
      var cls = (item.class || "").toLowerCase()
      if (title.indexOf(q) !== -1 || cls.indexOf(q) !== -1) {
        res.push(item)
      }
    }
    return res
  }

  function open(payloadJson) {
    root.opened = true
    root.searchMode = false
    root.filterText = ""
    root.selectedIndex = 0
    root.refreshItems()
    Qt.callLater(function() {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    root.searchMode = false
    root.filterText = ""
  }

  function dismiss() {
    root.opened = false
    root.searchMode = false
    root.filterText = ""
    Quickshell.execDetached([root.scriptPath, "submap-exit"])
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy-window-holster")
    }
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function refreshItems() {
    listProc.running = true
  }

  function activateSlot(slot) {
    root.dismiss()
    Quickshell.execDetached([root.scriptPath, "activate", String(slot)])
  }

  function select(delta) {
    var count = root.filteredItems.length
    if (count === 0) return
    root.selectedIndex = ((root.selectedIndex + delta) % count + count) % count
    Qt.callLater(function() {
      if (itemListView) itemListView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function activateCurrent() {
    var count = root.filteredItems.length
    if (count === 0) return
    if (root.selectedIndex >= 0 && root.selectedIndex < count) {
      root.activateSlot(root.filteredItems[root.selectedIndex].slot)
    }
  }

  Process {
    id: configProc
    command: [root.scriptPath, "get-config"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var cfg = JSON.parse(text)
          if (cfg && cfg.shortcuts) {
            if (cfg.shortcuts.toggle) root.scToggle = cfg.shortcuts.toggle
            if (cfg.shortcuts.cycle) root.scCycle = cfg.shortcuts.cycle
            if (cfg.shortcuts.toggle_role) root.scHolster = cfg.shortcuts.toggle_role
          }
        } catch (e) {}
      }
    }
  }

  onOpenedChanged: if (opened) configProc.running = true
  Component.onCompleted: configProc.running = true

  Process {
    id: listProc
    command: [root.scriptPath, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (Array.isArray(data)) {
            root.items = data
            // Default selectedIndex to currently active window if any
            for (var i = 0; i < data.length; i++) {
              if (data[i].active) {
                root.selectedIndex = i
                break
              }
            }
          }
        } catch (e) {}
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-window-holster"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onBackingWindowVisibleChanged: {
      if (backingWindowVisible && root.opened) {
        Qt.callLater(function() {
          if (keyCatcher) keyCatcher.forceActiveFocus()
        })
      }
    }

    // Fullscreen dimmed backdrop scrim
    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    // Fullscreen click-outside dismisser
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    // Centered Interactive HUD Card
    BorderSurface {
      id: card
      width: root.cardWidth
      implicitHeight: Math.min(cardCol.implicitHeight + root.contentMargin * 2, panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      // Prevent clicks inside card from bubbling to scrim
      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      // Keyboard event catcher with exclusive Wayland layer-shell focus
      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.searchMode) {
              if (root.filterText.length > 0) {
                root.filterText = ""
                root.selectedIndex = 0
              } else {
                root.searchMode = false
              }
            } else {
              root.dismiss()
            }
            event.accepted = true
            return
          }

          if (!root.searchMode) {
            // Direct slot activation: 1..9 (instant, no Enter)
            if (event.text && event.text >= "1" && event.text <= "9") {
              var targetIdx = parseInt(event.text, 10) - 1
              if (targetIdx >= 0 && targetIdx < root.filteredItems.length) {
                root.activateSlot(root.filteredItems[targetIdx].slot)
                event.accepted = true
                return
              }
              event.accepted = true
              return
            }

            // Key '0' activates 10th slot (index 9)
            if (event.text === "0") {
              if (root.filteredItems.length >= 10) {
                root.activateSlot(root.filteredItems[9].slot)
                event.accepted = true
                return
              }
              event.accepted = true
              return
            }

            // Vim keyboard scrolling: j (down), k (up)
            if (event.key === Qt.Key_J || event.text === "j") {
              root.select(1)
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_K || event.text === "k") {
              root.select(-1)
              event.accepted = true
              return
            }

            // Arrow keys scrolling: Up / Down
            if (event.key === Qt.Key_Up) {
              root.select(-1)
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Down) {
              root.select(1)
              event.accepted = true
              return
            }

            // Page jumping
            if (event.key === Qt.Key_PageUp) {
              root.select(-5)
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_PageDown) {
              root.select(5)
              event.accepted = true
              return
            }

            // Home / End
            if (event.key === Qt.Key_Home) {
              root.selectedIndex = 0
              if (itemListView) itemListView.positionViewAtIndex(0, ListView.Beginning)
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_End) {
              if (root.filteredItems.length > 0) {
                root.selectedIndex = root.filteredItems.length - 1
                if (itemListView) itemListView.positionViewAtIndex(root.selectedIndex, ListView.End)
              }
              event.accepted = true
              return
            }

            // Slash activates search mode
            if (event.key === Qt.Key_Slash || event.text === "/") {
              root.searchMode = true
              root.filterText = ""
              root.selectedIndex = 0
              event.accepted = true
              return
            }

            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activateCurrent()
              event.accepted = true
              return
            }
          } else {
            // Search mode is ACTIVE:
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activateCurrent()
              event.accepted = true
              return
            }
            if (event.modifiers & Qt.ControlModifier) {
              if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                root.select(1)
                event.accepted = true
                return
              }
              if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                root.select(-1)
                event.accepted = true
                return
              }
            }
            if (event.key === Qt.Key_Up) {
              root.select(-1)
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Down) {
              root.select(1)
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_PageUp) {
              root.select(-5)
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_PageDown) {
              root.select(5)
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Backspace) {
              if (root.filterText.length > 0) {
                root.filterText = root.filterText.slice(0, -1)
                root.selectedIndex = 0
              } else {
                root.searchMode = false
              }
              event.accepted = true
              return
            }
            if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              root.filterText = root.filterText + event.text
              root.selectedIndex = 0
              event.accepted = true
              return
            }
          }
        }
      }

      Column {
        id: cardCol
        width: parent.width - root.contentMargin * 2
        anchors.centerIn: parent
        spacing: root.contentSpacing

        // --- Header Row ---
        Item {
          id: headerContainer
          width: parent.width
          height: Math.max(leftHeaderRow.implicitHeight, topHintsRow.implicitHeight, Style.space(24))

          Row {
            id: leftHeaderRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              id: headerIcon
              text: "󰖲"
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              color: Commons.Color.accent
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: headerTitle
              text: "Window Holster"
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              color: root.foreground
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              id: countBadge
              visible: root.items.length > 0
              height: Style.space(20)
              width: countText.implicitWidth + Style.space(12)
              radius: Style.cornerRadius
              color: Util.alpha(Commons.Color.accent, 0.2)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: countText
                anchors.centerIn: parent
                text: root.items.length + (root.items.length === 1 ? " window" : " windows")
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Commons.Color.accent
              }
            }
          }

          Row {
            id: topHintsRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            // Search Mode Badge
            Rectangle {
              visible: root.searchMode
              height: Style.space(22)
              width: escRow.implicitWidth + Style.space(14)
              radius: Style.cornerRadius
              color: Util.alpha(root.foreground, 0.08)

              Row {
                id: escRow
                anchors.centerIn: parent
                spacing: Style.space(5)

                Text {
                  text: "Esc"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: Util.alpha(root.foreground, 0.75)
                }
                Text {
                  text: "Exit Search"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Util.alpha(root.foreground, 0.55)
                }
              }
            }

            // Normal Mode Badges: Jump, Scroll, Search
            Rectangle {
              visible: !root.searchMode
              height: Style.space(22)
              width: jumpRow.implicitWidth + Style.space(14)
              radius: Style.cornerRadius
              color: Util.alpha(root.foreground, 0.08)

              Row {
                id: jumpRow
                anchors.centerIn: parent
                spacing: Style.space(5)

                Text {
                  text: "1-0"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: Util.alpha(root.foreground, 0.75)
                }
                Text {
                  text: "Jump"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Util.alpha(root.foreground, 0.55)
                }
              }
            }

            Rectangle {
              visible: !root.searchMode
              height: Style.space(22)
              width: scrollRow.implicitWidth + Style.space(14)
              radius: Style.cornerRadius
              color: Util.alpha(root.foreground, 0.08)

              Row {
                id: scrollRow
                anchors.centerIn: parent
                spacing: Style.space(5)

                Text {
                  text: "j/k"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: Util.alpha(root.foreground, 0.75)
                }
                Text {
                  text: "Scroll"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Util.alpha(root.foreground, 0.55)
                }
              }
            }

            Rectangle {
              visible: !root.searchMode
              height: Style.space(22)
              width: searchRow.implicitWidth + Style.space(14)
              radius: Style.cornerRadius
              color: Util.alpha(root.foreground, 0.08)

              Row {
                id: searchRow
                anchors.centerIn: parent
                spacing: Style.space(5)

                Text {
                  text: "/"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: Util.alpha(root.foreground, 0.75)
                }
                Text {
                  text: "Search"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: Util.alpha(root.foreground, 0.55)
                }
              }
            }
          }
        }

        // --- Search Bar (Visible in Search Mode) ---
        Rectangle {
          visible: root.searchMode
          width: parent.width
          height: Style.space(36)
          radius: Style.cornerRadius
          color: Util.alpha(root.foreground, 0.06)
          border.color: Commons.Color.accent
          border.width: 1

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              text: "󰍉"
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: Commons.Color.accent
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.filterText ? (root.filterText + (root.cursorBlink ? "|" : " ")) : ("Type to filter holstered windows…" + (root.cursorBlink ? "|" : " "))
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              color: root.filterText ? root.foreground : Util.alpha(root.foreground, 0.45)
            }
          }
        }

        // --- Subtle divider ---
        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(root.foreground, 0.12)
        }

        // --- Empty State ---
        Column {
          visible: root.items.length === 0
          width: parent.width
          spacing: Style.space(8)
          topPadding: Style.space(16)
          bottomPadding: Style.space(16)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "󰖲"
            font.family: root.fontFamily
            font.pixelSize: Style.space(36)
            color: Util.alpha(root.foreground, 0.4)
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No windows are holstered"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            color: root.foreground
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Focus any window and press " + root.scHolster + " to holster it"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: Util.alpha(root.foreground, 0.6)
          }
        }

        // --- No Search Results State ---
        Column {
          visible: root.items.length > 0 && root.filteredItems.length === 0
          width: parent.width
          spacing: Style.space(8)
          topPadding: Style.space(12)
          bottomPadding: Style.space(12)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No matching windows found"
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: Util.alpha(root.foreground, 0.7)
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Press [Backspace] or [Esc] to clear search"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: Util.alpha(root.foreground, 0.5)
          }
        }

        // --- Holstered Windows List (At most 10 visible, scrollable beyond) ---
        ListView {
          id: itemListView
          visible: root.filteredItems.length > 0
          width: parent.width
          implicitHeight: Math.min(contentHeight, Math.min(10, root.filteredItems.length) * Style.space(48))
          clip: true
          spacing: Style.space(4)
          currentIndex: root.selectedIndex
          model: root.filteredItems

          ScrollBar.vertical: ScrollBar {
            policy: root.filteredItems.length > 10 ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
          }

          delegate: Rectangle {
            id: rowDelegate
            required property var modelData
            required property int index

            width: itemListView.width
            height: Style.space(44)
            radius: Style.cornerRadius
            color: (index === root.selectedIndex) ? root.selectedBackground : "transparent"

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: root.selectedIndex = index
              onClicked: root.activateSlot(modelData.slot)
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

              // Dynamic slot / rank badge
              Rectangle {
                width: Style.space(26)
                height: Style.space(26)
                radius: Style.cornerRadius
                color: modelData.active ? Commons.Color.accent : Util.alpha(root.foreground, (index === root.selectedIndex) ? 0.25 : 0.12)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent
                  // In search mode: dynamically re-numbered as 1, 2, 3...
                  // In normal mode: items 1-9 show 1-9, item 10 shows 0, item 11+ shows 11+
                  text: root.searchMode ? String(index + 1) : (index < 9 ? String(index + 1) : (index === 9 ? "0" : String(index + 1)))
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: modelData.active ? Commons.Color.background : ((index === root.selectedIndex) ? root.selectedText : root.foreground)
                }
              }

              // Active indicator badge
              Rectangle {
                id: activeBadge
                visible: modelData.active
                height: Style.space(20)
                width: activeLabel.implicitWidth + Style.space(8)
                radius: Style.cornerRadius
                color: Util.alpha(Commons.Color.accent, 0.2)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: activeLabel
                  anchors.centerIn: parent
                  text: "▶ Drop-down"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: Commons.Color.accent
                }
              }

              // Window Title and App Class
              Column {
                width: Math.max(Style.space(100), parent.width - Style.space(130) - (modelData.active ? (activeBadge.width + Style.space(10)) : 0))
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: modelData.title || "Window"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                  color: (index === root.selectedIndex) ? root.selectedText : root.foreground
                }

                Text {
                  width: parent.width
                  text: modelData.class || ""
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  color: (index === root.selectedIndex) ? root.selectedText : Util.alpha(root.foreground, 0.6)
                }
              }

              Item {
                // Spacer
                width: 1
                height: 1
              }

              // Dynamic Key Hint Badge on Right
              Text {
                text: {
                  if (root.searchMode) {
                    return (index === root.selectedIndex) ? "[Enter] Select" : "[Enter]"
                  } else {
                    if (index < 9) return "key [" + (index + 1) + "]"
                    if (index === 9) return "key [0]"
                    return (index === root.selectedIndex) ? "[Enter] Select" : "[Enter]"
                  }
                }
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: (index === root.selectedIndex)
                color: (index === root.selectedIndex) ? root.selectedText : Util.alpha(root.foreground, 0.45)
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }
        }

        // --- More Items Scroll Hint (Visible when items > 10) ---
        Rectangle {
          visible: root.filteredItems.length > 10
          width: parent.width
          height: Style.space(26)
          radius: Style.cornerRadius
          color: Util.alpha(root.foreground, 0.05)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(8)

            Text {
              text: "Showing 10 of " + root.filteredItems.length + " windows"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              color: Util.alpha(root.foreground, 0.7)
            }

            Text {
              text: "•"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: Util.alpha(root.foreground, 0.3)
            }

            Text {
              text: "Scroll [j / k / ↓ / ↑] or search [/]"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              color: Commons.Color.accent
            }
          }
        }

        // --- Bottom Helper / Footer ---
        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(root.foreground, 0.08)
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Rectangle {
            height: Style.space(22)
            width: tglRow.implicitWidth + Style.space(16)
            radius: Style.cornerRadius
            color: Util.alpha(root.foreground, 0.08)

            Row {
              id: tglRow
              anchors.centerIn: parent
              spacing: Style.space(5)

              Text {
                text: root.scToggle
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Util.alpha(root.foreground, 0.75)
              }
              Text {
                text: "Toggle"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Util.alpha(root.foreground, 0.55)
              }
            }
          }

          Rectangle {
            height: Style.space(22)
            width: cycRow.implicitWidth + Style.space(16)
            radius: Style.cornerRadius
            color: Util.alpha(root.foreground, 0.08)

            Row {
              id: cycRow
              anchors.centerIn: parent
              spacing: Style.space(5)

              Text {
                text: root.scCycle
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Util.alpha(root.foreground, 0.75)
              }
              Text {
                text: "Cycle"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Util.alpha(root.foreground, 0.55)
              }
            }
          }

          Rectangle {
            height: Style.space(22)
            width: hlsRow.implicitWidth + Style.space(16)
            radius: Style.cornerRadius
            color: Util.alpha(root.foreground, 0.08)

            Row {
              id: hlsRow
              anchors.centerIn: parent
              spacing: Style.space(5)

              Text {
                text: root.scHolster
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Util.alpha(root.foreground, 0.75)
              }
              Text {
                text: "Holster"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                color: Util.alpha(root.foreground, 0.55)
              }
            }
          }
        }
      }
    }
  }
}
