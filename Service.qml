import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Background service for Omarchy Window Holster
// Handles IPC dispatching, crash safety watchdog, and lifecycle restoration.
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null

  readonly property string scriptPath: Qt.resolvedUrl("bin/omarchy-window-holster").toString().replace(/^file:\/\//, "")

  // Crash & Quit Safety Watchdog:
  // Monitors parent process (Quickshell) lifetime via stdin pipe and signals.
  // When Quickshell or the plugin quits, crashes, or is killed,
  // the watchdog automatically restores all holstered windows to visible workspaces.
  // Also runs the socket2 background listener for click-outside auto-retract.
  Process {
    id: watchdogProc
    command: [root.scriptPath, "watchdog"]
    running: true
    onExited: function(exitCode) {
      running = true
    }
  }

  Component.onCompleted: {
    // Automatically setup CLI in $PATH and register default Hyprland shortcuts out of the box
    Quickshell.execDetached([root.scriptPath, "setup"])
  }

  Component.onDestruction: {
    Quickshell.execDetached([root.scriptPath, "reset-all"])
  }

  IpcHandler {
    target: "omarchy-window-holster"

    function toggle(): string { return serviceIpc.toggle() }
    function cycle(): string { return serviceIpc.cycle() }
    function cycleNext(): string { return serviceIpc.cycleNext() }
    function cyclePrev(): string { return serviceIpc.cyclePrev() }
    function toggleRole(): string { return serviceIpc.toggleRole() }
    function activate(slot: int): string { return serviceIpc.activate(slot) }
    function select(): string { return serviceIpc.select() }
    function showHud(): string { return serviceIpc.showHud() }
    function hideHud(): string { return serviceIpc.hideHud() }
    function toggleHud(): string { return serviceIpc.toggleHud() }
    function resetAll(): string { return serviceIpc.resetAll() }
  }

  IpcHandler {
    id: serviceIpc
    target: "omarchy.window-holster"

    function toggle(): string {
      Quickshell.execDetached([root.scriptPath, "toggle"])
      return "toggled"
    }

    function cycle(): string {
      Quickshell.execDetached([root.scriptPath, "cycle", "next"])
      return "cycling next"
    }

    function cycleNext(): string {
      Quickshell.execDetached([root.scriptPath, "cycle", "next"])
      return "cycling next"
    }

    function cyclePrev(): string {
      Quickshell.execDetached([root.scriptPath, "cycle", "prev"])
      return "cycling prev"
    }

    function toggleRole(): string {
      Quickshell.execDetached([root.scriptPath, "toggle-role"])
      return "toggled"
    }

    function activate(slot: int): string {
      Quickshell.execDetached([root.scriptPath, "activate", String(slot)])
      return "activating " + slot
    }

    function select(): string {
      Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "omarchy-window-holster"])
      return "select toggled"
    }

    function showHud(): string {
      Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omarchy-window-holster", "{}"])
      return "hud shown"
    }

    function hideHud(): string {
      Quickshell.execDetached(["omarchy-shell", "shell", "hide", "omarchy-window-holster"])
      return "hud hidden"
    }

    function toggleHud(): string {
      Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "omarchy-window-holster"])
      return "hud toggled"
    }

    function resetAll(): string {
      Quickshell.execDetached([root.scriptPath, "reset-all"])
      return "reset all"
    }
  }
}
