import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "BarModel.js" as BarModel

PanelWindow {
  id: root

  property var service: null
  property var shell: null
  property var manifest: null
  property bool opened: visible

  readonly property string home: Quickshell.env("HOME")
  readonly property string shellJsonPath: home + "/.config/omarchy/shell.json"

  property var shellConfig: ({})
  property string activeBarTab: "bottomBar" // "bottomBar" | "leftBar" | "rightBar" | "bar"

  readonly property var barSlotKeys: ["bar", "bottomBar", "leftBar", "rightBar"]

  visible: false
  color: "transparent"
  surfaceFormat.opaque: false
  implicitWidth: 820
  implicitHeight: 600
  WlrLayershell.namespace: "omarchy-menu"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  function open(payloadJson) {
    shellConfigFile.reload()
    root.visible = true
    panelRoot.forceActiveFocus()
  }

  function close() {
    root.visible = false
  }

  FileView {
    id: shellConfigFile
    path: root.shellJsonPath
    watchChanges: true
    atomicWrites: false
    printErrors: false
    onLoaded: root.parseConfig()
    onFileChanged: reload()
  }

  function defaultPositionFor(slotKey) {
    if (slotKey === "bar") return "top"
    if (slotKey === "bottomBar") return "bottom"
    if (slotKey === "leftBar") return "left"
    if (slotKey === "rightBar") return "right"
    return "bottom"
  }

  function ensureBarSlots(cfg) {
    for (var i = 0; i < root.barSlotKeys.length; i++) {
      var k = root.barSlotKeys[i]
      var defPos = defaultPositionFor(k)
      if (!BarModel.isPlainObject(cfg[k])) {
        cfg[k] = { position: defPos, background: "none", layout: { left: [], center: [], right: [] } }
      }
      cfg[k].position = BarModel.normalizePosition(cfg[k].position || defPos)
      if (!cfg[k].background) cfg[k].background = "none"
      if (!BarModel.isPlainObject(cfg[k].layout)) {
        cfg[k].layout = { left: [], center: [], right: [] }
      }
    }
  }

  function parseConfig() {
    var raw = String(shellConfigFile.text() || "").trim()
    if (!raw) return
    try {
      var parsed = JSON.parse(raw)
      if (BarModel.isPlainObject(parsed)) {
        ensureBarSlots(parsed)
        root.shellConfig = parsed
      }
    } catch (e) {
      console.warn("io.github.layolayo.mc-4bars: ManagerPanel failed to parse shell.json:", e)
    }
  }

  function mutateShellConfig(mutator, rescanPrimaryBar) {
    var raw = String(shellConfigFile.text() || "").trim()
    if (!raw) return
    try {
      var cfg = JSON.parse(raw)
      if (!BarModel.isPlainObject(cfg)) return
      ensureBarSlots(cfg)
      mutator(cfg)
      cfg.version = 1
      root.shellConfig = cfg
      shellConfigFile.setText(JSON.stringify(cfg, null, 2) + "\n")
      if (rescanPrimaryBar) {
        Quickshell.execDetached(["omarchy-shell", "-q", "shell", "reloadConfig"])
      }
      Quickshell.execDetached(["omarchy-shell", "-q", "io.github.layolayo.mc-4bars", "reloadConfig"])
    } catch (e) {
      console.warn("io.github.layolayo.mc-4bars: ManagerPanel failed to save shell.json:", e)
    }
  }

  function popEntryFromLayout(layout, targetId) {
    var found = null
    var secs = ["left", "center", "right", "tray"]
    for (var s = 0; s < secs.length; s++) {
      var sec = secs[s]
      var arr = Array.isArray(layout[sec]) ? layout[sec] : []
      var kept = []
      for (var i = 0; i < arr.length; i++) {
        if (BarModel.entryId(arr[i]) === targetId) {
          if (found === null) found = arr[i]
        } else {
          kept.push(arr[i])
        }
      }
      layout[sec] = kept
    }
    return found
  }

  function moveWidget(pluginId, destBarKey, destSection) {
    if (!BarModel.isSafePluginId(pluginId)) return
    mutateShellConfig(function(cfg) {
      var entry = null
      for (var i = 0; i < root.barSlotKeys.length; i++) {
        var k = root.barSlotKeys[i]
        var popped = popEntryFromLayout(cfg[k].layout, pluginId)
        if (popped !== null && entry === null) entry = popped
      }
      if (entry === null) entry = { id: pluginId }
      var targetLayout = cfg[destBarKey].layout
      if (!Array.isArray(targetLayout[destSection])) targetLayout[destSection] = []
      targetLayout[destSection].push(entry)
    }, true)
  }

  function shiftWidget(barKey, section, index, delta) {
    mutateShellConfig(function(cfg) {
      var layout = cfg[barKey].layout
      var arr = Array.isArray(layout[section]) ? layout[section] : []
      var targetIdx = index + delta
      if (index < 0 || index >= arr.length || targetIdx < 0 || targetIdx >= arr.length) return
      var item = arr[index]
      arr.splice(index, 1)
      arr.splice(targetIdx, 0, item)
      layout[section] = arr
    }, barKey === "bar")
  }

  function setBarEdgeOrSwap(barKey, targetEdgeRaw) {
    var targetEdge = BarModel.normalizePosition(targetEdgeRaw)
    mutateShellConfig(function(cfg) {
      var sourceEdge = BarModel.normalizePosition(cfg[barKey].position || defaultPositionFor(barKey))
      if (sourceEdge === targetEdge) return
      var occupantKey = ""
      for (var i = 0; i < root.barSlotKeys.length; i++) {
        var k = root.barSlotKeys[i]
        if (k === barKey) continue
        var pos = BarModel.normalizePosition(cfg[k].position || defaultPositionFor(k))
        if (pos === targetEdge) {
          occupantKey = k
          break
        }
      }
      cfg[barKey].position = targetEdge
      if (occupantKey !== "") {
        cfg[occupantKey].position = sourceEdge
      }
    }, true)
  }

  function setBarProp(barKey, prop, val) {
    mutateShellConfig(function(cfg) {
      cfg[barKey][prop] = val
    }, barKey === "bar")
  }

  function sectionEntries(barKey, section) {
    var barObj = root.shellConfig && root.shellConfig[barKey] ? root.shellConfig[barKey] : null
    var layout = barObj && barObj.layout ? barObj.layout : null
    return layout && Array.isArray(layout[section]) ? layout[section] : []
  }

  function totalWidgetsInBar(barKey) {
    return sectionEntries(barKey, "left").length
         + sectionEntries(barKey, "center").length
         + sectionEntries(barKey, "right").length
         + sectionEntries(barKey, "tray").length
  }

  function barEdge(barKey) {
    var barObj = root.shellConfig && root.shellConfig[barKey] ? root.shellConfig[barKey] : null
    return BarModel.normalizePosition((barObj && barObj.position) || defaultPositionFor(barKey))
  }

  function barBackground(barKey) {
    var barObj = root.shellConfig && root.shellConfig[barKey] ? root.shellConfig[barKey] : null
    return (barObj && barObj.background) ? barObj.background : "none"
  }

  function otherBarDestinations(currentBarKey) {
    var list = []
    var order = ["bar", "bottomBar", "leftBar", "rightBar"]
    for (var i = 0; i < order.length; i++) {
      var k = order[i]
      if (k === currentBarKey) continue
      var edge = barEdge(k)
      var shortEdge = edge === "top" ? "Top" : (edge === "bottom" ? "Bot" : (edge === "left" ? "Left" : "Right"))
      list.push({ key: k, edge: edge, label: "→" + shortEdge })
    }
    return list
  }

  Component.onCompleted: parseConfig()

  FocusScope {
    id: panelRoot
    anchors.fill: parent
    focus: true

    Keys.onEscapePressed: root.close()

    BorderSurface {
      anchors.fill: parent
      color: Commons.Color.background
      borderSpec: Border.flat(Commons.Color.accent, 2)
      radius: Style.cornerRadius

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // Header
        RowLayout {
          Layout.fillWidth: true
          spacing: 10

          Text {
            text: "󰕮  MC 4Bars — Quad-Edge Status Bar Manager"
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          Rectangle {
            width: 108
            height: 28
            radius: 5
            color: toggleEdgeMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            border.color: Commons.Color.accent

            Text {
              anchors.centerIn: parent
              text: "Toggle " + root.barEdge(root.activeBarTab)
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.small
            }

            MouseArea {
              id: toggleEdgeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: Quickshell.execDetached(["omarchy-shell", "io.github.layolayo.mc-4bars", "toggleEdge", root.barEdge(root.activeBarTab)])
            }
          }

          Rectangle {
            width: 96
            height: 28
            radius: 5
            color: toggleAllMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            border.color: Commons.Color.accent

            Text {
              anchors.centerIn: parent
              text: "Toggle All"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.small
            }

            MouseArea {
              id: toggleAllMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: Quickshell.execDetached(["omarchy-shell", "io.github.layolayo.mc-4bars", "toggle"])
            }
          }

          Rectangle {
            width: 28
            height: 28
            radius: 5
            color: closeMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.28) : Qt.rgba(1, 1, 1, 0.08)

            Text {
              anchors.centerIn: parent
              text: "✕"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }
          }
        }

        // 4 Bar Tabs
        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Repeater {
            model: [
              { key: "bottomBar", title: "Secondary 1" },
              { key: "leftBar", title: "Secondary 2" },
              { key: "rightBar", title: "Secondary 3" },
              { key: "bar", title: "Primary Bar" }
            ]
            delegate: Rectangle {
              required property var modelData
              readonly property bool selected: root.activeBarTab === modelData.key
              readonly property string currentEdge: root.barEdge(modelData.key)
              readonly property int count: root.totalWidgetsInBar(modelData.key)
              Layout.fillWidth: true
              height: 42
              radius: 5
              color: selected ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.06)
              border.width: 1
              border.color: selected ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.12)

              ColumnLayout {
                anchors.centerIn: parent
                spacing: 1

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: modelData.title + " [" + currentEdge.toUpperCase() + "]"
                  color: selected ? Commons.Color.background : Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.small
                  font.bold: true
                }

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: count > 0 ? (count + (count === 1 ? " widget (active)" : " widgets (active)")) : "0 widgets (dormant)"
                  color: selected ? Commons.Color.background : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.7)
                  font.family: Style.font.family
                  font.pixelSize: 10
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activeBarTab = modelData.key
              }
            }
          }
        }

        // Edge Move / Auto-Swap & Background Controls for Active Bar
        Rectangle {
          Layout.fillWidth: true
          height: 44
          radius: 6
          color: Qt.rgba(1, 1, 1, 0.04)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.1)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Text {
              text: "Edge (Auto-Swaps):"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.small
            }

            Repeater {
              model: ["top", "bottom", "left", "right"]
              delegate: Rectangle {
                required property string modelData
                readonly property bool current: root.barEdge(root.activeBarTab) === modelData
                width: 60
                height: 26
                radius: 4
                color: current ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.08)

                Text {
                  anchors.centerIn: parent
                  text: modelData
                  color: current ? Commons.Color.background : Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.small
                  font.bold: current
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setBarEdgeOrSwap(root.activeBarTab, modelData)
                }
              }
            }

            Item { Layout.fillWidth: true }

            Text {
              text: "Background:"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.small
            }

            Repeater {
              model: ["none", "glassy", "opaque"]
              delegate: Rectangle {
                required property string modelData
                readonly property bool current: root.barBackground(root.activeBarTab) === modelData
                width: 58
                height: 26
                radius: 4
                color: current ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.08)

                Text {
                  anchors.centerIn: parent
                  text: modelData
                  color: current ? Commons.Color.background : Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.small
                  font.bold: current
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setBarProp(root.activeBarTab, "background", modelData)
                }
              }
            }
          }
        }

        // Three columns: L/M/R for horizontal bars (top/bottom) or T/M/B for vertical bars (left/right)
        RowLayout {
          id: columnsRow
          readonly property bool isVerticalBar: {
            var e = root.barEdge(root.activeBarTab)
            return e === "left" || e === "right"
          }
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 10

          Repeater {
            model: [
              { key: "left", titleH: "Left (L)", titleV: "Top (T)" },
              { key: "center", titleH: "Middle (M)", titleV: "Middle (M)" },
              { key: "right", titleH: "Right (R)", titleV: "Bottom (B)" }
            ]
            delegate: Rectangle {
              id: secCol
              required property var modelData
              readonly property string secKey: modelData.key
              readonly property string colTitle: columnsRow.isVerticalBar ? modelData.titleV : modelData.titleH
              readonly property var items: root.sectionEntries(root.activeBarTab, secKey)
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 6
              color: Qt.rgba(1, 1, 1, 0.03)
              border.width: 1
              border.color: Qt.rgba(1, 1, 1, 0.1)

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Text {
                  text: secCol.colTitle + " (" + secCol.items.length + ")"
                  color: Commons.Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                ListView {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  clip: true
                  spacing: 5
                  model: secCol.items

                  delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property string wid: BarModel.entryId(modelData)
                    readonly property var otherBars: root.otherBarDestinations(root.activeBarTab)
                    width: ListView.view.width
                    height: 68
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.06)

                    ColumnLayout {
                      anchors.fill: parent
                      anchors.margins: 5
                      spacing: 3

                      Text {
                        text: wid
                        color: Commons.Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.small
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                      }

                      // Row 1: Section L/M/R (or T/M/B on vertical bars) + Up/Down order
                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Repeater {
                          model: [
                            { s: "left", lH: "L", lV: "T" },
                            { s: "center", lH: "M", lV: "M" },
                            { s: "right", lH: "R", lV: "B" }
                          ]
                          delegate: Rectangle {
                            required property var modelData
                            readonly property bool activeSec: modelData.s === secCol.secKey
                            width: 22
                            height: 17
                            radius: 3
                            color: activeSec ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.12)

                            Text {
                              anchors.centerIn: parent
                              text: columnsRow.isVerticalBar ? modelData.lV : modelData.lH
                              color: activeSec ? Commons.Color.background : Commons.Color.foreground
                              font.family: Style.font.family
                              font.pixelSize: 10
                              font.bold: true
                            }

                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: if (!activeSec) root.moveWidget(wid, root.activeBarTab, modelData.s)
                            }
                          }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                          width: 20
                          height: 17
                          radius: 3
                          color: Qt.rgba(1, 1, 1, 0.12)
                          Text { anchors.centerIn: parent; text: "↑"; color: Commons.Color.foreground; font.pixelSize: 10 }
                          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.shiftWidget(root.activeBarTab, secCol.secKey, index, -1) }
                        }

                        Rectangle {
                          width: 20
                          height: 17
                          radius: 3
                          color: Qt.rgba(1, 1, 1, 0.12)
                          Text { anchors.centerIn: parent; text: "↓"; color: Commons.Color.foreground; font.pixelSize: 10 }
                          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.shiftWidget(root.activeBarTab, secCol.secKey, index, 1) }
                        }
                      }

                      // Row 2: Send to any of the other 3 bars (preserving current section L/M/R)
                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Repeater {
                          model: otherBars
                          delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            height: 17
                            radius: 3
                            color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22)

                            Text {
                              anchors.centerIn: parent
                              text: modelData.label
                              color: Commons.Color.foreground
                              font.family: Style.font.family
                              font.pixelSize: 9
                            }

                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.moveWidget(wid, modelData.key, secCol.secKey)
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
