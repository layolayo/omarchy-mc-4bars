import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarIconButton {
  id: root

  property var shell: null
  property var service: null

  text: "󰕮"

  function tooltipText() {
    return "MC 4Bars — Quad-Edge Status Bar Manager"
  }

  onClicked: {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "io.github.layolayo.mc-4bars", "{}"])
  }
}
