import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarButton {
  id: root

  property var bar: null
  property var shell: null
  property var service: null
  property var settings: ({})

  text: "󰕮"
  tooltipText: "MC 4Bars — Quad-Bar Layout Manager (Middle-click: toggle secondary bars)"

  onClicked: {
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "io.github.layolayo.mc-4bars", "{}"])
  }

  onMiddleClicked: {
    if (root.service && typeof root.service.toggleAllSecondaryBars === "function") {
      root.service.toggleAllSecondaryBars()
    } else {
      Quickshell.execDetached(["omarchy-shell", "io.github.layolayo.mc-4bars", "toggle"])
    }
  }
}
