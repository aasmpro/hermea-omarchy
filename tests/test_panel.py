"""Run with python3 -B -m unittest discover -s tests -v. No GUI is launched."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location("hermes_panel", Path(__file__).resolve().parents[1] / "hermes-panel.py")
panel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(panel)

STATUS = """
◆ Environment
  Model:        example-model
◆ Gateway Service
  Status:       ✓ running
  Manager:      systemd (user)
◆ Scheduled Jobs
  Jobs:         2 active, 3 total
◆ Sessions
  Active:       4 session(s)
"""


class StatusTests(unittest.TestCase):
    def test_allowlisted_status_fields_and_ansi(self):
        cards, errors = panel.parse_status("\x1b[32m" + STATUS + "\x1b[0m")
        self.assertEqual(errors, [])
        self.assertEqual(list(cards), ["gateway", "sessions", "jobs"])
        self.assertEqual(cards["gateway"]["value"], "Running")
        self.assertEqual(cards["sessions"]["value"], "4")
        self.assertEqual(cards["sessions"]["detail"], "Selected profile only")
        self.assertEqual(cards["jobs"]["value"], "2 enabled / 3 total")
        self.assertNotIn("example-model", json.dumps(cards))

    def test_version_card_parsing(self):
        self.assertEqual(panel.parse_version("Hermes Agent v0.9.3\n"), "0.9.3")

    def test_skill_counts_installed_and_used(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "skills" / "one").mkdir(parents=True)
            (root / "skills" / "two").mkdir()
            (root / "skills" / "one" / "SKILL.md").write_text("# one")
            (root / "skills" / "two" / "SKILL.md").write_text("# two")
            (root / "skills" / ".usage.json").write_text(json.dumps({
                "one": {"last_used_at": "2026-09-19T00:00:00Z"},
                "two": {"last_used_at": None},
                "missing": {"last_used_at": "2026-09-19T00:00:00Z"},
            }))
            self.assertEqual(panel.skill_counts(root), (2, 1))

    def test_unknown_never_becomes_zero(self):
        cards, errors = panel.parse_status("◆ Sessions\n  Active:       (error reading sessions file)\n")
        self.assertTrue(errors)
        self.assertTrue(all(card["state"] == "unknown" for card in cards.values()))


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        (self.home / ".hermes").mkdir()

    def test_discovery_and_profile_paths(self):
        for name in ("writer", "codex", ".hidden", "Bad Name"):
            (self.home / ".hermes/profiles" / name).mkdir(parents=True)
        profiles, errors = panel.discover_profiles(self.home)
        self.assertEqual([profile["name"] for profile in profiles], ["default", "codex", "writer"])
        self.assertEqual(errors, [])
        self.assertEqual(panel.profile_dir(self.home, "writer"), self.home / ".hermes/profiles/writer")
        with self.assertRaises(panel.ProbeError):
            panel.profile_dir(self.home, "../../bad")

    def test_profile_icon_fallback_and_named_profiles(self):
        (self.home / ".hermes/profiles/codex").mkdir(parents=True)
        self.assertEqual(panel.profile_icon(self.home, "default"), panel.DEFAULT_PROFILE_ICON)
        self.assertEqual(panel.profile_icon(self.home, "codex"), panel.DEFAULT_PROFILE_ICON)
        panel.write_profile_icon(self.home, "default", "󰘦")
        panel.write_profile_icon(self.home, "codex", "󰚩")
        self.assertEqual(panel.profile_icon(self.home, "default"), "󰘦")
        self.assertEqual(panel.profile_icon(self.home, "codex"), "󰚩")

    def test_profile_icon_rejects_unknown_glyph(self):
        with self.assertRaises(panel.ProbeError):
            panel.write_profile_icon(self.home, "default", "not-an-icon")

    def test_profile_icon_preserves_unrelated_configuration(self):
        config = self.home / ".hermes/profile.yaml"
        config.write_text("description: kept\ndescription_auto: false\n")
        panel.write_profile_icon(self.home, "default", "󰘦")
        payload = panel.yaml.safe_load(config.read_text())
        self.assertEqual(payload["description"], "kept")
        self.assertFalse(payload["description_auto"])
        self.assertEqual(payload["ui"]["profile_icon"], "󰘦")

    @patch.object(panel, "notify")
    @patch.object(panel.subprocess, "Popen")
    @patch.object(panel.shutil, "which", return_value="/bin/mock")
    def test_chat_does_not_change_default(self, which, popen, notify):
        (self.home / ".hermes/profiles/codex").mkdir(parents=True)
        sticky = self.home / ".hermes/active_profile"
        sticky.write_text("default\n")
        popen.return_value.wait.return_value = 0
        with patch.dict(os.environ, {"TERM": "xterm-256color"}):
            self.assertEqual(panel.launch_chat("codex", "openai-codex", "gpt-5.5", self.home), 0)
        self.assertEqual(popen.call_args.args[0], ["xdg-terminal-exec", f"--dir={self.home}", "--", "hermes", "--profile", "codex", "--provider", "openai-codex", "--model", "gpt-5.5", "--cli"])
        self.assertEqual(popen.call_args.kwargs["env"]["HERMES_HOME"], str(self.home / ".hermes/profiles/codex"))
        self.assertEqual(sticky.read_text(), "default\n")
        notify.assert_not_called()

    @patch.object(panel, "probe_dashboard")
    def test_snapshot_returns_empty_state_without_profile(self, dashboard):
        dashboard.return_value = (panel.card("dashboard", "http://127.0.0.1:9119", "inactive"), [])
        result = panel.snapshot("missing", self.home)
        self.assertEqual(result["schemaVersion"], 4)
        self.assertFalse(result["available"])
        self.assertEqual([item["name"] for item in result["profiles"]], ["default"])
        self.assertEqual(len(result["cards"]), 6)
        self.assertEqual(result["models"]["options"], [])
        self.assertTrue(result["errors"])


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        (self.home / ".hermes").mkdir()

    @patch.object(panel, "scoped_hermes_home")
    def test_includes_all_available_models_and_current_model(self, scope):
        scope.return_value.__enter__.return_value = None
        scope.return_value.__exit__.return_value = None
        payload = {"provider": "nous", "model": "nous-free", "providers": [
            {"slug": "openai-codex", "models": ["gpt-5.5"]},
            {"slug": "nous", "models": ["nous-free", "nous-paid"], "pricing": {"nous-free": {"free": True}, "nous-paid": {"free": False}}},
            {"slug": "openrouter", "models": ["not-allowed"]},
        ]}
        inventory = MagicMock()
        inventory.build_models_payload.return_value = payload
        inventory.load_picker_context.return_value = object()
        import sys, types
        package = types.ModuleType("hermes_cli")
        with patch.dict(sys.modules, {"hermes_cli": package, "hermes_cli.inventory": inventory}):
            result = panel.live_models("default", self.home)
        self.assertEqual([item["model"] for item in result["options"]], ["nous-free", "nous-paid", "gpt-5.5", "not-allowed"])
        self.assertTrue(result["currentAllowed"])

    @patch.object(panel, "scoped_hermes_home")
    def test_model_pricing_is_safe_when_provider_returns_numbers(self, scope):
        scope.return_value.__enter__.return_value = None
        scope.return_value.__exit__.return_value = None
        payload = {"provider": "nous", "model": "nous-paid", "providers": [
            {"slug": "nous", "models": ["nous-paid"], "pricing": {"nous-paid": {"input": 1, "output": 2}}}
        ]}
        inventory = MagicMock()
        inventory.build_models_payload.return_value = payload
        inventory.load_picker_context.return_value = object()
        import sys, types
        package = types.ModuleType("hermes_cli")
        with patch.dict(sys.modules, {"hermes_cli": package, "hermes_cli.inventory": inventory}):
            result = panel.live_models("default", self.home)
        self.assertIn("1 in · 2 out", result["options"][0]["description"])

    @patch.object(panel, "run_hermes")
    @patch.object(panel, "run_internal_models")
    def test_set_model_only_writes_selected_profile(self, catalog, run):
        catalog.return_value = {"options": [{"provider": "openai-codex", "model": "gpt-5.5"}]}
        run.side_effect = [(0, "nous\n"), (0, ""), (0, ""), (0, ""), (0, "")]
        self.assertEqual(panel.set_model("default", "openai-codex", "gpt-5.5", self.home), 0)
        calls = [call.args[0] for call in run.call_args_list]
        self.assertIn(["--profile", "default", "config", "unset", "model.base_url"], calls)
        self.assertIn(["--profile", "default", "config", "set", "model.default", "gpt-5.5"], calls)

    @patch.object(panel, "notify")
    @patch.object(panel, "run_internal_models")
    def test_rejects_model_not_in_live_catalog(self, catalog, notify):
        catalog.return_value = {"options": []}
        self.assertEqual(panel.set_model("default", "openai-codex", "invented", self.home), 1)
        self.assertIn("not available", notify.call_args.args[0])


class DashboardTests(unittest.TestCase):
    @patch.object(panel.socket, "create_connection")
    def test_dashboard_states(self, connect):
        connect.return_value.__enter__.return_value = MagicMock()
        self.assertEqual(panel.probe_dashboard()[0]["state"], "ok")
        connect.side_effect = ConnectionRefusedError()
        self.assertEqual(panel.probe_dashboard()[0]["state"], "inactive")
        connect.side_effect = socket.timeout()
        self.assertEqual(panel.probe_dashboard()[0]["state"], "unknown")

    @patch.object(panel.socket, "create_connection")
    def test_dashboard_uses_configured_endpoint(self, connect):
        connect.return_value.__enter__.return_value = MagicMock()
        panel.probe_dashboard("example.test", 12345)
        connect.assert_called_once_with(("example.test", 12345), timeout=1)
        self.assertEqual(panel.dashboard_url("example.test", 12345), "http://example.test:12345")

    def test_dashboard_rejects_invalid_endpoint(self):
        with self.assertRaises(panel.ProbeError):
            panel.dashboard_url("bad host", 9119)
        with self.assertRaises(panel.ProbeError):
            panel.dashboard_url("127.0.0.1", 70000)


if __name__ == "__main__":
    unittest.main()
