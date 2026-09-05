import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).parents[1] / "plugins" / "amir-loop-lumvaleos" / "scripts" / "lumvaleos-preflight.py"
SPEC = importlib.util.spec_from_file_location("lumvaleos_preflight", SCRIPT)
PREFLIGHT = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(PREFLIGHT)


class CodexConfigTests(unittest.TestCase):
    def test_python39_fallback_reads_command_arguments_without_tomllib(self):
        text = '''
[mcp_servers.unrelated]
command = "ignore-me"

[mcp_servers.lumvaleos]
command = "/opt/lumvale-os/venv/bin/python"
args = ["/opt/lumvale-os/lumvaleos.py", "mcp-server"]

[features]
enabled = true
'''
        with patch.dict(sys.modules, {"tomllib": None}):
            self.assertEqual(
                PREFLIGHT.codex_lumvaleos_server(text),
                {
                    "command": "/opt/lumvale-os/venv/bin/python",
                    "args": ["/opt/lumvale-os/lumvaleos.py", "mcp-server"],
                },
            )


if __name__ == "__main__":
    unittest.main()
