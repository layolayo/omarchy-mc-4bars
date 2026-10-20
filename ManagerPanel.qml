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
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: visible

  readonly property string home: Quickshell.env("HOME")
  readonly property string shellJsonPath: home + "/.config/omarchy/shell.json"

  function omarchyBin(name) {
    return root.omarchyPath ? (root.omarchyPath + "/bin/" + name) : name
  }

  function launchTui() {
    var rawUrl = String(Qt.resolvedUrl("bin/omarchy-mc-4bars"))
    var tuiPath = rawUrl.indexOf("file://") === 0 ? decodeURIComponent(rawUrl.slice(7)) : rawUrl
    root.close()
    Quickshell.execDetached([root.omarchyBin("omarchy-launch-floating-terminal-with-presentation"), "/usr/bin/python3", tuiPath, "tui"])
  }

  property var shellConfig: ({})
  property string activeBarTab: "bar" // "bar" (Top) | "bottomBar" (Bottom) | "leftBar" (Left) | "rightBar" (Right)
  property string pendingRemoveId: ""

  readonly property var barSlotKeys: ["bar", "bottomBar", "leftBar", "rightBar"]

  visible: false
  color: "transparent"
  surfaceFormat.opaque: false
  implicitWidth: 920
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
    atomicWrites: true
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
    if (!Array.isArray(cfg.plugins)) cfg.plugins = []
    var hasSelf = false
    for (var p = 0; p < cfg.plugins.length; p++) {
      if (BarModel.entryId(cfg.plugins[p]) === "io.github.layolayo.mc-4bars") {
        hasSelf = true
        break
      }
    }
    if (!hasSelf) cfg.plugins.push({ id: "io.github.layolayo.mc-4bars" })
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
    if (!raw && BarModel.isPlainObject(root.shellConfig) && root.shellConfig.version === 1) {
      raw = JSON.stringify(root.shellConfig)
    }
    if (!raw) return
    try {
      var cfg = JSON.parse(raw)
      if (!BarModel.isPlainObject(cfg)) return
      ensureBarSlots(cfg)
      mutator(cfg)
      cfg.version = 1
      root.shellConfig = cfg
      shellConfigFile.setText(JSON.stringify(cfg, null, 2) + "\n")
      if (root.service && typeof root.service.reloadAllBars === "function") {
        root.service.reloadAllBars()
      } else {
        Quickshell.execDetached([root.omarchyBin("omarchy-shell"), "-q", "io.github.layolayo.mc-4bars", "reloadConfig"])
      }
      if (rescanPrimaryBar) {
        Quickshell.execDetached([root.omarchyBin("omarchy-shell"), "-q", "shell", "reloadConfig"])
      }
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

  function layoutHasTray(layout) {
    if (!layout) return false
    var secs = ["left", "center", "right"]
    for (var s = 0; s < secs.length; s++) {
      var arr = Array.isArray(layout[secs[s]]) ? layout[secs[s]] : []
      for (var i = 0; i < arr.length; i++) {
        if (BarModel.entryId(arr[i]) === "omarchy.tray") return true
      }
    }
    return false
  }

  function barHasTray(barKey) {
    var barObj = root.shellConfig && root.shellConfig[barKey] ? root.shellConfig[barKey] : null
    return layoutHasTray(barObj ? barObj.layout : null)
  }

  function moveWidget(pluginId, destBarKey, destSection) {
    if (!BarModel.isSafePluginId(pluginId)) return
    Qt.callLater(function() {
      mutateShellConfig(function(cfg) {
        var entry = null
        for (var i = 0; i < root.barSlotKeys.length; i++) {
          var k = root.barSlotKeys[i]
          var popped = popEntryFromLayout(cfg[k].layout, pluginId)
          if (popped !== null && entry === null) entry = popped
        }
        if (entry === null) entry = { id: pluginId }
        var targetLayout = cfg[destBarKey].layout
        var finalSec = destSection
        if (finalSec === "tray" && (!layoutHasTray(targetLayout) || pluginId === "omarchy.tray")) {
          finalSec = destBarKey === "bar" ? "right" : "center"
        }
        if (!Array.isArray(targetLayout[finalSec])) targetLayout[finalSec] = []
        targetLayout[finalSec].push(entry)
      }, true)
    })
  }

  function shiftWidget(barKey, section, index, delta) {
    Qt.callLater(function() {
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
    })
  }

  function removeWidget(barKey, pluginId) {
    root.pendingRemoveId = ""
    Qt.callLater(function() {
      mutateShellConfig(function(cfg) {
        popEntryFromLayout(cfg[barKey].layout, pluginId)
      }, barKey === "bar")
    })
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
            textFormat: Text.PlainText
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: 16
            font.bold: true
            Layout.fillWidth: true
          }

          Rectangle {
            implicitWidth: tuiBtnLabel.implicitWidth + 24
            Layout.preferredWidth: implicitWidth
            Layout.minimumWidth: implicitWidth
            height: 28
            radius: 5
            color: tuiBtnMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            border.color: Commons.Color.accent

            Text {
              id: tuiBtnLabel
              anchors.centerIn: parent
              text: "Open TUI"
              textFormat: Text.PlainText
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: 12
            }

            MouseArea {
              id: tuiBtnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.launchTui()
            }
          }

          Rectangle {
            implicitWidth: toggleEdgeLabel.implicitWidth + 28
            Layout.preferredWidth: implicitWidth
            Layout.minimumWidth: implicitWidth
            height: 28
            radius: 5
            color: toggleEdgeMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            border.color: Commons.Color.accent

            Text {
              id: toggleEdgeLabel
              anchors.centerIn: parent
              text: "Toggle " + root.barEdge(root.activeBarTab)
              textFormat: Text.PlainText
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: 12
            }

            MouseArea {
              id: toggleEdgeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.service && typeof root.service.toggleEdgeVisibility === "function") {
                  root.service.toggleEdgeVisibility(root.barEdge(root.activeBarTab))
                } else {
                  Quickshell.execDetached([root.omarchyBin("omarchy-shell"), "io.github.layolayo.mc-4bars", "toggleEdge", root.barEdge(root.activeBarTab)])
                }
              }
            }
          }

          Rectangle {
            implicitWidth: toggleAllLabel.implicitWidth + 28
            Layout.preferredWidth: implicitWidth
            Layout.minimumWidth: implicitWidth
            height: 28
            radius: 5
            color: toggleAllMouse.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            border.color: Commons.Color.accent

            Text {
              id: toggleAllLabel
              anchors.centerIn: parent
              text: "Toggle All"
              textFormat: Text.PlainText
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: 12
            }

            MouseArea {
              id: toggleAllMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.service && typeof root.service.toggleAllSecondaryBars === "function") {
                  root.service.toggleAllSecondaryBars()
                } else {
                  Quickshell.execDetached([root.omarchyBin("omarchy-shell"), "io.github.layolayo.mc-4bars", "toggle"])
                }
              }
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
              textFormat: Text.PlainText
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: 13
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

        // 4 Bar Tabs (Top, Bottom, Left, Right)
        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Repeater {
            model: [
              { key: "bar", title: "Top Bar" },
              { key: "bottomBar", title: "Bottom Bar" },
              { key: "leftBar", title: "Left Bar" },
              { key: "rightBar", title: "Right Bar" }
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
                  textFormat: Text.PlainText
                  color: selected ? Commons.Color.background : Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: 12
                  font.bold: true
                }

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: count > 0 ? (count + (count === 1 ? " widget (active)" : " widgets (active)")) : "0 widgets (dormant)"
                  textFormat: Text.PlainText
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
              textFormat: Text.PlainText
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: 12
            }

            Repeater {
              model: ["top", "bottom", "left", "right"]
              delegate: Rectangle {
                required property string modelData
                readonly property bool current: root.barEdge(root.activeBarTab) === modelData
                implicitWidth: Math.max(58, edgeBtnLabel.implicitWidth + 18)
                Layout.preferredWidth: implicitWidth
                height: 26
                radius: 4
                color: current ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.08)

                Text {
                  id: edgeBtnLabel
                  anchors.centerIn: parent
                  text: modelData
                  textFormat: Text.PlainText
                  color: current ? Commons.Color.background : Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: 12
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
              textFormat: Text.PlainText
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: 12
            }

            Repeater {
              model: ["none", "glassy", "opaque"]
              delegate: Rectangle {
                required property string modelData
                readonly property bool current: root.barBackground(root.activeBarTab) === modelData
                implicitWidth: Math.max(58, bgBtnLabel.implicitWidth + 18)
                Layout.preferredWidth: implicitWidth
                height: 26
                radius: 4
                color: current ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.08)

                Text {
                  id: bgBtnLabel
                  anchors.centerIn: parent
                  text: modelData
                  textFormat: Text.PlainText
                  color: current ? Commons.Color.background : Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: 12
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

        // Columns: L/M/R (+ Tray if omarchy.tray is on this bar) or T/M/B (+ Tray) on vertical bars
        RowLayout {
          id: columnsRow
          readonly property bool isVerticalBar: {
            var e = root.barEdge(root.activeBarTab)
            return e === "left" || e === "right"
          }
          readonly property bool hasTray: root.barHasTray(root.activeBarTab)
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 10

          Repeater {
            model: [
              { key: "left", titleH: "Left (L)", titleV: "Top (T)" },
              { key: "center", titleH: "Middle (M)", titleV: "Middle (M)" },
              { key: "right", titleH: "Right (R)", titleV: "Bottom (B)" },
              { key: "tray", titleH: "Tray", titleV: "Tray" }
            ]
            delegate: Rectangle {
              id: secCol
              required property var modelData
              readonly property string secKey: modelData.key
              readonly property string colTitle: columnsRow.isVerticalBar ? modelData.titleV : modelData.titleH
              readonly property var items: root.sectionEntries(root.activeBarTab, secKey)
              visible: secKey !== "tray" || columnsRow.hasTray || items.length > 0
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
                  textFormat: Text.PlainText
                  color: Commons.Color.accent
                  font.family: Style.font.family
                  font.pixelSize: 13
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
                    readonly property bool confirmingDelete: root.pendingRemoveId === (root.activeBarTab + ":" + wid)
                    width: ListView.view.width
                    height: 68
                    radius: 4
                    color: confirmingDelete ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.16) : Qt.rgba(1, 1, 1, 0.06)

                    ColumnLayout {
                      anchors.fill: parent
                      anchors.margins: 5
                      spacing: 3

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                          text: wid.indexOf(".") !== -1 ? wid.split(".").pop() : wid
                          textFormat: Text.PlainText
                          color: Commons.Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: 12
                          font.bold: true
                        }

                        Text {
                          visible: wid.indexOf(".") !== -1 && !confirmingDelete
                          text: wid
                          textFormat: Text.PlainText
                          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.55)
                          font.family: Style.font.family
                          font.pixelSize: 10
                          elide: Text.ElideMiddle
                          Layout.fillWidth: true
                        }

                        Item {
                          visible: wid.indexOf(".") === -1 || confirmingDelete
                          Layout.fillWidth: true
                        }

                        // Inline Remove with Confirmation
                        RowLayout {
                          spacing: 3

                          Rectangle {
                            visible: !confirmingDelete
                            width: 18
                            height: 16
                            radius: 3
                            color: delBtnMouse.containsMouse ? Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.35) : Qt.rgba(1, 1, 1, 0.1)
                            Text { anchors.centerIn: parent; text: "✕"; textFormat: Text.PlainText; color: Commons.Color.foreground; font.pixelSize: 9 }
                            MouseArea {
                              id: delBtnMouse
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.pendingRemoveId = root.activeBarTab + ":" + wid
                            }
                          }

                          Rectangle {
                            visible: confirmingDelete
                            implicitWidth: confirmYesText.implicitWidth + 10
                            height: 16
                            radius: 3
                            color: Commons.Color.urgent
                            Text {
                              id: confirmYesText
                              anchors.centerIn: parent
                              text: "Remove?"
                              textFormat: Text.PlainText
                              color: Commons.Color.background
                              font.family: Style.font.family
                              font.pixelSize: 9
                              font.bold: true
                            }
                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.removeWidget(root.activeBarTab, wid)
                            }
                          }

                          Rectangle {
                            visible: confirmingDelete
                            implicitWidth: confirmNoText.implicitWidth + 10
                            height: 16
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.16)
                            Text {
                              id: confirmNoText
                              anchors.centerIn: parent
                              text: "Cancel"
                              textFormat: Text.PlainText
                              color: Commons.Color.foreground
                              font.family: Style.font.family
                              font.pixelSize: 9
                            }
                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.pendingRemoveId = ""
                            }
                          }
                        }
                      }

                      // Row 1: Section L/M/R/Tray (or T/M/B/Tray on vertical bars) + Reorder arrows
                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Repeater {
                          model: [
                            { s: "left", lH: "L", lV: "T" },
                            { s: "center", lH: "M", lV: "M" },
                            { s: "right", lH: "R", lV: "B" },
                            { s: "tray", lH: "Tr", lV: "Tr" }
                          ]
                          delegate: Rectangle {
                            required property var modelData
                            readonly property bool activeSec: modelData.s === secCol.secKey
                            visible: modelData.s !== "tray" || (columnsRow.hasTray && wid !== "omarchy.tray")
                            width: 22
                            height: 17
                            radius: 3
                            color: activeSec ? Commons.Color.accent : Qt.rgba(1, 1, 1, 0.12)

                            Text {
                              anchors.centerIn: parent
                              text: columnsRow.isVerticalBar ? modelData.lV : modelData.lH
                              textFormat: Text.PlainText
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
                          width: 22
                          height: 17
                          radius: 3
                          color: Qt.rgba(1, 1, 1, 0.12)
                          Text {
                            anchors.centerIn: parent
                            text: columnsRow.isVerticalBar ? "↑" : "←"
                            textFormat: Text.PlainText
                            color: Commons.Color.foreground
                            font.pixelSize: 10
                          }
                          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.shiftWidget(root.activeBarTab, secCol.secKey, index, -1) }
                        }

                        Rectangle {
                          width: 22
                          height: 17
                          radius: 3
                          color: Qt.rgba(1, 1, 1, 0.12)
                          Text {
                            anchors.centerIn: parent
                            text: columnsRow.isVerticalBar ? "↓" : "→"
                            textFormat: Text.PlainText
                            color: Commons.Color.foreground
                            font.pixelSize: 10
                          }
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
                              textFormat: Text.PlainText
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
