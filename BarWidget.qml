import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarIconButton {
  id: root

  property var shell: null
  property var service: null
  readonly property string homePath: Quickshell.env("HOME") || ""
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || (root.homePath ? (root.homePath + "/.local/share/omarchy") : "")
  readonly property string tuiBinPath: String(Qt.resolvedUrl("bin/omarchy-mc-4bars")).replace(/^file:\/\//, "")

  function omarchyBin(name) {
    return root.omarchyPath ? (root.omarchyPath + "/bin/" + name) : name
  }

  text: "󰕮"
  tooltipText: "MC 4Bars — Left: GUI | Middle: Toggle Bars | Right: TUI"

  onPressed: function(button) {
    if (button === Qt.LeftButton) {
      if (root.shell && typeof root.shell.toggle === "function") {
        root.shell.toggle("io.github.layolayo.mc-4bars", {})
      } else {
        Quickshell.execDetached([root.omarchyBin("omarchy-shell"), "shell", "toggle", "io.github.layolayo.mc-4bars", "{}"])
      }
    } else if (button === Qt.MiddleButton) {
      if (root.service && typeof root.service.toggleAllSecondaryBars === "function") {
        root.service.toggleAllSecondaryBars()
      } else {
        Quickshell.execDetached([root.omarchyBin("omarchy-shell"), "io.github.layolayo.mc-4bars", "toggle"])
      }
    } else if (button === Qt.RightButton) {
      Quickshell.execDetached([
        root.omarchyBin("omarchy-launch-floating-terminal-with-presentation"),
        "/usr/bin/python3",
        root.tuiBinPath,
        "tui"
      ])
    }
  }
}
