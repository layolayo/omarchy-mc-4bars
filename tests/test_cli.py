#!/usr/bin/env python3
"""Userspace CLI, layout mutation, and visibility migration tests for MC 4Bars."""

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CLI_BIN = REPO_ROOT / "bin" / "omarchy-mc-4bars"


class Mc4BarsCliTests(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory(prefix="mc4bars-cli-test-")
        self.base = Path(self.tmpdir.name)
        self.home = self.base / "home"
        self.config_home = self.home / ".config"
        self.state_home = self.home / ".local" / "state"
        self.omarchy_cfg = self.config_home / "omarchy"
        self.omarchy_cfg.mkdir(parents=True, exist_ok=True)
        self.state_home.mkdir(parents=True, exist_ok=True)
        plugin_dir = self.omarchy_cfg / "plugins" / "io.github.layolayo.mc-4bars"
        plugin_dir.mkdir(parents=True, exist_ok=True)
        (plugin_dir / "manifest.json").write_text(
            (REPO_ROOT / "manifest.json").read_text(encoding="utf-8"),
            encoding="utf-8",
        )

        # Stub omarchy-shell so CLI exercises deterministic offline paths without touching the live session
        self.bin_dir = self.base / "bin"
        self.bin_dir.mkdir(parents=True, exist_ok=True)
        omarchy_dir = self.base / "omarchy"
        (omarchy_dir / "bin").mkdir(parents=True, exist_ok=True)
        stub_shell = omarchy_dir / "bin" / "omarchy-shell"
        stub_shell.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        stub_shell.chmod(0o755)
        stub_toggle = omarchy_dir / "bin" / "omarchy-toggle-bar"
        stub_toggle.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        stub_toggle.chmod(0o755)

        self.env = os.environ.copy()
        self.env["HOME"] = str(self.home)
        self.env["XDG_CONFIG_HOME"] = str(self.config_home)
        self.env["XDG_STATE_HOME"] = str(self.state_home)
        self.env["OMARCHY_PATH"] = str(omarchy_dir)

        self.shell_json = self.omarchy_cfg / "shell.json"
        self.visibility_json = self.state_home / "io.github.layolayo.mc-4bars" / "visibility.json"

        initial_cfg = {
            "bar": {
                "position": "top",
                "background": "opaque",
                "centerAnchor": "omarchy.clock",
                "layout": {
                    "left": ["omarchy.workspaces"],
                    "centerBegin": ["omarchy.system-update"],
                    "center": ["omarchy.clock"],
                    "centerEnd": ["omarchy.indicators"],
                    "right": ["omarchy.tray", "io.github.layolayo.mc-4bars"],
                    "tray": ["omarchy.bluetooth"],
                },
            },
            "bottomBar": {
                "position": "bottom",
                "background": "none",
                "layout": {"left": [], "center": [], "right": [], "tray": []},
            },
            "leftBar": {
                "position": "left",
                "background": "glassy",
                "layout": {"left": [], "center": [], "right": [], "tray": []},
            },
            "rightBar": {
                "position": "right",
                "background": "none",
                "layout": {"left": [], "center": [], "right": [], "tray": []},
            },
        }
        self.shell_json.write_text(json.dumps(initial_cfg, indent=2) + "\n", encoding="utf-8")

    def tearDown(self):
        self.tmpdir.cleanup()

    def run_cli(self, *args, stdin_data=None):
        return subprocess.run(
            ["/usr/bin/python3", str(CLI_BIN), *args],
            input=stdin_data,
            text=True,
            capture_output=True,
            env=self.env,
            timeout=5,
        )

    def test_sync_visibility_creates_isolated_0600_state(self):
        res = self.run_cli("sync-visibility")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertEqual(
            data,
            {
                "bottomBar": False,
                "leftBar": False,
                "rightBar": False,
                "hadLegacyAutoBarOff": False,
            },
        )
        self.assertTrue(self.visibility_json.is_file())
        mode = stat.S_IMODE(self.visibility_json.stat().st_mode)
        self.assertEqual(mode, 0o600)

    def test_sync_visibility_migrates_and_cleans_legacy_toggles(self):
        toggles_dir = self.state_home / "omarchy" / "toggles"
        toggles_dir.mkdir(parents=True, exist_ok=True)
        legacy_bottom = toggles_dir / "bottom-bar-off"
        legacy_right = toggles_dir / "right-bar-off"
        legacy_auto = toggles_dir / "mc-4bars-auto-bar-off"
        primary_bar_off = toggles_dir / "bar-off"
        for p in (legacy_bottom, legacy_right, legacy_auto, primary_bar_off):
            p.write_text("", encoding="utf-8")

        res = self.run_cli("sync-visibility")
        self.assertEqual(res.returncode, 0, res.stderr)
        data = json.loads(res.stdout)
        self.assertEqual(
            data,
            {
                "bottomBar": True,
                "leftBar": False,
                "rightBar": True,
                "hadLegacyAutoBarOff": True,
            },
        )

        # Legacy secondary markers must be removed; primary Omarchy bar-off must remain untouched!
        self.assertFalse(legacy_bottom.exists())
        self.assertFalse(legacy_right.exists())
        self.assertFalse(legacy_auto.exists())
        self.assertTrue(primary_bar_off.exists())

    def test_write_visibility_stdin_roundtrip_and_validation(self):
        payload = json.dumps({"bottomBar": False, "leftBar": True, "rightBar": False})
        res = self.run_cli("write-visibility-stdin", stdin_data=payload)
        self.assertEqual(res.returncode, 0, res.stderr)

        saved = json.loads(self.visibility_json.read_text(encoding="utf-8"))
        self.assertEqual(
            saved,
            {"version": 1, "bottomBar": False, "leftBar": True, "rightBar": False},
        )

        bad = self.run_cli("write-visibility-stdin", stdin_data="not-json")
        self.assertNotEqual(bad.returncode, 0)

    def test_move_widget_across_bars_and_preserve_primary_clock_split(self):
        # Move bluetooth from primary tray to bottomBar middle
        res = self.run_cli("bottom", "omarchy.bluetooth", "M")
        self.assertEqual(res.returncode, 0, res.stderr)

        cfg = json.loads(self.shell_json.read_text(encoding="utf-8"))
        self.assertEqual(cfg["bottomBar"]["layout"]["center"], ["omarchy.bluetooth"])
        self.assertEqual(cfg["bar"]["layout"]["tray"], [])
        # Primary bar centerBegin / center / centerEnd must remain intact around omarchy.clock
        self.assertEqual(cfg["bar"]["layout"]["centerBegin"], ["omarchy.system-update"])
        self.assertEqual(cfg["bar"]["layout"]["center"], ["omarchy.clock"])
        self.assertEqual(cfg["bar"]["layout"]["centerEnd"], ["omarchy.indicators"])

        # Move a new widget into primary bar middle before omarchy.clock -> lands in centerBegin
        res2 = self.run_cli("move", "omarchy.bluetooth", "top", "M", "--before", "omarchy.clock")
        self.assertEqual(res2.returncode, 0, res2.stderr)
        cfg2 = json.loads(self.shell_json.read_text(encoding="utf-8"))
        self.assertIn("omarchy.bluetooth", cfg2["bar"]["layout"]["centerBegin"])
        self.assertEqual(cfg2["bar"]["layout"]["center"], ["omarchy.clock"])

    def test_swap_background_and_remove(self):
        res_bg = self.run_cli("background", "opaque", "bottom")
        self.assertEqual(res_bg.returncode, 0, res_bg.stderr)
        cfg = json.loads(self.shell_json.read_text(encoding="utf-8"))
        self.assertEqual(cfg["bottomBar"]["background"], "opaque")

        res_swap = self.run_cli("swap", "top", "bottom")
        self.assertEqual(res_swap.returncode, 0, res_swap.stderr)
        cfg_swapped = json.loads(self.shell_json.read_text(encoding="utf-8"))
        self.assertEqual(cfg_swapped["bar"]["position"], "bottom")
        self.assertEqual(cfg_swapped["bottomBar"]["position"], "top")

        res_rm = self.run_cli("remove", "io.github.layolayo.mc-4bars", "-y")
        self.assertEqual(res_rm.returncode, 0, res_rm.stderr)
        cfg_rm = json.loads(self.shell_json.read_text(encoding="utf-8"))
        self.assertNotIn("io.github.layolayo.mc-4bars", cfg_rm["bar"]["layout"]["right"])

    def test_write_stdin_atomic_0600_and_list_output(self):
        cfg = json.loads(self.shell_json.read_text(encoding="utf-8"))
        cfg["leftBar"]["layout"]["center"] = ["omarchy.clock"]
        res = self.run_cli("write-stdin", stdin_data=json.dumps(cfg))
        self.assertEqual(res.returncode, 0, res.stderr)
        mode = stat.S_IMODE(self.shell_json.stat().st_mode)
        self.assertEqual(mode, 0o600)

        res_list = self.run_cli("list")
        self.assertEqual(res_list.returncode, 0, res_list.stderr)
        self.assertIn("Left Bar", res_list.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
