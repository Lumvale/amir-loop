"""Cross-platform contract for the activation adapter (invoked by Bats)."""

from __future__ import annotations

import importlib.util
import os
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = (Path(__file__).resolve().parents[1] / "plugins" / "amir-loop-lumvaleos" /
          "scripts" / "lumvaleos-reconcile.py")
SPEC = importlib.util.spec_from_file_location("lumvaleos_reconcile", SCRIPT)
assert SPEC and SPEC.loader
RECONCILE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RECONCILE)


class ReconcileTests(unittest.TestCase):
    def test_activation_claims_due_work_and_injects_it_into_the_current_session(self):
        seen = {}

        def launch(command, **kwargs):
            seen.update(command=command, kwargs=kwargs)
            return type("Result", (), {"returncode": 0, "stdout": json.dumps({
                "queued": [{"name": "mailbox", "status": "queued"}],
                "claim": {"claim_token": "abc123", "automation": "mailbox",
                          "prompt": "Verify the DSP label.", "expires_at": "later"},
            })})()

        with patch.object(RECONCILE, "lumvaleos_root", return_value=Path("engine")), \
             patch.object(RECONCILE, "interpreter", return_value=Path(sys.executable)), \
             patch.object(RECONCILE.subprocess, "run", side_effect=launch), \
             patch("sys.stdin", io.StringIO('{"hook_event_name":"SessionStart","session_id":"s1"}')), \
             patch("sys.stdout", new_callable=io.StringIO) as output:
            self.assertEqual(RECONCILE.main(), 0)
        self.assertEqual(seen["command"][2:], ["activate", "--ide", "codex",
                                                "--session", "s1", "--json"])
        payload = json.loads(output.getvalue())
        context = payload["hookSpecificOutput"]["additionalContext"]
        self.assertIn("Verify the DSP label.", context)
        self.assertIn("complete --claim abc123 --status success", context)
        self.assertNotIn("queued", context)

    def test_codex_mcp_config_locates_engine_outside_current_repo(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            root = base / "lumvale-os"
            root.mkdir()
            (root / "lumvaleos.py").touch()
            config = base / "config.toml"
            config.write_text(
                f'[mcp_servers.lumvaleos]\ncommand = "{root.as_posix()}/lumvaleos.py"\n',
                encoding="utf-8",
            )
            with patch.dict(os.environ, {"AMIR_LOOP_CODEX_CONFIG": str(config)}, clear=False):
                os.environ.pop("LUMVALEOS_ROOT", None)
                self.assertEqual(RECONCILE.lumvaleos_root(), root)

    def test_missing_explicit_engine_is_a_quiet_noop(self):
        with patch.dict(os.environ, {"LUMVALEOS_ROOT": "definitely-missing"}, clear=False):
            self.assertEqual(RECONCILE.main(), 0)


if __name__ == "__main__":
    unittest.main()
