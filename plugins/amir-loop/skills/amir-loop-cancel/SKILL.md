---
name: amir-loop-cancel
description: Cancel Amir Loop in the current project and prevent the Stop hook from re-arming.
---

# Cancel Amir Loop

Run the cancel entrypoint from the current project directory and show its output verbatim.

- On Windows, resolve `../../scripts/amir-loop-cancel.ps1` from this skill directory and invoke
  it with PowerShell. Do not invoke bare `bash`; it may resolve to WSL before cancellation runs.
- On POSIX, invoke `../../scripts/amir-loop-setup.sh --cancel` with Bash.

Cancellation is project-wide and deliberately writes `.claude/amir-loop-off`. It removes only
pending and legacy state, preserves session-scoped state for evidence, and releases the current
worktree claim through the owner-checked core helper. Do not delete session state or claims by
hand, and do not remove the kill switch unless the user asks to start the loop again.
