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
  property var cachedConfig: null

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
    atomicWrites: false
    printErrors: false
    onLoaded: root.syncFromDiskConfig()
    onFileChanged: reload()
  }

  Connections {
    target: root.shell
    function onBarConfigChanged() {
      root.onHostBarConfigChanged()
    }
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
    }
    return config
  }

  Timer {
    id: hostReloadTimer
    interval: 60
    repeat: false
    onTriggered: Util.execArgv(["omarchy-shell", "-q", "shell", "reloadConfig"])
  }

  function readCurrentConfig() {
    var base = null
    if (Util.isPlainObject(root.cachedConfig)) {
      base = JSON.parse(JSON.stringify(root.cachedConfig))
    } else {
      var raw = String(coordinatorConfigFile.text() || "").trim()
      if (raw) {
        try {
          var parsed = JSON.parse(raw)
          if (Util.isPlainObject(parsed)) base = parsed
        } catch (e) {}
      }
    }
    if (!base) return null
    return ensureAllBarSlots(base)
  }

  function applyConfigToSecondaryBars(config) {
    if (!Util.isPlainObject(config)) return
    for (var i = 0; i < secondaryBars.length; i++) {
      var sbar = secondaryBars[i]
      if (sbar && Util.isPlainObject(config[sbar.barKey])) {
        sbar.applyConfigObject(config[sbar.barKey])
      }
    }
  }

  function persistAndApplyConfig(config, reloadHostShell) {
    ensureAllBarSlots(config)
    config.version = 1
    root.cachedConfig = JSON.parse(JSON.stringify(config))
    root.lastPrimaryEdge = BarModel.normalizePosition((config.bar && config.bar.position) || "top")
    root.suppressSwapWatch = true
    applyConfigToSecondaryBars(config)
    coordinatorConfigFile.setText(JSON.stringify(config, null, 2) + "\n")
    root.suppressSwapWatch = false
    if (reloadHostShell) {
      hostReloadTimer.restart()
    }
  }

  function onHostBarConfigChanged() {
    if (root.suppressSwapWatch) return
    if (!root.shell || !Util.isPlainObject(root.shell.barConfig)) return
    var primaryEdge = BarModel.normalizePosition(root.shell.barConfig.position || "top")
    if (root.lastPrimaryEdge !== "" && primaryEdge !== root.lastPrimaryEdge) {
      var oldEdge = root.lastPrimaryEdge
      root.lastPrimaryEdge = primaryEdge
      var config = readCurrentConfig()
      if (!config) return
      config.bar.position = primaryEdge
      var secondarySlots = ["bottomBar", "leftBar", "rightBar"]
      var conflictSlot = ""
      for (var i = 0; i < secondarySlots.length; i++) {
        var sKey = secondarySlots[i]
        var sPos = BarModel.normalizePosition((config[sKey] && config[sKey].position) || defaultPositionFor(sKey))
        if (sPos === primaryEdge) {
          conflictSlot = sKey
          break
        }
      }
      if (conflictSlot !== "") {
        config[conflictSlot].position = oldEdge
        persistAndApplyConfig(config, false)
        return
      }
      root.cachedConfig = JSON.parse(JSON.stringify(config))
    }
    root.lastPrimaryEdge = primaryEdge
  }

  function syncFromDiskConfig() {
    if (root.suppressSwapWatch) return
    var raw = String(coordinatorConfigFile.text() || "").trim()
    if (!raw) return
    try {
      var config = JSON.parse(raw)
      if (!Util.isPlainObject(config)) return
      ensureAllBarSlots(config)
      root.cachedConfig = JSON.parse(JSON.stringify(config))
      var primaryEdge = BarModel.normalizePosition((config.bar && config.bar.position) || "top")
      if (root.lastPrimaryEdge !== "" && primaryEdge !== root.lastPrimaryEdge) {
        var oldEdge = root.lastPrimaryEdge
        root.lastPrimaryEdge = primaryEdge
        var secondarySlots = ["bottomBar", "leftBar", "rightBar"]
        var conflictSlot = ""
        for (var i = 0; i < secondarySlots.length; i++) {
          var sKey = secondarySlots[i]
          var sPos = BarModel.normalizePosition((config[sKey] && config[sKey].position) || defaultPositionFor(sKey))
          if (sPos === primaryEdge) {
            conflictSlot = sKey
            break
          }
        }
        if (conflictSlot !== "") {
          config[conflictSlot].position = oldEdge
          persistAndApplyConfig(config, true)
          return
        }
      }
      root.lastPrimaryEdge = primaryEdge
      applyConfigToSecondaryBars(config)
    } catch (e) {
    }
  }

  function mutateBarSlot(slotKey, mutator) {
    if (typeof mutator !== "function") return false
    var config = readCurrentConfig()
    if (!config || !Util.isPlainObject(config[slotKey])) return false
    mutator(config[slotKey])
    persistAndApplyConfig(config, slotKey === "bar")
    return true
  }

  function notifyConfigMutated() {
    reloadAllBars()
  }

  function reloadAllBars() {
    coordinatorConfigFile.reload()
  }

  function moveOrSwapBar(sourceBarKey, targetEdgeRaw) {
    var targetEdge = BarModel.normalizePosition(targetEdgeRaw)
    var config = readCurrentConfig()
    if (!config || !Util.isPlainObject(config[sourceBarKey])) return "error"
    try {
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

      var touchedPrimary = (sourceBarKey === "bar" || occupantKey === "bar")
      persistAndApplyConfig(config, touchedPrimary)
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
    var config = readCurrentConfig()
    if (!config) return "error"
    try {
      var allSlots = ["bar", "bottomBar", "leftBar", "rightBar"]
      var slotA = ""
      for (var i = 0; i < allSlots.length; i++) {
        var k = allSlots[i]
        var pos = BarModel.normalizePosition(config[k].position || defaultPositionFor(k))
        if (pos === edgeA && !slotA) {
          slotA = k
          break
        }
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
