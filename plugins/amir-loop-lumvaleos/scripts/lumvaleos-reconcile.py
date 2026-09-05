#!/usr/bin/env python3
"""Wake LumvaleOS reconciliation without depending on a clock or host scheduler.

The hook is intentionally a thin, fail-open signal. LumvaleOS owns due-ness, checkpointing,
receipts, and its Workspace-global singleton lease; Amir Loop never implements a second scheduler.
"""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


def lumvaleos_root() -> Path | None:
    explicit = os.environ.get("LUMVALEOS_ROOT")
    if explicit:
        candidate = Path(explicit).expanduser()
        return candidate if (candidate / "lumvaleos.py").is_file() else None
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


def main() -> int:
    root = lumvaleos_root()
    if root is None:
        return 0
    python = interpreter(root)
    if not python.is_file():
        return 0
    command = [str(python), str(root / "lumvaleos.py"), "scheduler", "run", "--json"]
    environment = os.environ.copy()
    try:
        if environment.get("AMIR_LOOP_RECONCILE_FOREGROUND") == "1":
            return subprocess.run(command, cwd=root, env=environment, check=False).returncode
        flags = 0
        if os.name == "nt":
            flags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
        subprocess.Popen(
            command,
            cwd=root,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=os.name != "nt",
            creationflags=flags,
        )
    except OSError:
        # Agent startup must remain usable if the optional local runtime is absent or broken.
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
