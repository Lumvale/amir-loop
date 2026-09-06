---
name: amir-loop-status
description: Show deterministic, read-only Amir Loop state for this project.
---

# Show Amir Loop Status

Run status from the current project directory. For agent-readable evidence, use JSON mode and show
the output verbatim.

- On Windows, resolve `../../scripts/amir-loop-status.ps1` relative to this skill and invoke it
  with PowerShell using `-Json`. Do not invoke bare `bash`; it may resolve to WSL.
- On POSIX, resolve `../../scripts/amir-loop-status.sh` relative to this skill and invoke it with
  Bash using `--json`.

If the host exposes its session identifier, pass it as `-Session ID` on PowerShell or
`--session ID` on POSIX. Otherwise preserve `ambiguous`, `absent`, and `unknown` values; do not
guess a session or claim that a state file, worktree claim, or heartbeat proves process liveness.
Status is read-only. Do not remove a kill switch, state file, or claim as part of diagnosis.
