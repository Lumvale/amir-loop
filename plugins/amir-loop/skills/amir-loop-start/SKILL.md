---
name: amir-loop-start
description: Start Amir Loop for the current project with an exact user-supplied prompt.
---

# Start Amir Loop

Pass the complete prompt as one argument. Never interpolate prompt text into a command string.

- On Windows, resolve `../../scripts/amir-loop-setup.ps1` from this skill directory and invoke
  it from PowerShell with `-Prompt` and the exact prompt string. Do not invoke bare `bash`; it
  may resolve to WSL before Amir Loop can validate the host path.
- On POSIX, resolve `../../scripts/amir-loop-setup.sh` and invoke it with Bash, passing the exact
  prompt as one quoted argument.

Show the setup receipt verbatim. A receipt proves persisted loop state; it does not prove that a
future continuation has run. Never emit a configured completion promise unless it is true.
