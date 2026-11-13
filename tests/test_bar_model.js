#!/usr/bin/env node
"use strict";

// Pure-JavaScript unit tests for BarModel.js layout normalisation, security
// guards, tray pinning, settings deltas, and cutout geometry.

const assert = require("assert");
const BarModel = require("../BarModel.js");

function runTests() {
  // 1. Clamp & basic helpers
  assert.strictEqual(BarModel.clamp(5, 0, 10), 5);
  assert.strictEqual(BarModel.clamp(-3, 0, 10), 0);
  assert.strictEqual(BarModel.clamp(99, 0, 10), 10);
  assert.strictEqual(BarModel.clamp(NaN, 2, 8), 2);

  assert.strictEqual(BarModel.isPlainObject({ a: 1 }), true);
  assert.strictEqual(BarModel.isPlainObject([]), false);
  assert.strictEqual(BarModel.isPlainObject(null), false);

  assert.strictEqual(BarModel.canonicalWidgetId("  omarchy.clock  "), "omarchy.clock");
  assert.strictEqual(BarModel.fileUrl("/tmp/my plugin/Widget.qml"), "file://%2Ftmp/my%20plugin/Widget.qml".replace("%2F", "/"));
  assert.strictEqual(BarModel.fileUrl("/tmp/a b/c.qml"), "file:///tmp/a%20b/c.qml");

  // 2. Fixed edge mapping
  assert.strictEqual(BarModel.fixedEdgeForRegion("left"), "start");
  assert.strictEqual(BarModel.fixedEdgeForRegion("right"), "end");
  assert.strictEqual(BarModel.fixedEdgeForRegion("center"), "center");
  assert.strictEqual(BarModel.fixedEdgeForRegion("tray"), "center");

  // 3. Plugin ID and entry-point security sanitisation
  assert.strictEqual(BarModel.isSafePluginId("io.github.layolayo.mc-4bars"), true);
  assert.strictEqual(BarModel.isSafePluginId("omarchy.clock"), true);
  assert.strictEqual(BarModel.isSafePluginId("../escape"), false);
  assert.strictEqual(BarModel.isSafePluginId("bad/slash"), false);
  assert.strictEqual(BarModel.isSafePluginId(".hidden"), false);

  assert.strictEqual(BarModel.isSafeEntryPoint("BarWidget.qml"), true);
  assert.strictEqual(BarModel.isSafeEntryPoint("ui/Widget.qml"), true);
  assert.strictEqual(BarModel.isSafeEntryPoint("/etc/passwd.qml"), false);
  assert.strictEqual(BarModel.isSafeEntryPoint("../Widget.qml"), false);
  assert.strictEqual(BarModel.isSafeEntryPoint("Widget.js"), false);

  // 4. Layout normalisation (including centerBegin / center / centerEnd)
  const norm = BarModel.normalizeLayout({
    left: ["omarchy.workspaces", "", null],
    centerBegin: ["omarchy.update"],
    center: [{ id: "omarchy.clock", settings: { format: "24h" } }],
    centerEnd: ["omarchy.screenrecording"],
    right: ["omarchy.tray", "omarchy.battery"],
    tray: ["omarchy.bluetooth"]
  });
  assert.deepStrictEqual(norm.left, [{ id: "omarchy.workspaces" }]);
  assert.deepStrictEqual(norm.centerBegin, [{ id: "omarchy.update" }]);
  assert.deepStrictEqual(norm.center, [{ id: "omarchy.clock", settings: { format: "24h" } }]);
  assert.deepStrictEqual(norm.centerEnd, [{ id: "omarchy.screenrecording" }]);
  assert.deepStrictEqual(norm.tray, [{ id: "omarchy.bluetooth" }]);

  // 5. Tray inner-edge pinning
  const pinnedRight = BarModel.pinTrayToInner(
    [{ id: "omarchy.battery" }, { id: "omarchy.tray" }, { id: "omarchy.audio" }],
    "right"
  );
  assert.strictEqual(pinnedRight[0].id, "omarchy.tray");

  const pinnedLeft = BarModel.pinTrayToInner(
    [{ id: "omarchy.tray" }, { id: "omarchy.workspaces" }],
    "left"
  );
  assert.strictEqual(pinnedLeft[pinnedLeft.length - 1].id, "omarchy.tray");

  // 6. Inline settings delta detection
  const prevLayout = {
    left: [{ id: "a", settings: { n: 1 } }],
    center: [{ id: "b" }],
    right: [],
    tray: []
  };
  const nextSameOrderChangedSettings = {
    left: [{ id: "a", settings: { n: 2 } }],
    center: [{ id: "b" }],
    right: [],
    tray: []
  };
  const delta = BarModel.inlineSettingsDelta(prevLayout, nextSameOrderChangedSettings);
  assert.ok(Array.isArray(delta) && delta.length === 1);
  assert.strictEqual(delta[0].region, "left");
  assert.strictEqual(delta[0].index, 0);
  assert.deepStrictEqual(delta[0].entry.settings, { n: 2 });

  const nextReordered = {
    left: [],
    center: [{ id: "b" }, { id: "a", settings: { n: 2 } }],
    right: [],
    tray: []
  };
  assert.strictEqual(BarModel.inlineSettingsDelta(prevLayout, nextReordered), null);

  // 7. Position normalisation & bar sizes
  assert.strictEqual(BarModel.normalizePosition(" left "), "left");
  assert.strictEqual(BarModel.normalizePosition("LEFT"), "bottom");
  assert.strictEqual(BarModel.normalizePosition("invalid"), "bottom");
  assert.strictEqual(BarModel.barSizeFor({ "eDP-1": 34 }, "eDP-1", 28), 34);
  assert.strictEqual(BarModel.barSizeFor({ "eDP-1": 34 }, "DP-2", 28), 28);

  console.log("PASS: BarModel.js unit tests (all assertions succeeded)");
}

runTests();
