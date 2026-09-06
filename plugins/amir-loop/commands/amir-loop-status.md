---
description: Show the current Amir Loop state for this project
---

Show the output verbatim. Do not modify any loop state.

- On Windows, run `& "${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-status.ps1"` from
  PowerShell. Do not invoke bare Bash because it may resolve to WSL.
- On POSIX, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-status.sh"`.

For agent-readable diagnostics, use JSON mode. When the host exposes a session
identifier, pass it with `-Session ID` on PowerShell or `--session ID` on POSIX;
otherwise preserve an `ambiguous` result rather than guessing among sessions.
