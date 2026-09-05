#!/usr/bin/env python3
"""Reconcile and claim Workspace work into the active agentic IDE session.

The hook is intentionally a thin, fail-open signal. LumvaleOS owns due-ness, checkpointing,
receipts, and its Workspace-global singleton lease; Amir Loop never implements a second scheduler.
"""

from __future__ import annotations

import ast
import os
from pathlib import Path
import json
import subprocess
import sys
from typing import Any


def root_from_server(command: str, arguments: list[Any] | None = None) -> Path | None:
    """Recover the engine root from the same MCP command shapes as the preflight adapter."""
    for value in [command, *(str(item) for item in (arguments or []))]:
        candidate = Path(value.strip().strip('"')).expanduser()
        lowered = candidate.name.lower()
        if lowered in {"lumvaleos-mcp.cmd", "lumvaleos-mcp.sh"}:
            return candidate.parent.parent
        if lowered == "lumvaleos.py":
            return candidate.parent
        if lowered == "lumvaleos_mcp_server.py" and candidate.parent.name == "scripts":
            return candidate.parent.parent
    return None


def lumvaleos_server(text: str) -> dict[str, Any]:
    """Read the one Codex TOML table needed by the startup adapter.

    Python 3.11+ owns the complete TOML grammar through ``tomllib``. The
    self-hosted AL2023 runner still provides Python 3.9, so its compatibility
    path deliberately recognizes only the literal ``command`` and ``args``
    values inside ``[mcp_servers.lumvaleos]``. Unsupported shapes resolve to an
    absent server and keep this optional wake-up hook fail open.
    """
    try:
        import tomllib
    except ModuleNotFoundError:
        values: dict[str, Any] = {}
        in_server = False
        for raw in text.splitlines():
            line = raw.strip()
            if line.startswith("["):
                in_server = line == "[mcp_servers.lumvaleos]"
                continue
            if not in_server or "=" not in line:
                continue
            key, literal = (part.strip() for part in line.split("=", 1))
            if key not in {"command", "args"}:
                continue
            try:
                values[key] = ast.literal_eval(literal)
            except (SyntaxError, ValueError):
                return {}
        command = values.get("command")
        arguments = values.get("args", [])
        if not isinstance(command, str) or not isinstance(arguments, list):
            return {}
        return values
    return tomllib.loads(text).get("mcp_servers", {}).get("lumvaleos", {})


def lumvaleos_root() -> Path | None:
    explicit = os.environ.get("LUMVALEOS_ROOT")
    if explicit:
        candidate = Path(explicit).expanduser()
        return candidate if (candidate / "lumvaleos.py").is_file() else None

    config = Path(os.environ.get(
        "AMIR_LOOP_CODEX_CONFIG",
        str(Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "config.toml"),
    ))
    if config.is_file():
        try:
            server = lumvaleos_server(config.read_text(encoding="utf-8"))
            candidate = root_from_server(str(server.get("command", "")), server.get("args", []))
            if candidate and (candidate / "lumvaleos.py").is_file():
                return candidate
        except (OSError, ValueError, TypeError):
            # An optional malformed or unreadable host config is treated as absent so discovery
            # can continue through the current working directory.
            pass

    # Antigravity keeps MCP configuration in its Gemini customization root.  Reuse both
    # the runtime command and Workspace environment from that authoritative registration.
    antigravity_config = Path.home() / ".gemini" / "config" / "mcp_config.json"
    if antigravity_config.is_file():
        try:
            server = json.loads(antigravity_config.read_text(encoding="utf-8")).get(
                "mcpServers", {}).get("lumvaleos", {})
            for key, value in (server.get("env") or {}).items():
                os.environ.setdefault(str(key), str(value))
            candidate = root_from_server(str(server.get("command", "")), server.get("args", []))
            if candidate and (candidate / "lumvaleos.py").is_file():
                return candidate
        except (OSError, ValueError, TypeError):
            pass
    current = Path.cwd().resolve()
    for candidate in (current, *current.parents):
        if (candidate / "lumvaleos.py").is_file():
            return candidate
    return None


def interpreter(root: Path) -> Path:
    explicit = os.environ.get("LUMVALEOS_PYTHON")
    if explicit:
        return Path(explicit).expanduser()
    suffix = Path("Scripts/python.exe") if os.name == "nt" else Path("bin/python")
    for dirname in ("venv", ".venv"):
        candidate = root / dirname / suffix
        if candidate.is_file():
            return candidate
    return Path(sys.executable)


def hook_payload() -> dict[str, Any]:
    try:
        value = json.load(sys.stdin)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def ide_name(environment: dict[str, str]) -> str:
    if environment.get("CODEX_HOME") or environment.get("CODEX_THREAD_ID"):
        return "codex"
    if environment.get("CLAUDE_CODE") or environment.get("CLAUDE_SESSION_ID"):
        return "claude-code"
    return environment.get("AGENTIC_IDE", "unknown")


def injected_context(claim: dict[str, Any], command_prefix: str = "lumvaleos scheduler") -> str:
    token = str(claim["claim_token"])
    return "\n".join([
        f"LumvaleOS scheduled work `{claim['automation']}` has been exclusively claimed by this session.",
        "Perform it now using the IDE's normal tools and authenticated capabilities:",
        "",
        str(claim["prompt"]),
        "",
        "Checkpoint only after verifying the outcome. On success run:",
        f"{command_prefix} complete --claim {token} --status success --json",
        "If the work fails or is blocked, run the same command with `--status failed`.",
        "Do not end the turn while leaving the claim unreported.",
    ])


def main() -> int:
    root = lumvaleos_root()
    if root is None:
        return 0
    python = interpreter(root)
    if not python.is_file():
        return 0
    environment = os.environ.copy()
    payload = hook_payload()
    event = str(payload.get("hook_event_name") or payload.get("hookEventName") or
                "SessionStart")
    session = str(payload.get("session_id") or payload.get("sessionId") or
                  payload.get("conversation_id") or environment.get("CODEX_THREAD_ID") or
                  environment.get("CLAUDE_SESSION_ID") or "unknown")
    scheduler = root / "modules" / "automation_scheduler" / "run_scheduler.py"
    command = [str(python), str(scheduler), "activate",
               "--ide", ide_name(environment), "--session", session, "--json"]
    try:
        result = subprocess.run(command, cwd=root, env=environment, check=False, text=True,
                                capture_output=True, timeout=8)
        response = json.loads(result.stdout) if result.returncode == 0 else {}
        claim = response.get("claim") if isinstance(response, dict) else None
        if isinstance(claim, dict):
            command_prefix = f'"{python}" "{scheduler}"'
            context = injected_context(claim, command_prefix)
            if environment.get("AMIR_LOOP_HOST_OUTPUT") == "antigravity":
                json.dump({"injectSteps": [{"ephemeralMessage": context}]}, sys.stdout)
            else:
                json.dump({"hookSpecificOutput": {"hookEventName": event,
                                                   "additionalContext": context}}, sys.stdout)
            sys.stdout.write("\n")
    except (OSError, subprocess.TimeoutExpired, ValueError):
        # Agent startup must remain usable if the optional local runtime is absent or broken.
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
