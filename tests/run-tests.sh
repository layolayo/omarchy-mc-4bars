#!/usr/bin/env bash
set -euo pipefail

# Comprehensive userspace test runner for MC 4Bars (io.github.layolayo.mc-4bars)
# Verifies:
#   1. Zero symlinks & full `omarchy plugin validate` packaging compliance
#   2. Pure-JavaScript unit tests for BarModel.js
#   3. Isolated userspace CLI, atomic state, and legacy migration tests
#   4. Offscreen Quickshell QML contract test (SecondaryBarApi + BarWidget + BarModel)
#   5. Live Wayland Quickshell full runtime contract test (Bar + SecondaryBar + ManagerPanel)

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
ORIG_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
ORIG_WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
ORIG_HYPRLAND_SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"

echo "=== [1/5] Validating Omarchy plugin package structure ==="
if find "$REPO_DIR" -not -path "$REPO_DIR/.git*" -type l | grep -q .; then
  echo "FAIL: Symlink detected inside plugin repository:" >&2
  find "$REPO_DIR" -not -path "$REPO_DIR/.git*" -type l >&2
  exit 1
fi
"$OMARCHY_PATH/bin/omarchy-plugin-validate" "$REPO_DIR"

echo ""
echo "=== [2/5] Running BarModel.js unit tests ==="
if command -v node >/dev/null 2>&1; then
  node "$REPO_DIR/tests/test_bar_model.js"
else
  echo "SKIP: node not found in PATH"
fi

echo ""
echo "=== [3/5] Running CLI, layout mutation, and visibility migration tests ==="
/usr/bin/python3 "$REPO_DIR/tests/test_cli.py"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mc-4bars-qstest.XXXXXX")"
cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

echo ""
echo "=== [4/5] Running Offscreen Quickshell QML API & Widget contract test ==="
OFF_HOME="$WORK/offscreen_home"
OFF_QS="$WORK/qs_offscreen"
OFF_RESULT="$WORK/offscreen_result.json"
OFF_LOG="$WORK/offscreen.log"
mkdir -p "$OFF_HOME/.config" "$OFF_HOME/.local/state" "$OFF_HOME/.cache" "$WORK/offscreen_runtime" "$OFF_QS"
chmod 700 "$WORK/offscreen_runtime"

ln -s "$OMARCHY_PATH/shell/Commons" "$OFF_QS/Commons"
ln -s "$OMARCHY_PATH/shell/Ui" "$OFF_QS/Ui"
cp -R "$REPO_DIR" "$OFF_QS/mc4bars"

cat > "$OFF_QS/shell.qml" <<EOF
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "./mc4bars" as Mc4Bars
import "./mc4bars/BarModel.js" as BarModel

ShellRoot {
  id: offRoot

  property Item trackedCard: null

  Mc4Bars.SecondaryBarApi {
    id: testBarApi
    pluginId: "test.plugin"
    moduleName: "test.plugin"
    position: "bottom"
    vertical: false
    barSize: 28
    barHidden: false
    _notePopoutCard: function(card) { offRoot.trackedCard = card }
    _popoutCardFor: function(owner) { return offRoot.trackedCard }
    _barSizeFor: function(screenName) { return screenName === "eDP-1" ? 34 : 28 }
  }

  BarWidget {
    id: trayWidget
    bar: testBarApi
    fixedEdge: BarModel.fixedEdgeForRegion("tray")
    inTraySection: true
  }

  Item { id: sampleCard; width: 100; height: 60 }

  Mc4Bars.BarWidget {
    id: pluginButton
  }

  Process {
    id: writer
    property string payload: ""
    command: ["/usr/bin/python3", "-c", "import sys, pathlib; pathlib.Path(sys.argv[1]).write_text(sys.stdin.read(), encoding='utf-8')", "$OFF_RESULT"]
    stdinEnabled: true
    onStarted: {
      write(payload)
      stdinEnabled = false
    }
    onExited: Qt.quit()
  }

  Timer {
    interval: 200
    running: true
    repeat: false
    onTriggered: {
      testBarApi.notePopoutCard(sampleCard)
      var cardMatched = (testBarApi.popoutCardFor(trayWidget) === sampleCard)
      testBarApi.setCenterHoverRevealSuppressed(true)
      testBarApi.setCenterHoverRevealSuppressed(false)
      var checks = {
        inTraySectionProp: trayWidget.inTraySection === true,
        fixedEdgeProp: trayWidget.fixedEdge === "center",
        barSizeLookup: testBarApi.barSizeFor("eDP-1") === 34 && testBarApi.barSizeFor("DP-2") === 28,
        popoutCardContract: cardMatched,
        legacyHoverPropPresent: ("centerSectionRevealHeld" in testBarApi) && ("centerHoverRevealSuppressed" in testBarApi),
        pluginButtonInstantiated: !!pluginButton && pluginButton.tooltipText.indexOf("MC 4Bars") === 0
      }
      var ok = true
      for (var k in checks) {
        if (checks[k] !== true) ok = false
      }
      checks.ok = ok
      writer.payload = JSON.stringify(checks, null, 2)
      writer.running = true
    }
  }
}
EOF

ulimit -c 0 2>/dev/null || true
HOME="$OFF_HOME" \
XDG_CONFIG_HOME="$OFF_HOME/.config" \
XDG_STATE_HOME="$OFF_HOME/.local/state" \
XDG_CACHE_HOME="$OFF_HOME/.cache" \
XDG_RUNTIME_DIR="$WORK/offscreen_runtime" \
WAYLAND_DISPLAY="" \
HYPRLAND_INSTANCE_SIGNATURE="" \
QT_QPA_PLATFORM="offscreen" \
QML2_IMPORT_PATH="$OMARCHY_PATH/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
QML_IMPORT_PATH="$OMARCHY_PATH/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  /usr/bin/quickshell -p "$OFF_QS/shell.qml" --no-color >"$OFF_LOG" 2>&1 || true

if [[ ! -f "$OFF_RESULT" ]]; then
  echo "FAIL: Offscreen Quickshell contract test did not produce $OFF_RESULT" >&2
  cat "$OFF_LOG" >&2
  exit 1
fi

/usr/bin/python3 - "$OFF_RESULT" "$OFF_LOG" <<'PY'
import json, pathlib, sys
res = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
log_text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")
if not res.get("ok"):
    print(f"FAIL: Offscreen QML contract failed: {res}", file=sys.stderr)
    sys.exit(1)
bad = [
    l for l in log_text.splitlines()
    if ("WARN" in l or "ERROR" in l)
    and any(t in l for t in ("mc4bars", "SecondaryBarApi", "BarWidget"))
]
if bad:
    print("FAIL: Offscreen QML warnings/errors:", "\n".join(bad), file=sys.stderr)
    sys.exit(1)
print("PASS: Offscreen Quickshell QML API & BarWidget contract verified (zero warnings)")
PY

echo ""
echo "=== [5/5] Running Wayland Quickshell Full Runtime Contract (Bar + SecondaryBar + ManagerPanel) ==="
if [[ -z "$ORIG_XDG_RUNTIME_DIR" || -z "$ORIG_WAYLAND_DISPLAY" || ! -S "$ORIG_XDG_RUNTIME_DIR/$ORIG_WAYLAND_DISPLAY" ]]; then
  echo "SKIP: No live Wayland socket accessible at \$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY (offscreen contract passed in [4/5])."
  echo ""
  echo "ALL AVAILABLE TESTS PASSED."
  exit 0
fi

WL_HOME="$WORK/wl_home"
WL_CONFIG="$WL_HOME/.config"
WL_STATE="$WL_HOME/.local/state"
WL_CACHE="$WL_HOME/.cache"
mkdir -p "$WL_CONFIG/omarchy/plugins/test.thirdparty.demo" \
         "$WL_STATE/omarchy/toggles" \
         "$WL_CACHE"

# Seed legacy left-bar-off marker to verify live Bar.qml + SecondaryBar.qml migration & cleanup
touch "$WL_STATE/omarchy/toggles/left-bar-off"

cat > "$WL_CONFIG/omarchy/plugins/test.thirdparty.demo/manifest.json" <<'EOF'
{
  "schemaVersion": 1,
  "id": "test.thirdparty.demo",
  "name": "Third-Party Demo",
  "version": "1.0.0",
  "author": "Test",
  "description": "Test third-party widget and service",
  "kinds": ["service", "bar-widget"],
  "barWidget": {
    "displayName": "Demo",
    "defaults": { "greeting": "hello-userspace" }
  },
  "entryPoints": {
    "service": "Service.qml",
    "barWidget": "Widget.qml"
  }
}
EOF

cat > "$WL_CONFIG/omarchy/plugins/test.thirdparty.demo/Service.qml" <<'EOF'
import QtQuick

QtObject {
  property var shell: null
  property var manifest: null
  property string pingValue: "pong-from-service"
}
EOF

cat > "$WL_CONFIG/omarchy/plugins/test.thirdparty.demo/Widget.qml" <<'EOF'
import QtQuick
import qs.Ui

BarWidget {
  id: demoWidget
  implicitWidth: 28
  implicitHeight: 24
  property var shell: null
  readonly property var service: (bar && bar.shell) ? bar.shell.serviceFor("test.thirdparty.demo") : (shell ? shell.serviceFor("test.thirdparty.demo") : null)
  property Item dummyCard: Item { x: 14; y: 22; width: 120; height: 80 }

  function exercisePopoutContract() {
    if (!bar) return false
    bar.requestPopout(demoWidget)
    if (typeof bar.notePopoutCard === "function") {
      bar.notePopoutCard(dummyCard)
    }
    var snap = (typeof bar.popoutCardFor === "function") ? bar.popoutCardFor(demoWidget) : null
    var cardOk = !!snap && snap.width === 120 && snap.height === 80 && snap.x === 14 && snap.y === 22
    if (typeof bar.setCenterHoverRevealSuppressed === "function") {
      bar.setCenterHoverRevealSuppressed(true)
      bar.setCenterHoverRevealSuppressed(false)
    }
    if (typeof bar.notePopoutCard === "function") {
      bar.notePopoutCard(null)
    }
    bar.releasePopout(demoWidget)
    var clearedOk = (typeof bar.popoutCardFor === "function") && bar.popoutCardFor(demoWidget) === null
    return cardOk && clearedOk
  }
}
EOF

cat > "$WL_CONFIG/omarchy/shell.json" <<'EOF'
{
  "enabledPlugins": ["io.github.layolayo.mc-4bars", "test.thirdparty.demo"],
  "bar": {
    "position": "top",
    "background": "opaque",
    "centerAnchor": "omarchy.clock",
    "layout": {
      "left": ["omarchy.workspaces"],
      "center": ["omarchy.clock"],
      "right": ["io.github.layolayo.mc-4bars"],
      "tray": []
    }
  },
  "bottomBar": {
    "position": "bottom",
    "background": "glassy",
    "layout": {
      "left": ["firstparty.sample"],
      "center": ["test.thirdparty.demo"],
      "right": ["firstparty.trayhost"],
      "tray": ["firstparty.traychild"]
    }
  },
  "leftBar": {
    "position": "left",
    "background": "none",
    "layout": {
      "left": ["firstparty.sample"],
      "center": [],
      "right": [],
      "tray": []
    }
  },
  "rightBar": {
    "position": "right",
    "background": "opaque",
    "layout": {
      "left": [],
      "center": [],
      "right": [],
      "tray": []
    }
  }
}
EOF

QS_DIR="$WORK/qs_wayland"
mkdir -p "$QS_DIR"
ln -s "$OMARCHY_PATH/shell/Commons" "$QS_DIR/Commons"
ln -s "$OMARCHY_PATH/shell/Ui" "$QS_DIR/Ui"
cp -R "$REPO_DIR" "$QS_DIR/mc4bars"

RESULT_FILE="$WORK/wayland_result.json"
QS_LOG="$WORK/wayland_quickshell.log"

cat > "$QS_DIR/shell.qml" <<EOF
import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "./mc4bars" as Mc4Bars

ShellRoot {
  id: harness

  Component {
    id: sampleFirstPartyComp
    BarWidget {
      implicitWidth: 24
      implicitHeight: 24
    }
  }

  Component {
    id: trayHostComp
    BarWidget {
      implicitWidth: 24
      implicitHeight: 24
      property Item sectionHost: Item {
        width: 40
        height: 24
        visible: true
        property Item dropSpace: Item { width: 10; height: 24; visible: true }
      }
    }
  }

  QtObject {
    id: fakeBarWidgetRegistry
    property int revision: 1
    property var widgets: ({
      "firstparty.sample": { component: sampleFirstPartyComp },
      "firstparty.trayhost": { component: trayHostComp },
      "firstparty.traychild": { component: sampleFirstPartyComp }
    })
    function metadataFor(id) {
      if (id.indexOf("firstparty.") === 0) return { id: id, firstParty: true }
      return null
    }
  }

  QtObject {
    id: fakeShell
    function summon(id, payload) { return true }
    function toggle(id, payload) { return true }
    function dismiss(id) { return true }
    function isOpen(id) { return false }
    function serviceFor(id) { return null }
    function settingsFor(id) { return ({}) }
    function saveSettingsFor(id, obj) { return true }
    function summonBarWidget(id) { return false }
    function hideBarWidget(id) { return false }
    function isBarWidgetOpen(id) { return false }
  }

  Mc4Bars.Bar {
    id: coordinator
    omarchyPath: "$OMARCHY_PATH"
    barWidgetRegistry: fakeBarWidgetRegistry
    shell: fakeShell
    manifest: ({ id: "io.github.layolayo.mc-4bars", version: "1.1.0" })
  }

  Mc4Bars.BarWidget {
    id: barIconWidget
    shell: fakeShell
    service: coordinator
  }

  Mc4Bars.ManagerPanel {
    id: managerPanel
    omarchyPath: "$OMARCHY_PATH"
    service: coordinator
    shell: fakeShell
    manifest: ({ id: "io.github.layolayo.mc-4bars", version: "1.1.0" })
  }

  Process {
    id: resultWriter
    property string payload: ""
    command: ["/usr/bin/python3", "-c", "import sys, pathlib; pathlib.Path(sys.argv[1]).write_text(sys.stdin.read(), encoding='utf-8')", "$RESULT_FILE"]
    stdinEnabled: true
    onStarted: {
      write(payload)
      stdinEnabled = false
    }
    onExited: Qt.quit()
  }

  Timer {
    interval: 900
    running: true
    repeat: false
    onTriggered: {
      var checks = {}
      try {
        var bottomBar = coordinator.secondaryBars[0]
        var leftBar = coordinator.secondaryBars[1]

        checks.leftMigratedHidden = (leftBar.barHidden === true)

        var testApi = bottomBar.pluginBarApiFor("test.thirdparty.demo", "test.thirdparty.demo", false, false)
        checks.apiExists = !!testApi
        checks.apiEdgeBottom = (testApi && testApi.position === "bottom")
        checks.apiHasLegacyProps = (testApi && ("centerSectionRevealHeld" in testApi) && ("centerHoverRevealSuppressed" in testApi))
        checks.apiHasCurrentMethods = (testApi && typeof testApi.notePopoutCard === "function" && typeof testApi.popoutCardFor === "function")

        var screenCount = Quickshell.screens ? Quickshell.screens.length : 0
        checks.screenCount = screenCount

        if (screenCount > 0) {
          var sampleItems = bottomBar.moduleWidgets("firstparty.sample")
          var demoItems = bottomBar.moduleWidgets("test.thirdparty.demo")
          var trayChildItems = bottomBar.moduleWidgets("firstparty.traychild")
          checks.sampleLoaded = sampleItems.length > 0
          checks.demoLoaded = demoItems.length > 0
          checks.trayChildLoaded = trayChildItems.length > 0

          if (sampleItems.length > 0) {
            checks.sampleFixedEdge = (sampleItems[0].fixedEdge === "start")
            checks.sampleNotInTray = (sampleItems[0].inTraySection === false)
          }
          if (trayChildItems.length > 0) {
            checks.trayChildInTray = (trayChildItems[0].inTraySection === true)
          }
          if (demoItems.length > 0) {
            var dw = demoItems[0]
            checks.demoSettingsMerged = (dw.settings && dw.settings.greeting === "hello-userspace")
            checks.demoServiceWired = (dw.service && dw.service.pingValue === "pong-from-service")
            checks.demoPopoutContract = dw.exercisePopoutContract()
          }
        }

        // Persist hide state to isolated visibility.json
        var hideRes = coordinator.hideEdgeVisibility("bottom")
        checks.hideBottomReturnedHidden = (hideRes === "hidden" && bottomBar.barHidden === true)

        managerPanel.open("{}")
        checks.managerOpened = (managerPanel.visible === true)
        managerPanel.close()
        checks.managerClosed = (managerPanel.visible === false)

        var allOk = true
        for (var k in checks) {
          if (k === "screenCount") continue
          if (checks[k] !== true) allOk = false
        }
        checks.ok = allOk
      } catch (err) {
        checks.ok = false
        checks.exception = String(err)
      }

      finishTimer.payload = JSON.stringify(checks, null, 2)
      finishTimer.start()
    }
  }

  Timer {
    id: finishTimer
    property string payload: "{}"
    interval: 300
    repeat: false
    onTriggered: {
      resultWriter.payload = finishTimer.payload
      resultWriter.running = true
    }
  }

  Timer {
    interval: 6000
    running: true
    repeat: false
    onTriggered: {
      resultWriter.payload = JSON.stringify({ ok: false, error: "timeout" })
      resultWriter.running = true
    }
  }
}
EOF

HOME="$WL_HOME" \
XDG_CONFIG_HOME="$WL_CONFIG" \
XDG_STATE_HOME="$WL_STATE" \
XDG_CACHE_HOME="$WL_CACHE" \
XDG_RUNTIME_DIR="$ORIG_XDG_RUNTIME_DIR" \
WAYLAND_DISPLAY="$ORIG_WAYLAND_DISPLAY" \
HYPRLAND_INSTANCE_SIGNATURE="$ORIG_HYPRLAND_SIG" \
QML2_IMPORT_PATH="$OMARCHY_PATH/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
QML_IMPORT_PATH="$OMARCHY_PATH/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  /usr/bin/quickshell -p "$QS_DIR/shell.qml" --no-color >"$QS_LOG" 2>&1 || true

if [[ ! -f "$RESULT_FILE" ]]; then
  echo "FAIL: Wayland Quickshell runtime test did not produce $RESULT_FILE" >&2
  cat "$QS_LOG" >&2
  exit 1
fi

/usr/bin/python3 - "$RESULT_FILE" "$WL_STATE/io.github.layolayo.mc-4bars/visibility.json" "$WL_STATE/omarchy/toggles/left-bar-off" "$QS_LOG" <<'PY'
import json, pathlib, sys

res = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
vis_path = pathlib.Path(sys.argv[2])
legacy_left = pathlib.Path(sys.argv[3])
log_text = pathlib.Path(sys.argv[4]).read_text(encoding="utf-8", errors="replace")

if not res.get("ok"):
    print(f"FAIL: Wayland QML runtime contract failed: {json.dumps(res, indent=2)}", file=sys.stderr)
    print("--- Quickshell Log ---", file=sys.stderr)
    print(log_text, file=sys.stderr)
    sys.exit(1)

if not vis_path.is_file():
    print(f"FAIL: Expected isolated visibility state file {vis_path} to exist", file=sys.stderr)
    sys.exit(1)

vis = json.loads(vis_path.read_text(encoding="utf-8"))
if vis.get("bottomBar") is not True or vis.get("leftBar") is not True:
    print(f"FAIL: Unexpected persisted visibility state: {vis}", file=sys.stderr)
    sys.exit(1)

if legacy_left.exists():
    print("FAIL: Legacy left-bar-off marker was not cleaned up!", file=sys.stderr)
    sys.exit(1)

bad_lines = [
    line for line in log_text.splitlines()
    if ("WARN" in line or "ERROR" in line)
    and any(tok in line for tok in ("mc4bars", "SecondaryBar", "SecondaryBarApi", "ManagerPanel", "BarWidget.qml", "Bar.qml"))
]

if bad_lines:
    print("FAIL: QML warnings/errors detected in mc-4bars:", file=sys.stderr)
    for b in bad_lines:
        print("  " + b, file=sys.stderr)
    sys.exit(1)

print(f"PASS: Wayland Quickshell full runtime contract verified across {res.get('screenCount', 0)} screen(s) with zero QML warnings!")
PY

echo ""
echo "ALL 5 TEST SUITES PASSED."
