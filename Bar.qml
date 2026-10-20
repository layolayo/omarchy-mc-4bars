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
    atomicWrites: true
    printErrors: false
    onLoaded: root.syncFromDiskConfig()
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

  function findUnoccupiedEdge(config) {
    var allEdges = ["top", "bottom", "left", "right"]
    var slots = ["bar", "bottomBar", "leftBar", "rightBar"]
    var used = ({})
    for (var i = 0; i < slots.length; i++) {
      var k = slots[i]
      if (Util.isPlainObject(config[k])) {
        var pos = BarModel.normalizePosition(config[k].position || defaultPositionFor(k))
        used[pos] = true
      }
    }
    for (var j = 0; j < allEdges.length; j++) {
      if (!used[allEdges[j]]) return allEdges[j]
    }
    return ""
  }

  Timer {
    id: hostReloadTimer
    interval: 80
    repeat: false
    onTriggered: Util.execArgv([root.omarchyBin("omarchy-shell"), "-q", "shell", "reloadConfig"])
  }

  function readCurrentConfig() {
    var raw = String(coordinatorConfigFile.text() || "").trim()
    if (raw) {
      try {
        var parsed = JSON.parse(raw)
        if (Util.isPlainObject(parsed)) return ensureAllBarSlots(parsed)
      } catch (e) {}
    }
    if (Util.isPlainObject(root.cachedConfig)) {
      return ensureAllBarSlots(JSON.parse(JSON.stringify(root.cachedConfig)))
    }
    return null
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

  function syncFromDiskConfig() {
    if (root.suppressSwapWatch) return
    var raw = String(coordinatorConfigFile.text() || "").trim()
    if (!raw) return
    try {
      var config = JSON.parse(raw)
      if (!Util.isPlainObject(config)) return
      ensureAllBarSlots(config)

      // Only if the Primary Bar ('bar') was moved directly onto a secondary bar's edge
      // will two bars share the same edge while another edge is unoccupied.
      // Resolving that collision by moving the displaced secondary bar to the unoccupied
      // edge is 100% idempotent and can never loop.
      var primaryEdge = BarModel.normalizePosition((config.bar && config.bar.position) || "top")
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
        var freeEdge = findUnoccupiedEdge(config)
        if (!freeEdge && root.lastPrimaryEdge !== "" && root.lastPrimaryEdge !== primaryEdge) {
          freeEdge = root.lastPrimaryEdge
        }
        if (freeEdge && freeEdge !== primaryEdge) {
          config[conflictSlot].position = freeEdge
          persistAndApplyConfig(config, false)
          return
        }
      }

      root.cachedConfig = JSON.parse(JSON.stringify(config))
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
      Util.execArgv([root.omarchyBin("omarchy-toggle-bar"), "toggle"])
      return "toggled-primary"
    }
    return "empty"
  }

  function showEdgeVisibility(edgeRaw) {
    var edge = BarModel.normalizePosition(edgeRaw)
    var sbar = secondaryBarAtEdge(edge)
    if (sbar) return sbar.showBar()
    if (root.lastPrimaryEdge === edge || edge === "top") {
      Util.execArgv([root.omarchyBin("omarchy-toggle-bar"), "off"])
      return "visible"
    }
    return "empty"
  }

  function hideEdgeVisibility(edgeRaw) {
    var edge = BarModel.normalizePosition(edgeRaw)
    var sbar = secondaryBarAtEdge(edge)
    if (sbar) return sbar.hideBar()
    if (root.lastPrimaryEdge === edge || edge === "top") {
      Util.execArgv([root.omarchyBin("omarchy-toggle-bar"), "on"])
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
    primaryBarHiddenProbe.running = true
    primaryFullscreenDesktopProbe.running = true
    root.refreshPrimaryFullscreenState()
    for (var i = 0; i < secondaryBars.length; i++) {
      secondaryBars[i].syncHiddenState()
    }
  }

  property bool primaryBarFlagHidden: false
  property bool primaryAutoHidByFullscreen: false
  property bool primaryFullscreenDesktop: false
  property int primaryHyprFullscreenSerial: 0

  function omarchyBin(name) {
    return root.omarchyPath ? (root.omarchyPath + "/bin/" + name) : name
  }

  readonly property bool primaryScreenFullscreen: {
    var serial = root.primaryHyprFullscreenSerial
    var screens = Quickshell.screens
    for (var s = 0; s < screens.length; s++) {
      var monitor = Hyprland.monitorFor(screens[s])
      var activeWorkspace = monitor ? monitor.activeWorkspace : null
      if (!activeWorkspace) continue
      var wsIpc = activeWorkspace.lastIpcObject
      if (wsIpc && wsIpc.hasfullscreen) return true
      var workspaceId = activeWorkspace.id
      var toplevels = Hyprland.toplevels.values
      for (var i = 0; i < toplevels.length; i++) {
        var toplevel = toplevels[i]
        if (!toplevel || !toplevel.workspace || toplevel.workspace.id !== workspaceId) continue
        var ipc = toplevel.lastIpcObject
        var fs = ipc && ipc.fullscreen ? Number(ipc.fullscreen) : 0
        var fsc = ipc && ipc.fullscreenClient ? Number(ipc.fullscreenClient) : 0
        if (Math.max(fs, fsc) >= 2) return true
      }
    }
    return false
  }

  readonly property bool primaryFullscreenActive: root.primaryFullscreenDesktop || root.primaryScreenFullscreen

  onPrimaryFullscreenActiveChanged: root.applyPrimaryBarHidden()

  function applyPrimaryBarHidden() {
    var fsActive = root.primaryFullscreenActive
    if (fsActive) {
      if (!root.primaryBarFlagHidden && !root.primaryAutoHidByFullscreen) {
        root.primaryAutoHidByFullscreen = true
        Util.execArgv([root.omarchyBin("omarchy-toggle"), "mc-4bars-auto-bar-off", "on"])
        Util.execArgv([root.omarchyBin("omarchy-toggle-bar"), "on"])
      } else if (root.primaryAutoHidByFullscreen && !root.primaryBarFlagHidden) {
        Util.execArgv([root.omarchyBin("omarchy-toggle-bar"), "on"])
      }
    } else {
      if (root.primaryAutoHidByFullscreen) {
        root.primaryAutoHidByFullscreen = false
        Util.execArgv([root.omarchyBin("omarchy-toggle"), "mc-4bars-auto-bar-off", "off"])
        Util.execArgv([root.omarchyBin("omarchy-toggle-bar"), "off"])
      }
    }
  }

  Process {
    id: primaryAutoHideMarkerProbe
    running: true
    command: ["/usr/bin/test", "-f", root.home + "/.local/state/omarchy/toggles/mc-4bars-auto-bar-off"]
    onExited: function(exitCode) {
      root.primaryAutoHidByFullscreen = (exitCode === 0)
      root.applyPrimaryBarHidden()
    }
  }

  Process {
    id: primaryBarHiddenProbe
    running: true
    command: ["/usr/bin/test", "-f", root.home + "/.local/state/omarchy/toggles/bar-off"]
    onExited: function(exitCode) {
      root.primaryBarFlagHidden = (exitCode === 0)
      if (!root.primaryFullscreenActive && !root.primaryBarFlagHidden && root.primaryAutoHidByFullscreen) {
        root.primaryAutoHidByFullscreen = false
        Util.execArgv([root.omarchyBin("omarchy-toggle"), "mc-4bars-auto-bar-off", "off"])
      }
      root.applyPrimaryBarHidden()
    }
  }

  Process {
    id: primaryFullscreenDesktopProbe
    running: true
    command: ["/usr/bin/test", "-f", root.home + "/.local/state/omarchy/toggles/hypr/window-no-gaps.lua"]
    onExited: function(exitCode) {
      root.primaryFullscreenDesktop = (exitCode === 0)
      root.applyPrimaryBarHidden()
    }
  }

  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: primaryBarHiddenProbe.running = true
  }

  FileView {
    path: root.home + "/.local/state/omarchy/toggles/hypr"
    watchChanges: true
    printErrors: false
    onFileChanged: primaryFullscreenDesktopProbe.running = true
  }

  Timer {
    id: primaryHyprFollowupTimer
    interval: 60
    repeat: false
    onTriggered: {
      root.primaryHyprFullscreenSerial += 1
      root.applyPrimaryBarHidden()
    }
  }

  Timer {
    interval: 350
    running: true
    repeat: false
    onTriggered: root.refreshPrimaryFullscreenState()
  }

  Timer {
    interval: 1500
    running: true
    repeat: false
    onTriggered: root.refreshPrimaryFullscreenState()
  }

  function refreshPrimaryFullscreenState() {
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    root.primaryHyprFullscreenSerial += 1
    root.applyPrimaryBarHidden()
    primaryHyprFollowupTimer.restart()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "fullscreen" || name === "workspace" || name === "workspacev2" ||
          name === "focusedmon" || name === "activewindow" || name === "activewindowv2" ||
          name === "openwindow" || name === "closewindow" || name === "movewindow") {
        root.refreshPrimaryFullscreenState()
      }
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
