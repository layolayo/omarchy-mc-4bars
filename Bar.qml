import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import qs.Commons
import "BarModel.js" as BarModel

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var shell: null
  property var manifest: null

  property string home: Quickshell.env("HOME")
  property string omarchyConfigDir: home + "/.config/omarchy"
  property string lastPrimaryEdge: ""
  property bool suppressSwapWatch: false
  property double lastGlobalToggleMs: 0

  readonly property var secondaryBars: [bottomBarInstance, leftBarInstance, rightBarInstance]

  SecondaryBar {
    id: bottomBarInstance
    barKey: "bottomBar"
    defaultPosition: "bottom"
    toggleFlag: "bottom-bar-off"
    controller: root
    omarchyPath: root.omarchyPath
    barWidgetRegistry: root.barWidgetRegistry
    pluginRegistry: root.pluginRegistry
    shell: root.shell
    manifest: root.manifest
  }

  SecondaryBar {
    id: leftBarInstance
    barKey: "leftBar"
    defaultPosition: "left"
    toggleFlag: "left-bar-off"
    controller: root
    omarchyPath: root.omarchyPath
    barWidgetRegistry: root.barWidgetRegistry
    pluginRegistry: root.pluginRegistry
    shell: root.shell
    manifest: root.manifest
  }

  SecondaryBar {
    id: rightBarInstance
    barKey: "rightBar"
    defaultPosition: "right"
    toggleFlag: "right-bar-off"
    controller: root
    omarchyPath: root.omarchyPath
    barWidgetRegistry: root.barWidgetRegistry
    pluginRegistry: root.pluginRegistry
    shell: root.shell
    manifest: root.manifest
  }

  FileView {
    id: coordinatorConfigFile
    path: root.omarchyConfigDir + "/shell.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.checkPrimaryBarSwap()
    onFileChanged: reload()
  }

  function defaultPositionFor(slotKey) {
    if (slotKey === "bar") return "top"
    if (slotKey === "bottomBar") return "bottom"
    if (slotKey === "leftBar") return "left"
    if (slotKey === "rightBar") return "right"
    return "bottom"
  }

  function ensureAllBarSlots(config) {
    var slots = ["bar", "bottomBar", "leftBar", "rightBar"]
    var usedEdges = ({})
    for (var i = 0; i < slots.length; i++) {
      var key = slots[i]
      var defPos = defaultPositionFor(key)
      if (!Util.isPlainObject(config[key])) {
        config[key] = {
          position: defPos,
          background: "none",
          layout: { left: [], center: [], right: [] }
        }
      }
      var pos = BarModel.normalizePosition(config[key].position || defPos)
      config[key].position = pos
      if (!Util.isPlainObject(config[key].layout)) {
        config[key].layout = { left: [], center: [], right: [] }
      }
      usedEdges[pos] = (usedEdges[pos] || 0) + 1
    }
    return config
  }

  function checkPrimaryBarSwap() {
    if (root.suppressSwapWatch) return
    var raw = String(coordinatorConfigFile.text() || "").trim()
    if (!raw) return
    try {
      var config = JSON.parse(raw)
      if (!Util.isPlainObject(config)) return
      var primaryEdge = BarModel.normalizePosition((config.bar && config.bar.position) || "top")
      if (root.lastPrimaryEdge !== "" && primaryEdge !== root.lastPrimaryEdge) {
        var oldEdge = root.lastPrimaryEdge
        root.lastPrimaryEdge = primaryEdge
        var secondarySlots = ["bottomBar", "leftBar", "rightBar"]
        var conflictSlot = ""
        for (var i = 0; i < secondarySlots.length; i++) {
          var sKey = secondarySlots[i]
          var sObj = config[sKey]
          var sPos = BarModel.normalizePosition((sObj && sObj.position) || defaultPositionFor(sKey))
          if (sPos === primaryEdge) {
            conflictSlot = sKey
            break
          }
        }
        if (conflictSlot !== "") {
          ensureAllBarSlots(config)
          config[conflictSlot].position = oldEdge
          root.suppressSwapWatch = true
          coordinatorConfigFile.setText(JSON.stringify(config, null, 2) + "\n")
          root.suppressSwapWatch = false
          root.reloadAllBars()
          return
        }
      }
      root.lastPrimaryEdge = primaryEdge
    } catch (e) {
    }
  }

  function notifyConfigMutated() {
    coordinatorConfigFile.reload()
    root.reloadAllBars()
  }

  function reloadAllBars() {
    coordinatorConfigFile.reload()
    for (var i = 0; i < secondaryBars.length; i++) {
      secondaryBars[i].reloadConfigFile()
    }
  }

  function moveOrSwapBar(sourceBarKey, targetEdgeRaw) {
    var targetEdge = BarModel.normalizePosition(targetEdgeRaw)
    var raw = String(coordinatorConfigFile.text() || "").trim()
    if (!raw) return "error"
    try {
      var config = JSON.parse(raw)
      if (!Util.isPlainObject(config)) return "error"
      ensureAllBarSlots(config)
      if (!Util.isPlainObject(config[sourceBarKey])) return "error"

      var sourceEdge = BarModel.normalizePosition(config[sourceBarKey].position || defaultPositionFor(sourceBarKey))
      if (sourceEdge === targetEdge) return "unchanged"

      var allSlots = ["bar", "bottomBar", "leftBar", "rightBar"]
      var occupantKey = ""
      for (var i = 0; i < allSlots.length; i++) {
        var k = allSlots[i]
        if (k === sourceBarKey) continue
        var pos = BarModel.normalizePosition(config[k].position || defaultPositionFor(k))
        if (pos === targetEdge) {
          occupantKey = k
          break
        }
      }

      config[sourceBarKey].position = targetEdge
      if (occupantKey !== "") {
        config[occupantKey].position = sourceEdge
      }
      if (sourceBarKey === "bar" || occupantKey === "bar") {
        root.lastPrimaryEdge = BarModel.normalizePosition(config.bar.position || "top")
      }

      config.version = 1
      root.suppressSwapWatch = true
      coordinatorConfigFile.setText(JSON.stringify(config, null, 2) + "\n")
      root.suppressSwapWatch = false
      root.reloadAllBars()
      return occupantKey !== "" ? ("swapped:" + sourceEdge + "<->" + targetEdge) : ("moved:" + targetEdge)
    } catch (e) {
      console.warn("io.github.layolayo.mc-4bars: failed to move/swap bar:", e)
      return "error"
    }
  }

  function swapEdges(edgeARaw, edgeBRaw) {
    var edgeA = BarModel.normalizePosition(edgeARaw)
    var edgeB = BarModel.normalizePosition(edgeBRaw)
    if (edgeA === edgeB) return "unchanged"
    var raw = String(coordinatorConfigFile.text() || "").trim()
    if (!raw) return "error"
    try {
      var config = JSON.parse(raw)
      if (!Util.isPlainObject(config)) return "error"
      ensureAllBarSlots(config)
      var allSlots = ["bar", "bottomBar", "leftBar", "rightBar"]
      var slotA = ""
      var slotB = ""
      for (var i = 0; i < allSlots.length; i++) {
        var k = allSlots[i]
        var pos = BarModel.normalizePosition(config[k].position || defaultPositionFor(k))
        if (pos === edgeA && !slotA) slotA = k
        else if (pos === edgeB && !slotB) slotB = k
      }
      if (!slotA) return "error"
      return moveOrSwapBar(slotA, edgeB)
    } catch (e) {
      return "error"
    }
  }

  function secondaryBarAtEdge(edgeRaw) {
    var edge = BarModel.normalizePosition(edgeRaw)
    for (var i = 0; i < secondaryBars.length; i++) {
      if (secondaryBars[i].position === edge) return secondaryBars[i]
    }
    return null
  }

  function toggleEdgeVisibility(edgeRaw) {
    var edge = BarModel.normalizePosition(edgeRaw)
    var sbar = secondaryBarAtEdge(edge)
    if (sbar) {
      return sbar.toggleBarVisibility()
    }
    if (root.lastPrimaryEdge === edge || edge === "top") {
      Util.execArgv(["omarchy-toggle-bar", "toggle"])
      return "toggled-primary"
    }
    return "empty"
  }

  function showEdgeVisibility(edgeRaw) {
    var edge = BarModel.normalizePosition(edgeRaw)
    var sbar = secondaryBarAtEdge(edge)
    if (sbar) return sbar.showBar()
    if (root.lastPrimaryEdge === edge || edge === "top") {
      Util.execArgv(["omarchy-toggle-bar", "off"])
      return "visible"
    }
    return "empty"
  }

  function hideEdgeVisibility(edgeRaw) {
    var edge = BarModel.normalizePosition(edgeRaw)
    var sbar = secondaryBarAtEdge(edge)
    if (sbar) return sbar.hideBar()
    if (root.lastPrimaryEdge === edge || edge === "top") {
      Util.execArgv(["omarchy-toggle-bar", "on"])
      return "hidden"
    }
    return "empty"
  }

  function toggleAllSecondaryBars() {
    var now = Date.now()
    if (now - root.lastGlobalToggleMs < 150) {
      return "debounced"
    }
    root.lastGlobalToggleMs = now

    var populated = []
    for (var i = 0; i < secondaryBars.length; i++) {
      if (secondaryBars[i].hasWidgets) populated.push(secondaryBars[i])
    }
    if (populated.length === 0) {
      return bottomBarInstance.toggleBarVisibility()
    }
    var anyVisible = false
    for (var j = 0; j < populated.length; j++) {
      if (!populated[j].barHidden) {
        anyVisible = true
        break
      }
    }
    for (var k = 0; k < populated.length; k++) {
      if (anyVisible) populated[k].hideBar()
      else populated[k].showBar()
    }
    return anyVisible ? "hidden" : "visible"
  }

  function showAllSecondaryBars() {
    for (var i = 0; i < secondaryBars.length; i++) {
      if (secondaryBars[i].hasWidgets || secondaryBars[i] === bottomBarInstance) {
        secondaryBars[i].showBar()
      }
    }
    return "visible"
  }

  function hideAllSecondaryBars() {
    for (var i = 0; i < secondaryBars.length; i++) {
      if (secondaryBars[i].hasWidgets || secondaryBars[i] === bottomBarInstance) {
        secondaryBars[i].hideBar()
      }
    }
    return "hidden"
  }

  function syncAllHiddenStates() {
    for (var i = 0; i < secondaryBars.length; i++) {
      secondaryBars[i].syncHiddenState()
    }
  }

  function togglePluginAcrossBars(id) {
    for (var i = 0; i < secondaryBars.length; i++) {
      if (secondaryBars[i].hasWidgets && secondaryBars[i].toggleLocalPlugin(id, "{}")) return "ok"
    }
    return bottomBarInstance.toggleLocalPlugin(id, "{}") ? "ok" : "unknown"
  }

  function summonPluginAcrossBars(id) {
    for (var i = 0; i < secondaryBars.length; i++) {
      if (secondaryBars[i].hasWidgets && secondaryBars[i].summonLocalPlugin(id, "{}")) return "ok"
    }
    return bottomBarInstance.summonLocalPlugin(id, "{}") ? "ok" : "unknown"
  }

  function hidePluginAcrossBars(id) {
    for (var i = 0; i < secondaryBars.length; i++) {
      if (secondaryBars[i].hasWidgets && secondaryBars[i].hideLocalPlugin(id)) return "ok"
    }
    return bottomBarInstance.hideLocalPlugin(id) ? "ok" : "unknown"
  }

  ShellIpc {
    target: "io.github.layolayo.mc-4bars"

    function syncHidden(): void { root.syncAllHiddenStates() }
    function toggle(): string { return root.toggleAllSecondaryBars() }
    function show(): string { return root.showAllSecondaryBars() }
    function hide(): string { return root.hideAllSecondaryBars() }
    function toggleEdge(edge: string): string { return root.toggleEdgeVisibility(edge) }
    function showEdge(edge: string): string { return root.showEdgeVisibility(edge) }
    function hideEdge(edge: string): string { return root.hideEdgeVisibility(edge) }
    function swapEdges(edgeA: string, edgeB: string): string { return root.swapEdges(edgeA, edgeB) }
    function reloadConfig(): string { root.reloadAllBars(); return "ok" }
    function togglePlugin(id: string): string { return root.togglePluginAcrossBars(id) }
    function summonPlugin(id: string): string { return root.summonPluginAcrossBars(id) }
    function hidePlugin(id: string): string { return root.hidePluginAcrossBars(id) }
  }

  ShellIpc {
    target: "io.github.layolayo.mc-2bars"

    function syncHidden(): void { root.syncAllHiddenStates() }
    function toggle(): string { return root.toggleAllSecondaryBars() }
    function show(): string { return root.showAllSecondaryBars() }
    function hide(): string { return root.hideAllSecondaryBars() }
    function toggleEdge(edge: string): string { return root.toggleEdgeVisibility(edge) }
    function showEdge(edge: string): string { return root.showEdgeVisibility(edge) }
    function hideEdge(edge: string): string { return root.hideEdgeVisibility(edge) }
    function swapEdges(edgeA: string, edgeB: string): string { return root.swapEdges(edgeA, edgeB) }
    function reloadConfig(): string { root.reloadAllBars(); return "ok" }
    function togglePlugin(id: string): string { return root.togglePluginAcrossBars(id) }
    function summonPlugin(id: string): string { return root.summonPluginAcrossBars(id) }
    function hidePlugin(id: string): string { return root.hidePluginAcrossBars(id) }
  }

  ShellIpc {
    target: "matthew.bottom-bar"

    function syncHidden(): void { root.syncAllHiddenStates() }
    function toggle(): string { return root.toggleAllSecondaryBars() }
    function show(): string { return root.showAllSecondaryBars() }
    function hide(): string { return root.hideAllSecondaryBars() }
    function toggleEdge(edge: string): string { return root.toggleEdgeVisibility(edge) }
    function showEdge(edge: string): string { return root.showEdgeVisibility(edge) }
    function hideEdge(edge: string): string { return root.hideEdgeVisibility(edge) }
    function swapEdges(edgeA: string, edgeB: string): string { return root.swapEdges(edgeA, edgeB) }
    function reloadConfig(): string { root.reloadAllBars(); return "ok" }
    function togglePlugin(id: string): string { return root.togglePluginAcrossBars(id) }
    function summonPlugin(id: string): string { return root.summonPluginAcrossBars(id) }
    function hidePlugin(id: string): string { return root.hidePluginAcrossBars(id) }
  }
}
