---
description: Scaffold an Amir Loop principles file for this project
---

Run the native scaffold entrypoint and show its output. It preserves an existing
principles file byte-for-byte.

- On Windows, run `& "$env:CLAUDE_PLUGIN_ROOT/scripts/amir-loop-init.ps1"` from
  PowerShell. Do not invoke bare Bash because it may resolve to WSL.
- On POSIX, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/amir-loop-init.sh"`.

When a new file is created, ask which backlog, merge authority and definition of
done apply, then fill the placeholders from the answers. Never replace an existing
principles file: it may hold standing orders someone relies on.
