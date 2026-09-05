#!/usr/bin/env python3
"""Verify the governed LumvaleOS CLI-to-MCP bridge after native transport failure.

This never invokes arbitrary capabilities and never treats the bridge as native MCP
success. It calls only the authoritative read-only ``lumvaleos_preflight`` tool.
"""

from __future__ import annotations

import argparse
import ast
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone
import time
from typing import Any


REQUIRED_SUBSYSTEMS = (
    "workspace",
    "engine",
    "graph",
    "capability_router",
    "engineering_board",
    "interpreter",
    "dependencies",
)
FALLBACK_STATUSES = {"transport_closed", "transport_unavailable"}
KNOWN_STATUSES = {"ok", "degraded", "unavailable", "could-not-check"}
USABLE_STATUSES = {"ok", "degraded"}


def emit(ok: bool, code: str, *, transport: str = "cli-mcp-bridge",
         degraded: bool = True, receipt_path: Path | None = None, **fields: Any) -> int:
    payload = {
        "ok": ok,
        "transport": transport,
        "degraded": degraded,
        "code": code,
        **fields,
    }
    if ok and receipt_path is not None:
        receipt = {"version": 1, "transport": transport, "degraded": degraded,
                   "checked_at": datetime.now(timezone.utc).isoformat(),
                   "expires_at_epoch": int(time.time()) + 900,
                   "workspace": fields.get("workspace", "unknown"),
                   "evidence": payload.get("evidence", {})}
        try:
            receipt_path.parent.mkdir(parents=True, exist_ok=True)
            temporary = receipt_path.with_suffix(receipt_path.suffix + ".tmp")
            temporary.write_text(json.dumps(receipt, sort_keys=True) + "\n", encoding="utf-8")
            temporary.replace(receipt_path)
        except OSError:
            payload["receipt"] = "not-written"
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))
    return 0 if ok else 1


def root_from_server(command: str, arguments: list[Any] | None = None) -> Path | None:
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


def codex_lumvaleos_server(text: str) -> dict[str, Any]:
    """Read the configured server on Python 3.9 as well as Python 3.11+.

    AL2023 currently supplies Python 3.9, which predates ``tomllib``. Its
    compatibility path deliberately recognizes only the literal command and
    args values needed for root discovery; unsupported TOML remains absent.
    """
    try:
        import tomllib
    except ModuleNotFoundError:
        values: dict[str, Any] = {}
        section = ""
        for raw in text.splitlines():
            line = raw.strip()
            if line.startswith("["):
                section = line
                continue
            if section != "[mcp_servers.lumvaleos]" or "=" not in line:
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


def configured_root() -> Path | None:
    for key in ("LUMVALEOS_ROOT",):
        if os.environ.get(key):
            return Path(os.environ[key]).expanduser()
    if os.environ.get("LUMVALEOS_MCP_COMMAND"):
        root = root_from_server(os.environ["LUMVALEOS_MCP_COMMAND"])
        if root:
            return root

    codex_config = Path(
        os.environ.get(
            "AMIR_LOOP_CODEX_CONFIG",
            str(Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "config.toml"),
        )
    )
    if codex_config.is_file():
        try:
            server = codex_lumvaleos_server(codex_config.read_text(encoding="utf-8"))
            root = root_from_server(str(server.get("command", "")), server.get("args", []))
            if root:
                return root
        except (OSError, ValueError, TypeError):
            # An optional malformed or unreadable Codex config is treated as absent so discovery
            # can continue through the remaining configured sources.
            pass

    claude_config = Path(os.environ.get("AMIR_LOOP_CLAUDE_CONFIG", Path.home() / ".claude.json"))
    if claude_config.is_file():
        try:
            data = json.loads(claude_config.read_text(encoding="utf-8"))
            server = data.get("mcpServers", {}).get("lumvaleos", {})
            root = root_from_server(str(server.get("command", "")), server.get("args", []))
            if root:
                return root
        except (OSError, ValueError, TypeError):
            # An optional malformed or unreadable Claude config is treated as absent so discovery
            # can continue through the current working directory.
            pass

    current = Path.cwd().resolve()
    for candidate in (current, *current.parents):
        if (candidate / "lumvaleos.py").is_file():
            return candidate
    return None


def interpreter_for(root: Path) -> Path:
    explicit = os.environ.get("LUMVALEOS_PYTHON")
    if explicit:
        return Path(explicit).expanduser()
    suffix = Path("Scripts/python.exe") if os.name == "nt" else Path("bin/python")
    for dirname in ("venv", ".venv"):
        candidate = root / dirname / suffix
        if candidate.is_file():
            return candidate
    return Path(sys.executable)


def parse_bridge_output(stdout: str) -> dict[str, Any] | None:
    for line in reversed(stdout.splitlines()):
        try:
            envelope = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(envelope, dict) or envelope.get("ok") is not True:
            return None
        result = envelope.get("result")
        if not isinstance(result, dict) or result.get("isError") is True:
            return None
        for item in result.get("content", []):
            if isinstance(item, dict) and item.get("type") == "text":
                try:
                    parsed = json.loads(item.get("text", ""))
                except (json.JSONDecodeError, TypeError):
                    continue
                if isinstance(parsed, dict):
                    return parsed
        return None
    return None


def normalized_status(value: Any) -> str:
    status = value if isinstance(value, str) else "unknown"
    return status if status in KNOWN_STATUSES else "unknown"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-status", required=True,
                        choices=("transport_closed", "transport_unavailable"))
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--lumvaleos-root")
    parser.add_argument("--timeout-seconds", type=float, default=30.0)
    parser.add_argument("--receipt-path")
    args = parser.parse_args()

    receipt_path = Path(args.receipt_path).expanduser() if args.receipt_path else None
    if args.native_status not in FALLBACK_STATUSES:
        return emit(False, "fallback-not-authorized", remedy="use the native MCP result")
    if args.timeout_seconds <= 0 or args.timeout_seconds > 120:
        return emit(False, "invalid-timeout", remedy="choose a timeout in (0, 120] seconds")

    root = Path(args.lumvaleos_root).expanduser() if args.lumvaleos_root else configured_root()
    if root is None or not (root / "lumvaleos.py").is_file():
        return emit(
            False,
            "lumvaleos-not-found",
            remedy="set LUMVALEOS_ROOT or configure the lumvaleos MCP command",
        )
    python = interpreter_for(root)
    if not python.is_file():
        return emit(False, "interpreter-not-found", remedy="set LUMVALEOS_PYTHON")

    arguments = json.dumps({"workspace": args.workspace}, separators=(",", ":"))
    command = [
        str(python),
        str(root / "lumvaleos.py"),
        "mcp",
        "invoke",
        "lumvaleos_preflight",
        "--arguments-json",
        arguments,
    ]
    environment = os.environ.copy()
    try:
        completed = subprocess.run(
            command,
            cwd=root,
            env=environment,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=args.timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return emit(False, "bridge-timeout", remedy="repair LumvaleOS CLI preflight latency")
    except OSError:
        return emit(False, "bridge-launch-failed", remedy="repair the configured LumvaleOS interpreter")

    report = parse_bridge_output(completed.stdout)
    if completed.returncode != 0 or report is None:
        return emit(False, "bridge-invalid-response", remedy="run LumvaleOS doctor from the selected workspace")

    statuses = {
        name: normalized_status(report.get(name, {}).get("status"))
        for name in REQUIRED_SUBSYSTEMS
    }
    unhealthy = sorted(name for name, status in statuses.items() if status not in USABLE_STATUSES)
    if unhealthy:
        return emit(
            False,
            "preflight-unhealthy",
            workspace=args.workspace,
            required_subsystems=statuses,
            unhealthy=unhealthy,
            remedy="repair the reported LumvaleOS subsystems before substantive work",
        )

    return emit(
        True,
        "governed-fallback-healthy",
        receipt_path=receipt_path,
        workspace=args.workspace,
        required_subsystems=statuses,
        evidence={
            "attempts": 1,
            "tool": "lumvaleos_preflight",
            "native_transport": args.native_status,
        },
        remedy="restart the agent session to restore native MCP; do not relabel this fallback as native success",
    )


if __name__ == "__main__":
    raise SystemExit(main())
