---
description: "Cancel the active Amir Loop and stop the Stop hook re-arming"
allowed-tools: ["Bash(bash \"${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-setup.sh\" --cancel:*)"]
hide-from-slash-command-tool: "true"
---

# Cancel Amir Loop

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-setup.sh" --cancel
```

This removes `.claude/amir-loop.local.md` and writes `.claude/amir-loop-off`.

Both steps matter. Deleting the state file alone would not be enough: the Stop hook arms a new
loop automatically on the next turn, so the loop would simply come back. The off-switch file is
what makes a cancel actually stick.

Re-enable by running `/amir loop` again, or by deleting `.claude/amir-loop-off`.
