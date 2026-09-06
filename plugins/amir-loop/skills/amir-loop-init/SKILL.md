---
name: amir-loop-init
description: Scaffold project-scoped Amir Loop principles without replacing existing standing orders.
---

# Initialize Amir Loop Principles

- On Windows, resolve `../../scripts/amir-loop-init.ps1` from this skill directory and invoke it
  from PowerShell. Do not invoke bare `bash`; it may resolve to WSL.
- On POSIX, resolve `../../scripts/amir-loop-init.sh` and invoke it with Bash.

Show the output verbatim. If principles already exist, the entrypoint displays and preserves them;
do not replace, merge, or normalize that file. When a new template is created, ask which backlog,
merge authority, definition of done, and prohibited actions belong in its placeholders.
