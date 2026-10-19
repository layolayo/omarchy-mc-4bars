import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarIconButton {
  id: root

  property var shell: null
  property var service: null

  text: "󰕮"
  tooltipText: "MC 4Bars — Quad-Edge Status Bar Manager"

  onPressed: function(button) {
    if (button === Qt.LeftButton) {
      Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "io.github.layolayo.mc-4bars", "{}"])
    } else if (button === Qt.MiddleButton) {
      Quickshell.execDetached(["omarchy-shell", "io.github.layolayo.mc-4bars", "toggle"])
    }
  }
}
