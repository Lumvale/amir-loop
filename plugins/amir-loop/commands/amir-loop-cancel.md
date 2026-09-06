---
description: "Cancel the active Amir Loop and stop the Stop hook re-arming"
allowed-tools: ["Bash(bash \"${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-setup.sh\" --cancel:*)"]
hide-from-slash-command-tool: "true"
---

# Cancel Amir Loop

On Windows, use `scripts/amir-loop-cancel.ps1` through PowerShell; do not invoke bare Bash because
it may resolve to WSL. The executable block below is the POSIX/Claude-host entrypoint.

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-setup.sh" --cancel
```

This removes legacy and pending state, preserves session-scoped `.claude/amir-loop.*.local.md`
state files and writes `.claude/amir-loop-off`.

Both steps matter. Deleting the state file alone would not be enough: the Stop hook arms a new
loop automatically on the next turn, so the loop would simply come back. The off-switch file is
what makes a cancel actually stick.

Re-enable by running `/amir-loop` again, or by deleting `.claude/amir-loop-off`.
