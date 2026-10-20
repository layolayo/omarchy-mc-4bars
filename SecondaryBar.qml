import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "BarModel.js" as BarModel

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var barWidgetRegistry: fallbackBarWidgetRegistry
  property var pluginRegistry: null
  property var barConfig: ({})
  property var shell: null
  property var manifest: null

  QtObject {
    id: fallbackBarWidgetRegistry
    property var widgets: ({})
    property int revision: 0
    function metadataFor(id) { return null }
  }

  property string barKey: "bottomBar"
  property string defaultPosition: "bottom"
  property string toggleFlag: "bottom-bar-off"
  property var controller: null

  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  readonly property var fallbackBarConfig: ({
    position: root.defaultPosition,
    background: "none",
    centerAnchor: "",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  readonly property bool hasWidgets: {
    var serial = barConfigSerial
    if (!layoutConfig) return false
    var l = Array.isArray(layoutConfig.left) ? layoutConfig.left.length : 0
    var c = Array.isArray(layoutConfig.center) ? layoutConfig.center.length : 0
    var r = Array.isArray(layoutConfig.right) ? layoutConfig.right.length : 0
    var t = Array.isArray(layoutConfig.tray) ? layoutConfig.tray.length : 0
    return (l + c + r + t) > 0
  }
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false
  property bool glassy: false
  property bool centerSectionHovered: false
  property int barHoverCount: 0
  readonly property bool barHovered: barHoverCount > 0
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property int barConfigSerial: 0
  property string position: root.defaultPosition
  property string fontFamily: Style.font.family
  property color themeForeground: Commons.Color.bar.text
  property color themeContrastForeground: Commons.Color.background
  property color transparentForeground: Commons.Color.bar.text
  property color foreground: themeForeground
  property color barForeground: useTransparentForeground ? transparentForeground : themeForeground
  property bool foregroundAnimationEnabled: true
  property color background: Commons.Color.bar.background
  readonly property color glassBackground: Qt.rgba(background.r, background.g, background.b, Math.min(background.a, 0.35))
  property color urgent: Commons.Color.bar.active

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: Style.duration(420); easing.type: Easing.OutCubic } }
  Behavior on background { ColorAnimation { duration: Style.duration(420); easing.type: Easing.OutCubic } }
  Behavior on urgent { ColorAnimation { duration: Style.duration(420); easing.type: Easing.OutCubic } }

  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null

  readonly property bool traySectionDragActive: !!barDragSource && !barDragSource.hostsTraySection
  readonly property bool traySectionPopoutOpen: {
    var owner = activePopout
    if (!owner) return false
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) return slot.region === "tray"
    }
    return false
  }
  property var barDragSource: null
  property var barDragTarget: null
  property var barDragTargetGeometry: null
  property bool barDragAfter: false
  property var barDragWindow: null
  property var barDragScreen: null
  property url barDragImageUrl: ""
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  property bool barMoveActive: false
  property string barMoveCandidate: ""
  property var barMoveWindow: null
  property var barMoveScreen: null
  property var clickTargets: []
  property var moduleSlots: []
  property var pluginBarApis: ({})
  readonly property var pluginObjectOwners: new Map()
  property bool pluginBarApiSyncQueued: false

  // Local manifest, service, and panel hosting for plugins placed on the bottom bar
  readonly property var _localManifestCache: new Map()
  property var _localServices: ({})
  property var _localPanels: ({})

  Item {
    id: localServiceHost
    visible: false
  }

  Component {
    id: manifestReaderComponent

    FileView {
      blockLoading: true
      printErrors: false
    }
  }

  FileView {
    id: userShellConfigFile
    path: root.omarchyConfigDir + "/shell.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.reloadBottomBarConfig()
    onLoadFailed: root.reloadBottomBarConfig()
    onFileChanged: reload()
  }

  function reloadConfigFile() {
    userShellConfigFile.reload()
  }

  function applyConfigObject(cfgObj) {
    if (Util.isPlainObject(cfgObj)) {
      root.barConfig = JSON.parse(JSON.stringify(cfgObj))
    } else {
      root.barConfig = fallbackBarConfig
    }
  }

  function reloadBottomBarConfig() {
    var raw = String(userShellConfigFile.text() || "").trim()
    if (!raw) {
      root.barConfig = fallbackBarConfig
      return
    }
    try {
      var parsed = JSON.parse(raw)
      if (Util.isPlainObject(parsed) && Util.isPlainObject(parsed[root.barKey])) {
        root.barConfig = parsed[root.barKey]
        return
      }
    } catch (e) {
      console.warn("io.github.layolayo.mc-4bars: failed to parse shell.json:", e)
    }
    root.barConfig = fallbackBarConfig
  }

  function mutateBottomBarConfig(mutator) {
    if (typeof mutator !== "function") return false
    if (root.controller && typeof root.controller.mutateBarSlot === "function") {
      return root.controller.mutateBarSlot(root.barKey, mutator)
    }
    var raw = String(userShellConfigFile.text() || "").trim()
    var config = { version: 1 }
    if (raw) {
      try {
        var parsed = JSON.parse(raw)
        if (Util.isPlainObject(parsed)) config = parsed
      } catch (e) {
        console.warn("io.github.layolayo.mc-4bars: cannot mutate malformed shell.json:", e)
        return false
      }
    }
    if (!Util.isPlainObject(config[root.barKey])) {
      config[root.barKey] = JSON.parse(JSON.stringify(fallbackBarConfig))
    }
    if (!Util.isPlainObject(config[root.barKey].layout)) {
      config[root.barKey].layout = { left: [], center: [], right: [] }
    }
    mutator(config[root.barKey])
    config.version = 1
    root.barConfig = JSON.parse(JSON.stringify(config[root.barKey]))
    userShellConfigFile.setText(JSON.stringify(config, null, 2) + "\n")
    return true
  }

  function updateBottomBarEntryInline(moduleName, settings) {
    var stripped = root.canonicalWidgetId(moduleName)
    var changed = false
    mutateBottomBarConfig(function(bbar) {
      var sections = ["left", "center", "right", "tray"]
      for (var s = 0; s < sections.length; s++) {
        var arr = bbar.layout[sections[s]] || []
        for (var i = 0; i < arr.length; i++) {
          if (arr[i] && root.canonicalWidgetId(arr[i].id) === stripped) {
            var next = { id: stripped }
            for (var k in settings) if (k !== "id") next[k] = settings[k]
            if (JSON.stringify(arr[i]) !== JSON.stringify(next)) {
              arr[i] = next
              changed = true
            }
          }
        }
      }
    })
    return changed
  }

  function sanitizePayloadJson(raw) {
    var text = String(raw || "{}").trim()
    if (!text) return "{}"
    try {
      var parsed = JSON.parse(text)
      return Util.isPlainObject(parsed) ? JSON.stringify(parsed) : "{}"
    } catch (e) {
      return "{}"
    }
  }

  function localManifestFor(pluginId) {
    var id = root.canonicalWidgetId(String(pluginId || ""))
    if (!BarModel.isSafePluginId(id) || id.indexOf("omarchy.") === 0) return null
    if (root._localManifestCache.has(id)) return root._localManifestCache.get(id)
    var dir = root.omarchyConfigDir + "/plugins/" + id
    var reader = manifestReaderComponent.createObject(null, { path: dir + "/manifest.json" })
    if (!reader) return null
    var raw = String(reader.text() || "").trim()
    reader.destroy()
    if (!raw) return null
    try {
      var parsed = JSON.parse(raw)
      if (!Util.isPlainObject(parsed) || parsed.schemaVersion !== 1) return null
      if (String(parsed.id || "") !== id) return null
      if (!Util.isPlainObject(parsed.entryPoints)) return null
      for (var epKey in parsed.entryPoints) {
        if (!BarModel.isSafeEntryPoint(parsed.entryPoints[epKey])) {
          console.warn("io.github.layolayo.mc-2bars: rejected unsafe entryPoint '" + epKey + "' in " + id)
          return null
        }
      }
      parsed.__sourceDir = dir
      root._localManifestCache.set(id, parsed)
      return parsed
    } catch (e) {
      console.warn("io.github.layolayo.mc-2bars: bad manifest for " + id + ":", e)
      return null
    }
  }

  function ensureLocalService(pluginId, manifest) {
    var key = root.canonicalWidgetId(String(pluginId || ""))
    if (!BarModel.isSafePluginId(key) || key.indexOf("omarchy.") === 0) return null
    if (root._localServices[key]) return root._localServices[key]
    var m = manifest || root.localManifestFor(key)
    if (!m || !m.entryPoints || !BarModel.isSafeEntryPoint(m.entryPoints.service)) return null
    var url = Util.fileUrl(m.__sourceDir + "/" + m.entryPoints.service)
    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    function finalize() {
      if (comp.status !== Component.Ready) {
        console.warn("io.github.layolayo.mc-2bars: service load failed for " + key + ": " + comp.errorString())
        return
      }
      var inst = comp.createObject(localServiceHost)
      if (!inst) return
      if ("omarchyPath" in inst) inst.omarchyPath = root.omarchyPath
      if ("shell" in inst) inst.shell = localShellFacade
      if ("manifest" in inst) inst.manifest = m
      if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = root.barWidgetRegistry
      if ("pluginRegistry" in inst) inst.pluginRegistry = root.pluginRegistry
      var next = ({})
      for (var sk in root._localServices) next[sk] = root._localServices[sk]
      next[key] = inst
      root._localServices = next
      if (root._localPanels[key] && "service" in root._localPanels[key]) {
        root._localPanels[key].service = inst
      }
    }
    if (comp.status === Component.Loading) {
      comp.statusChanged.connect(finalize)
      return null
    }
    finalize()
    return root._localServices[key] || null
  }

  function syncLocalPluginServices() {
    var wanted = ({})
    var regions = ["left", "center", "right", "tray"]
    for (var r = 0; r < regions.length; r++) {
      var entries = root.layoutEntries(regions[r])
      for (var i = 0; i < entries.length; i++) {
        var id = root.canonicalWidgetId(root.entryId(entries[i]))
        if (BarModel.isSafePluginId(id) && id.indexOf("omarchy.") !== 0) wanted[id] = true
      }
    }
    for (var wantedId in wanted) {
      var m = root.localManifestFor(wantedId)
      if (m && m.entryPoints && BarModel.isSafeEntryPoint(m.entryPoints.service)) {
        root.ensureLocalService(wantedId, m)
      }
    }
    for (var existingId in root._localServices) {
      if (wanted[existingId]) continue
      var inst = root._localServices[existingId]
      if (inst && typeof inst.destroy === "function") inst.destroy()
      var next = ({})
      for (var k in root._localServices) if (k !== existingId) next[k] = root._localServices[k]
      root._localServices = next
    }
  }

  function ensureLocalPanel(pluginId) {
    var key = root.canonicalWidgetId(String(pluginId || ""))
    if (!BarModel.isSafePluginId(key) || key.indexOf("omarchy.") === 0) return null
    if (root._localPanels[key]) return root._localPanels[key]
    var m = root.localManifestFor(key)
    if (!m || !m.entryPoints || !BarModel.isSafeEntryPoint(m.entryPoints.panel)) return null
    var url = Util.fileUrl(m.__sourceDir + "/" + m.entryPoints.panel)
    var comp = Qt.createComponent(url, Component.PreferSynchronous)
    if (comp.status !== Component.Ready) {
      console.warn("io.github.layolayo.mc-2bars: panel load failed for " + key + ": " + comp.errorString())
      return null
    }
    var inst = comp.createObject(localServiceHost)
    if (!inst) return null
    if ("omarchyPath" in inst) inst.omarchyPath = root.omarchyPath
    if ("bar" in inst) inst.bar = root
    if ("shell" in inst) inst.shell = localShellFacade
    if ("manifest" in inst) inst.manifest = m
    if ("barWidgetRegistry" in inst) inst.barWidgetRegistry = root.barWidgetRegistry
    if ("pluginRegistry" in inst) inst.pluginRegistry = root.pluginRegistry
    if ("service" in inst) inst.service = root._localServices[key] || root.ensureLocalService(key, m)
    var next = ({})
    for (var pk in root._localPanels) next[pk] = root._localPanels[pk]
    next[key] = inst
    root._localPanels = next
    return inst
  }

  function summonLocalPlugin(requestedId, payloadJson) {
    var key = root.canonicalWidgetId(String(requestedId || ""))
    if (!BarModel.isSafePluginId(key)) return false
    var safePayload = root.sanitizePayloadJson(payloadJson)
    if (root.summonBarWidget(key)) return true
    var panel = root.ensureLocalPanel(key)
    if (panel && typeof panel.open === "function") {
      panel.open(safePayload)
      return true
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", key, safePayload])
    return true
  }

  function hideLocalPlugin(requestedId) {
    var key = root.canonicalWidgetId(String(requestedId || ""))
    if (!BarModel.isSafePluginId(key)) return false
    if (root.hideBarWidget(key)) return true
    var panel = root._localPanels[key]
    if (panel && typeof panel.close === "function") {
      panel.close()
      return true
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "hide", key])
    return true
  }

  function isLocalPluginOpen(requestedId) {
    var key = root.canonicalWidgetId(String(requestedId || ""))
    if (!BarModel.isSafePluginId(key)) return false
    if (root.isBarWidgetOpen(key)) return true
    var panel = root._localPanels[key]
    return !!(panel && (panel.opened === true || panel.visible === true))
  }

  function toggleLocalPlugin(requestedId, payloadJson) {
    var key = root.canonicalWidgetId(String(requestedId || ""))
    if (!BarModel.isSafePluginId(key)) return false
    var safePayload = root.sanitizePayloadJson(payloadJson)
    if (root.findPanelWidget(key)) {
      return root.isBarWidgetOpen(key) ? root.hideBarWidget(key) : root.summonBarWidget(key)
    }
    var m = root.localManifestFor(key)
    if (m && m.entryPoints && BarModel.isSafeEntryPoint(m.entryPoints.panel)) {
      return root.isLocalPluginOpen(key)
        ? root.hideLocalPlugin(key)
        : root.summonLocalPlugin(key, safePayload)
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "toggle", key, safePayload])
    return true
  }

  QtObject {
    id: localShellFacade

    function serviceFor(requestedId) {
      var key = root.canonicalWidgetId(String(requestedId || ""))
      return root._localServices[key] || null
    }

    function firstPartyServiceFor(requestedId) {
      if (root.shell && typeof root.shell.firstPartyServiceFor === "function") {
        return root.shell.firstPartyServiceFor(requestedId)
      }
      return null
    }

    function summon(requestedId, payloadJson) {
      return root.summonLocalPlugin(requestedId, payloadJson)
    }

    function hide(requestedId) {
      return root.hideLocalPlugin(requestedId)
    }

    function toggle(requestedId, payloadJson) {
      return root.toggleLocalPlugin(requestedId, payloadJson)
    }

    function isOpen(requestedId) {
      return root.isLocalPluginOpen(requestedId)
    }

    function updateSettings(requestedId, settings) {
      return root.updateBottomBarEntryInline(requestedId, settings)
    }
  }

  Component {
    id: pluginBarApiComponent
    PluginBarApi { }
  }

  function publicLayoutConfig() {
    return JSON.parse(JSON.stringify(root.layoutConfig || {}))
  }

  function bindPluginBarApi(api) {
    if (!api) return
    api.foreground = Qt.binding(function() { return root.foreground })
    api.barForeground = Qt.binding(function() { return root.barForeground })
    api.background = Qt.binding(function() { return root.background })
    api.urgent = Qt.binding(function() { return root.urgent })
    api.fontFamily = Qt.binding(function() { return root.fontFamily })
    api.position = Qt.binding(function() { return root.position })
    api.vertical = Qt.binding(function() { return root.vertical })
    api.barSize = Qt.binding(function() { return root.barSize })
    api.transparent = Qt.binding(function() { return root.transparent })
    api.foregroundAnimationEnabled = Qt.binding(function() { return root.foregroundAnimationEnabled })
    api.centerSectionRevealHeld = Qt.binding(function() { return root.centerSectionRevealHeld })
    api._centerHoverRevealSuppressed = Qt.binding(function() { return root.centerHoverRevealSuppressed })
    api.traySectionDragActive = Qt.binding(function() { return root.traySectionDragActive })
    api.traySectionPopoutOpen = Qt.binding(function() { return root.traySectionPopoutOpen })
    root.syncPluginBarApiObjects(api)
  }

  function syncPluginBarApiObjects(api, layoutSnapshot) {
    if (!api) return
    api.activePopout = root.pluginOwnsBarObject(api.pluginId, root.activePopout)
      ? root.activePopout : (root.activePopout ? api.foreignPopoutMarker : null)
    api.clickTargets = root.pluginClickTargets(api.pluginId)
    api.layoutConfig = layoutSnapshot !== undefined
      ? JSON.parse(layoutSnapshot) : root.publicLayoutConfig()
  }

  function pluginObjectRecord(target) {
    return target ? (pluginObjectOwners.get(target) || null) : null
  }

  function markPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    if (!key || !target) return false
    var record = root.pluginObjectRecord(target)
    if (record && record.pluginId !== key) return false
    if (!record) {
      record = { target: target, pluginId: key, clickTarget: false, popout: false }
      pluginObjectOwners.set(target, record)
    }
    record[role] = true
    return true
  }

  function unmarkPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    var record = root.pluginObjectRecord(target)
    if (!record || record.pluginId !== key) return
    record[role] = false
    if (!record.clickTarget && !record.popout) pluginObjectOwners.delete(target)
  }

  function pluginOwnsBarObject(pluginId, target) {
    var record = target ? root.pluginObjectRecord(target) : null
    return !!record && record.pluginId === String(pluginId || "")
  }

  function pluginClickTargets(pluginId) {
    var out = []
    for (var i = 0; i < root.clickTargets.length; i++) {
      var target = root.clickTargets[i]
      if (root.pluginOwnsBarObject(pluginId, target)) out.push(target)
    }
    return out
  }

  function schedulePluginBarApiSync() {
    if (pluginBarApiSyncQueued) return
    pluginBarApiSyncQueued = true
    Qt.callLater(root.syncAllPluginBarApiObjects)
  }

  function syncAllPluginBarApiObjects() {
    pluginBarApiSyncQueued = false
    var layoutSnapshot = JSON.stringify(root.layoutConfig || {})
    for (var id in pluginBarApis) {
      var api = pluginBarApis[id]
      if (api) root.syncPluginBarApiObjects(api, layoutSnapshot)
    }
  }

  function registerPluginClickTarget(pluginId, target) {
    if (!root.markPluginObject(pluginId, target, "clickTarget")) return
    root.registerClickTarget(target)
  }

  function unregisterPluginClickTarget(pluginId, target) {
    if (!root.pluginOwnsBarObject(pluginId, target)) return
    root.unregisterClickTarget(target)
    root.unmarkPluginObject(pluginId, target, "clickTarget")
  }

  function requestPluginPopout(pluginId, owner) {
    if (!root.markPluginObject(pluginId, owner, "popout")) return
    root.requestPopout(owner)
    root.syncPluginBarApiObjects(pluginBarApis[String(pluginId || "")])
  }

  function releasePluginPopout(pluginId, owner) {
    if (!root.pluginOwnsBarObject(pluginId, owner)) return
    root.releasePopout(owner)
    root.unmarkPluginObject(pluginId, owner, "popout")
    root.syncPluginBarApiObjects(pluginBarApis[String(pluginId || "")])
  }

  function pluginBarApiFor(pluginId, moduleName, registered) {
    var key = String(pluginId || "")
    if (!key) return null

    if (pluginBarApis[key]) {
      pluginBarApis[key].shell = localShellFacade
      return pluginBarApis[key]
    }

    var api = pluginBarApiComponent.createObject(null, {
      pluginId: key,
      moduleName: String(moduleName || ""),
      shell: localShellFacade,
      _showTooltip: function(target, text) { root.showTooltip(target, text) },
      _hideTooltip: function(target) { root.hideTooltip(target) },
      _registerClickTarget: function(target) { root.registerPluginClickTarget(key, target) },
      _unregisterClickTarget: function(target) { root.unregisterPluginClickTarget(key, target) },
      _requestPopout: function(owner) { root.requestPluginPopout(key, owner) },
      _releasePopout: function(owner) { root.releasePluginPopout(key, owner) },
      _switchPanelFrom: function(owner, direction) { return root.switchPanelFrom(owner, direction) },
      _targetBelongsToWindow: function(target, window) { return root.targetBelongsToWindow(target, window) },
      _moduleWidgets: function(requestedId) {
        return String(requestedId || "") === String(moduleName || "")
          ? root.moduleWidgets(moduleName) : []
      },
      _run: function(command) { root.run(command) },
      _setCenterHoverRevealSuppressed: function(value) {
        root.centerHoverRevealSuppressed = !!value
      }
    })
    if (!api) return null
    root.bindPluginBarApi(api)

    var next = ({})
    for (var id in pluginBarApis) next[id] = pluginBarApis[id]
    next[key] = api
    pluginBarApis = next
    return api
  }

  function pluginBarApiUsed(pluginId) {
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.pluginApiId === pluginId) return true
    }
    return false
  }

  function releasePluginObjects(pluginId) {
    var owned = Array.from(pluginObjectOwners.values())
    for (var i = 0; i < owned.length; i++) {
      var record = owned[i]
      if (!record || record.pluginId !== pluginId) continue
      if (record.clickTarget) root.unregisterClickTarget(record.target)
      if (record.popout && root.activePopout === record.target) root.releasePopout(record.target)
      pluginObjectOwners.delete(record.target)
    }
  }

  function prunePluginBarApis() {
    var next = ({})
    for (var id in pluginBarApis) {
      var api = pluginBarApis[id]
      if (root.pluginBarApiUsed(id)) {
        next[id] = api
        continue
      }
      root.releasePluginObjects(id)
      if (api && typeof api.destroy === "function") api.destroy()
    }
    pluginBarApis = next
  }

  onActivePopoutChanged: schedulePluginBarApiSync()
  onClickTargetsChanged: schedulePluginBarApiSync()
  onLayoutConfigChanged: schedulePluginBarApiSync()
  onModuleSlotsChanged: Qt.callLater(prunePluginBarApis)

  Component.onDestruction: {
    for (var id in pluginBarApis) {
      root.releasePluginObjects(id)
      if (pluginBarApis[id] && typeof pluginBarApis[id].destroy === "function")
        pluginBarApis[id].destroy()
    }
    pluginBarApis = ({})
    for (var sid in root._localServices) {
      if (root._localServices[sid] && typeof root._localServices[sid].destroy === "function")
        root._localServices[sid].destroy()
    }
    root._localServices = ({})
    for (var pid in root._localPanels) {
      if (root._localPanels[pid] && typeof root._localPanels[pid].destroy === "function")
        root._localPanels[pid].destroy()
    }
    root._localPanels = ({})
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function(item) { return item !== slot })
    moduleSlots = next
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function clearBarDrag() {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen) return { x: x, y: y }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)

    return { x: x, y: y }
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null
    var thickness = Style.spacing.xs

    if (slot.isRegionDrop) {
      var sp = barDragScreenPoint({ x: slot.x, y: slot.y })
      if (vertical) {
        return {
          x: sp.x,
          y: sp.y - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }
      return {
        x: sp.x - thickness / 2,
        y: sp.y,
        width: thickness,
        height: slot.height
      }
    }

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  function nearestScreenEdge(point, screen) {
    var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
    var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

    var edge = "top"
    var best = ny
    if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
    if (nx < best) { edge = "left"; best = nx }
    if (1 - nx < best) { edge = "right"; best = 1 - nx }
    return edge
  }

  function beginBarMove(window) {
    barMoveWindow = window
    barMoveScreen = window ? window.screen : null
    barMoveCandidate = position
    barMoveActive = true
  }

  function updateBarMove(screenPoint) {
    if (!barMoveActive || !barMoveScreen) return
    barMoveCandidate = nearestScreenEdge(screenPoint, barMoveScreen)
  }

  function clearBarMove() {
    barMoveActive = false
    barMoveCandidate = ""
    barMoveWindow = null
    barMoveScreen = null
  }

  function finishBarMove() {
    var edge = barMoveCandidate
    if (!barMoveActive || !edge || edge === position) {
      clearBarMove()
      return
    }

    clearBarMove()
    setBarPosition(edge)
  }

  function setBarPosition(value) {
    var next = normalizePosition(value)
    if (root.controller && typeof root.controller.moveOrSwapBar === "function") {
      root.controller.moveOrSwapBar(root.barKey, next)
      return
    }
    root.mutateBottomBarConfig(function(bbar) {
      bbar.position = next
    })
  }

  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function") return

    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function(result) {
      if (root.barDragSource !== slot || !result || !result.url) return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  property var displayCutouts: []
  FileView {
    id: displayCutoutsFile
    path: "/usr/share/omarchy-platform/display-cutouts.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.displayCutouts = BarModel.parseCutouts(text())
    onLoadFailed: root.displayCutouts = []
    onFileChanged: reload()
  }

  function panelModeFor(screen) {
    var monitor = screen ? Hyprland.monitorFor(screen) : null
    return monitor ? ({
      width: monitor.width,
      height: monitor.height,
      transform: monitor.lastIpcObject ? monitor.lastIpcObject.transform : 0
    }) : null
  }

  function thicknessFor(screen) {
    if (root.vertical || !screen) return root.barSize
    return Math.max(root.barSize, BarModel.notchFloor(root.displayCutouts, root.position, screen.name, screen.width, screen.height, screen.devicePixelRatio, root.panelModeFor(screen), Style.bar.notchHeight))
  }

  readonly property var screenBarSizes: {
    var sizes = ({})
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) sizes[screens[i].name] = root.thicknessFor(screens[i])
    return sizes
  }

  function barSizeFor(screenName) {
    return BarModel.barSizeFor(root.screenBarSizes, screenName, root.barSize)
  }

  function normalizePosition(value) {
    return BarModel.normalizePosition(value)
  }

  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right"),
      tray:   normalized.tray
    }
  }

  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) && Object.keys(barConfig).length > 0 ? barConfig : fallbackBarConfig

    position = normalizePosition(config.position)
    var look = config.background || (config.transparent === true ? "none" : "none")
    setRequestedTransparency(look === "none")
    if (look !== "none") glassy = look === "glassy"
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")

    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta && barConfigSerial > 0) {
      applySettingsDelta(delta)
      root.syncLocalPluginServices()
      return
    }
    layoutConfig = next
    barConfigSerial++
    root.syncLocalPluginServices()
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry)) continue
        var item = slot.activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot) return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0) return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false

    nextSlot.activeItem.open()
    return true
  }

  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function") return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  function entryId(entry) {
    return BarModel.entryId(entry)
  }

  function moduleString(entry, key, fallback) {
    return BarModel.moduleString(entry, key, fallback)
  }

  function entryIndex(entries, name) {
    return BarModel.entryIndex(entries, name)
  }

  function entriesBefore(entries, name) {
    return BarModel.entriesBefore(entries, name)
  }

  function entriesAfter(entries, name) {
    return BarModel.entriesAfter(entries, name)
  }

  function canonicalWidgetId(name) {
    return Util.canonicalWidgetId(name)
  }

  Component.onCompleted: reloadBottomBarConfig()

  function setCenterSectionHovered(hovered) {
    centerSectionHovered = hovered
    if (hovered) {
      centerSectionRevealTimer.stop()
      centerSectionRevealHeld = true
    } else {
      centerSectionRevealTimer.restart()
    }
  }

  function setBarHovered(hovered) {
    barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1))
    if (barHoverCount === 0) centerSectionRevealTimer.restart()
  }

  function setCenterHoverRevealSuppressed(value) {
    centerHoverRevealSuppressed = !!value
  }

  Timer {
    id: centerSectionRevealTimer
    interval: 120
    onTriggered: if (!root.centerSectionHovered && !root.barHovered) root.centerSectionRevealHeld = false
  }

  function run(command) {
    if (!command) return
    Util.execDetached(command)
  }

  function cycleBackground() {
    root.mutateBottomBarConfig(function(bbar) {
      var cur = String(bbar.background || "none")
      var next = cur === "none" ? "glassy" : (cur === "glassy" ? "opaque" : "none")
      bbar.background = next
    })
  }

  function rawBottomLayoutSection(bbar, region) {
    if (!Util.isPlainObject(bbar.layout)) bbar.layout = {}
    if (!Array.isArray(bbar.layout[region])) bbar.layout[region] = []
    return bbar.layout[region]
  }

  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name) return i
    }
    return -1
  }

  function moveModuleInBottomBar(bbar, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawBottomLayoutSection(bbar, fromRegion)
    var toEntries = rawBottomLayoutSection(bbar, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0) return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0) toIndex = toEntries.length

    if (fromRegion === toRegion && fromIndex === toIndex) return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false

    var changed = false
    root.mutateBottomBarConfig(function(bbar) {
      changed = moveModuleInBottomBar(bbar, source.region, source.moduleName, toRegion, beforeName)
    })
    return changed
  }

  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width ||
          barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    var intoTraySection = !sourceSlot || !sourceSlot.hostsTraySection
    var candidates = []
    var seenRegions = ({})
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      if (slot.region === "tray" && !intoTraySection) continue

      seenRegions[slot.region] = true

      var dropSpace = slot.sectionDropSpace
      if (intoTraySection && dropSpace && dropSpace.visible && dropSpace.width > 0 && dropSpace.height > 0) {
        var spacePoint = dropSpace.mapToItem(null, 0, 0)
        candidates.push({ slot: dropSpace, x: spacePoint.x, y: spacePoint.y, width: dropSpace.width, height: dropSpace.height })
      }
      if (intoTraySection && slot.hostsTraySection) {
        var trayPoint = slot.mapFromItem(null, scenePoint.x, scenePoint.y)
        if (slot.traySectionContains(trayPoint.x, trayPoint.y)) continue
      }

      var slotPoint = { x: slot.x, y: slot.y }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }

      candidates.push({
        slot: slot,
        x: slotPoint.x,
        y: slotPoint.y,
        width: slot.width,
        height: slot.height
      })
    }

    // Add virtual drop zones for any empty region (left, center, right) so
    // widgets can be dragged into an empty section with the mouse.
    if (sourceWindow && sourceWindow.contentItem) {
      var w = sourceWindow.contentItem.width
      var h = sourceWindow.contentItem.height
      var regionAnchors = [
        { region: "left",   x: 16,      y: 16 },
        { region: "center", x: w / 2,   y: h / 2 },
        { region: "right",  x: w - 20,  y: h - 20 }
      ]
      for (var r = 0; r < regionAnchors.length; r++) {
        var ra = regionAnchors[r]
        if (seenRegions[ra.region]) continue
        var vSlot = {
          isRegionDrop: true,
          region: ra.region,
          moduleName: "",
          x: root.vertical ? 0 : ra.x,
          y: root.vertical ? ra.y : 0,
          width: root.vertical ? w : 4,
          height: root.vertical ? 4 : h
        }
        candidates.push({
          slot: vSlot,
          x: vSlot.x,
          y: vSlot.y,
          width: vSlot.width,
          height: vSlot.height
        })
      }
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      return slot
    }
    return null
  }

  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }
      if (visibleModuleSlot(region, name, sourceSlot)) return name
    }
    return ""
  }

  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot) return false
    if (targetSlot.isRegionDrop) {
      return dropBarModule(sourceSlot, targetSlot.region, "")
    }
    var beforeName = afterTarget ? nextVisibleModuleName(targetSlot.region, targetSlot.moduleName, sourceSlot) : targetSlot.moduleName
    return dropBarModule(sourceSlot, targetSlot.region, beforeName)
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue

      var targetPoint = { x: localX, y: localY }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width &&
          targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false

    target.triggerPress(button)
    return true
  }

  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string") c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  function setRequestedTransparency(value) {
    var nextTransparent = value === true
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    scheduleTransparentForegroundRefresh()
  }

  function restoreForegroundAnimation() {
    Qt.callLater(function() {
      Qt.callLater(function() { root.foregroundAnimationEnabled = true })
    })
  }

  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!requestedTransparent || transparentForegroundProc.running) return

    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      root.position,
      String(root.barSize),
      colorHex(root.themeForeground),
      colorHex(root.themeContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  onPositionChanged: scheduleTransparentForegroundRefresh()
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return

        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: root.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  property bool fullscreenDesktop: false
  property int hyprFullscreenSerial: 0
  property double lastToggleMs: 0

  Process {
    id: barHiddenProbe
    running: true
    command: ["test", "-f", root.home + "/.local/state/omarchy/toggles/" + root.toggleFlag]
    onExited: function(exitCode) { root.barHidden = (exitCode === 0) }
  }

  Process {
    id: fullscreenDesktopProbe
    running: true
    command: ["test", "-f", root.home + "/.local/state/omarchy/toggles/hypr/window-no-gaps.lua"]
    onExited: function(exitCode) { root.fullscreenDesktop = (exitCode === 0) }
  }

  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  FileView {
    path: root.home + "/.local/state/omarchy/toggles/hypr"
    watchChanges: true
    printErrors: false
    onFileChanged: fullscreenDesktopProbe.running = true
  }

  Timer {
    id: hyprRefreshFollowupTimer
    interval: 60
    repeat: false
    onTriggered: root.hyprFullscreenSerial += 1
  }

  function refreshHyprFullscreenState() {
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    root.hyprFullscreenSerial += 1
    hyprRefreshFollowupTimer.restart()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "fullscreen" || name === "workspace" || name === "workspacev2" ||
          name === "focusedmon" || name === "activewindow" || name === "activewindowv2" ||
          name === "openwindow" || name === "closewindow" || name === "movewindow") {
        root.refreshHyprFullscreenState()
      }
    }
  }

  function syncHiddenState() {
    barHiddenProbe.running = true
    fullscreenDesktopProbe.running = true
    root.refreshHyprFullscreenState()
  }

  function toggleBarVisibility() {
    var now = Date.now()
    if (now - root.lastToggleMs < 150) {
      return root.barHidden ? "hidden" : "visible"
    }
    root.lastToggleMs = now
    root.barHidden = !root.barHidden
    Util.execArgv(["omarchy-toggle", root.toggleFlag, root.barHidden ? "on" : "off"])
    return root.barHidden ? "hidden" : "visible"
  }

  function showBar() {
    root.lastToggleMs = Date.now()
    root.barHidden = false
    Util.execArgv(["omarchy-toggle", root.toggleFlag, "off"])
    return "visible"
  }

  function hideBar() {
    root.lastToggleMs = Date.now()
    root.barHidden = true
    Util.execArgv(["omarchy-toggle", root.toggleFlag, "on"])
    return "hidden"
  }

  Variants {
    model: root.hasWidgets ? Quickshell.screens : []

    delegate: Component {
      BarPanel {
        required property var modelData
        screen: modelData
      }
    }
  }

  Variants {
    model: root.hasWidgets ? Quickshell.screens : []

    delegate: Component {
      DragGhostPanel {
        required property var modelData
        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  Variants {
    model: root.hasWidgets ? Quickshell.screens : []

    delegate: Component {
      BarMoveGhostPanel {
        required property var modelData
        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property var activeWorkspace: monitor ? monitor.activeWorkspace : null
    onActiveWorkspaceChanged: root.refreshHyprFullscreenState()
    readonly property int workspaceId: activeWorkspace ? activeWorkspace.id : -1
    readonly property int fullscreenMode: {
      var serial = root.hyprFullscreenSerial
      var mode = 0
      var wsIpc = activeWorkspace ? activeWorkspace.lastIpcObject : null
      if (wsIpc && wsIpc.hasfullscreen) mode = 2
      var toplevels = Hyprland.toplevels.values
      for (var i = 0; i < toplevels.length; i++) {
        var toplevel = toplevels[i]
        if (!toplevel || !toplevel.workspace || toplevel.workspace.id !== workspaceId) continue
        var ipc = toplevel.lastIpcObject
        var fs = ipc && ipc.fullscreen ? Number(ipc.fullscreen) : 0
        var fsc = ipc && ipc.fullscreenClient ? Number(ipc.fullscreenClient) : 0
        mode = Math.max(mode, fs, fsc)
      }
      return mode
    }
    readonly property bool screenFullscreen: fullscreenMode >= 2
    readonly property bool effectiveHidden: root.barHidden || root.fullscreenDesktop || screenFullscreen
    onEffectiveHiddenChanged: {
      if (effectiveHidden) {
        root.clearTooltip()
        if (root.activePopout && "close" in root.activePopout) root.activePopout.close()
      }
    }

    Timer {
      interval: 300
      running: true
      repeat: false
      onTriggered: root.refreshHyprFullscreenState()
    }

    visible: !remapGuard.remapping && (cutoutWaitOver || !cutoutPending)
    exclusionMode: effectiveHidden ? ExclusionMode.Ignore : ExclusionMode.Auto
    mask: Region {
      item: !barWindow.effectiveHidden ? barContentLoader : null
    }

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    margins {
      top: effectiveHidden && root.position === "top" ? -barWindow.thickness : 0
      bottom: effectiveHidden && root.position === "bottom" ? -barWindow.thickness : 0
      left: effectiveHidden && root.position === "left" ? -barWindow.thickness : 0
      right: effectiveHidden && root.position === "right" ? -barWindow.thickness : 0
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    readonly property var panelMode: root.panelModeFor(screen)
    readonly property bool centerBesideRight: BarModel.centerBesideRight(root.displayCutouts, root.position, screen.name, screen.width, screen.height, screen.devicePixelRatio, panelMode)
    readonly property bool cutoutPending: BarModel.cutoutPending(root.displayCutouts, root.position, screen.name, screen.width, screen.height, screen.devicePixelRatio, panelMode)
    property bool cutoutWaitOver: false
    onCutoutPendingChanged: if (!cutoutPending) cutoutWaitOver = true
    Component.onCompleted: {
      if (!cutoutPending) cutoutWaitOver = true
      root.refreshHyprFullscreenState()
    }

    Timer {
      interval: 2000
      running: barWindow.cutoutPending && !barWindow.cutoutWaitOver
      onTriggered: barWindow.cutoutWaitOver = true
    }

    readonly property int thickness: root.thicknessFor(screen)

    implicitWidth: root.vertical ? thickness : 0
    implicitHeight: root.vertical ? 0 : thickness
    color: effectiveHidden || root.transparent ? "transparent" : (root.glassy ? root.glassBackground : root.background)
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    Loader {
      id: barContentLoader
      anchors.fill: parent
      visible: !barWindow.effectiveHidden
      opacity: barWindow.effectiveHidden ? 0 : 1
      sourceComponent: root.vertical ? verticalBar : horizontalBar

      HoverHandler {
        onHoveredChanged: root.setBarHovered(hovered)
        Component.onDestruction: if (hovered) root.setBarHovered(false)
      }
    }

    PopupWindow {
      id: tooltipWindow

      visible: !barWindow.effectiveHidden && root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        id: tooltipAnchor
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow)) return

          var popupWidth = tooltipWindow.implicitWidth
          var popupHeight = tooltipWindow.implicitHeight
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6

          if (root.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.position === "left") {
            localX = target.width + 6
            localY = target.height / 2 - popupHeight / 2
          } else if (root.position === "right") {
            localX = -popupWidth - 6
            localY = target.height / 2 - popupHeight / 2
          }

          var point = barWindow.contentItem.mapFromItem(target, localX, localY)
          tooltipAnchor.rect.x = Math.round(point.x)
          tooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      BorderSurface {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 14
        color: Commons.Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Commons.Color.tooltip.border, 1)
        radius: Style.cornerRadius

        Text {
          id: tooltipLabel
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.tooltipText
          color: Commons.Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Component {
      id: horizontalBar

      Item {
        anchors.fill: parent

        CenterModules {
          anchors.fill: parent
          entries: barWindow.centerBesideRight ? [] : root.layoutEntries("center")
        }

        LeftModules {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        RightModules {
          id: rightModules
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        ModuleList {
          entries: barWindow.centerBesideRight ? root.layoutEntries("center") : []
          region: "center"
          anchors.right: rightModules.left
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    Component {
      id: verticalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
      (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bottom-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    Rectangle {
      readonly property var targetRect: root.barDragTargetGeometry

      visible: ghostWindow.active && targetRect !== null
      x: targetRect ? Math.round(targetRect.x) : 0
      y: targetRect ? Math.round(targetRect.y) : 0
      width: targetRect ? targetRect.width : 0
      height: targetRect ? targetRect.height : 0
      color: Commons.Color.accent
      radius: Math.min(width, height) / 2
    }
  }

  component BarMoveGhostPanel: PanelWindow {
    id: moveGhostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barMoveScreen === ghostScreen ||
      (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
    visible: root.barMoveActive && screenMatches
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bottom-bar-move-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    mask: Region {}

    Repeater {
      model: ["top", "bottom", "left", "right"]

      BorderSurface {
        id: edgeSlab

        required property string modelData
        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
        readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

        x: modelData === "right" ? parent.width - edgeSize : 0
        y: modelData === "bottom" ? parent.height - edgeSize : 0
        width: edgeVertical ? edgeSize : parent.width
        height: edgeVertical ? parent.height : edgeSize
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        visible: opacity > 0
        opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

        Behavior on opacity {
          NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
        }
      }
    }
  }

  function findCenterAnchorEntry(entries) {
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component LeftModules: ModuleList {
    entries: root.layoutEntries("left")
    region: "left"
  }

  component RightModules: ModuleList {
    entries: root.layoutEntries("right")
    region: "right"
  }

  component CenterModules: Item {
    id: centerRoot

    property var entries: root.layoutEntries("center")
    readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry(entries)

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        Item {
          anchors.left: parent.left
          anchors.right: centerRoot.hasAnchor ? centerAnchorModule.left : parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom

          HoverHandler {
            onHoveredChanged: root.setCenterSectionHovered(hovered)
          }
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: centerRoot.hasAnchor ? centerAnchorModule.top : parent.bottom

          HoverHandler {
            onHoveredChanged: root.setCenterSectionHovered(hovered)
          }
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    id: gestureArea

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property real dragThreshold: Style.space(4)

    acceptedButtons: Qt.LeftButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
    pressAndHoldInterval: 200

    function startDrag(x, y) {
      if (dragging) return
      dragging = true
      root.beginBarMove(root.targetWindow(gestureArea))
      var scenePoint = gestureArea.mapToItem(null, x, y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
    }

    onPressAndHold: function(mouse) {
      if (!gestureArea.pressed) return
      startDrag(mouse.x, mouse.y)
    }

    onPositionChanged: function(mouse) {
      if (!(mouse.buttons & Qt.LeftButton)) return

      if (!dragging) {
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance < dragThreshold) return
        startDrag(mouse.x, mouse.y)
        return
      }

      var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onReleased: function(mouse) {
      if (!dragging) return
      dragging = false
      suppressClick = true
      root.finishBarMove()
      mouse.accepted = true
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarMove()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
      }
    }

    onDoubleClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.LeftButton) {
        root.cycleBackground()
        mouse.accepted = true
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var entries: []
    property string region: ""

    visible: entries.length > 0
    active: visible && entries.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }
  }

  Component {
    id: traySectionComponent

    ModuleList {
      entries: root.layoutEntries("tray")
      region: "tray"
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    readonly property string moduleName: root.entryId(entry)
    readonly property var localManifest: root.localManifestFor(moduleName)
    readonly property var moduleSettings: {
      var raw = root.entrySettings(entry)
      var defaults = (localManifest && localManifest.barWidget && Util.isPlainObject(localManifest.barWidget.defaults))
        ? localManifest.barWidget.defaults : {}
      var merged = {}
      for (var dk in defaults) merged[dk] = defaults[dk]
      for (var rk in raw) merged[rk] = raw[rk]
      return merged
    }
    readonly property var registryMetadata: root.barWidgetRegistry.metadataFor(root.canonicalWidgetId(moduleName))
    readonly property bool firstParty: registryMetadata && registryMetadata.firstParty === true
    readonly property string pluginApiId: registered ? root.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property string localWidgetUrl: {
      if (registered) return ""
      if (localManifest && localManifest.entryPoints && BarModel.isSafeEntryPoint(localManifest.entryPoints.barWidget)) {
        return Util.fileUrl(localManifest.__sourceDir + "/" + localManifest.entryPoints.barWidget)
      }
      return ""
    }
    readonly property bool qmlCustom: localWidgetUrl !== ""
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    readonly property real panelIndicatorExtent: {
      var mark = panelIndicatorItem
      if (mark) return Math.max(Style.space(10), Math.round((root.vertical ? mark.height : mark.width) * 0.55))
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
    }
    readonly property Item panelIndicatorItem: activeItem && "openPanelIndicatorItem" in activeItem ? activeItem.openPanelIndicatorItem : null
    readonly property real panelIndicatorCenter: {
      var mark = panelIndicatorItem
      if (!mark) return (root.vertical ? slot.height : slot.width) / 2
      var reveal = "revealProgress" in activeItem ? activeItem.revealProgress : 0
      var point = mark.mapToItem(slot, mark.width / 2, mark.height / 2)
      return root.vertical ? point.y : point.x
    }
    readonly property bool hostsTraySection: region !== "tray" && !!activeItem && "sectionHost" in activeItem
    readonly property Item sectionDropSpace: hostsTraySection && activeItem.sectionHost ? activeItem.sectionHost.dropSpace : null

    function traySectionContains(x, y) {
      var host = hostsTraySection ? activeItem.sectionHost : null
      if (!host || !host.visible || host.width <= 0 || host.height <= 0) return false
      var point = slot.mapToItem(host, x, y)
      return point.x >= 0 && point.y >= 0 && point.x <= host.width && point.y <= host.height
    }
    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : 0

    Component.onCompleted: root.registerModuleSlot(slot)
    Component.onDestruction: {
      if (root.barDragSource === slot) root.clearBarDrag()
      root.unregisterModuleSlot(slot)
    }

    HoverHandler { id: moduleHover }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.22 : 0.32
    }

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: emptyModuleComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.localWidgetUrl
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      color: Commons.Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      x: root.vertical
        ? (root.position === "left" ? parent.width - width - inset : inset)
        : Math.floor(slot.panelIndicatorCenter - width / 2)
      y: root.vertical
        ? Math.floor(slot.panelIndicatorCenter - height / 2)
        : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
      }
    }

    Loader {
      readonly property Item host: slot.hostsTraySection ? slot.activeItem.sectionHost : null
      parent: host || slot
      active: !!host
      sourceComponent: traySectionComponent
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: true
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      cursorShape: moduleHover.hovered && root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor

      onPressed: function(mouse) {
        if (slot.traySectionContains(mouse.x, mouse.y)) {
          mouse.accepted = false
          return
        }
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragTargetGeometry = drop ? root.dropMarkerRect(drop.slot, drop.after) : null
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging) suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = root.pluginBarApiFor(pluginApiId, moduleName, registered)
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }
  }
}
