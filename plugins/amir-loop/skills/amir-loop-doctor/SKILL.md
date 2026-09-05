---
name: amir-loop-doctor
description: Diagnose why Amir Loop is or is not working on this machine.
---

# Diagnose Amir Loop

Run the doctor from the current project directory and show its output verbatim.

For agent-readable diagnostics, prefer the schema-versioned JSON mode (`-Json` on
PowerShell or `--json` on POSIX) and report only failed checks and actionable warnings.
The default text mode remains the human-facing diagnostic.

- On Windows, resolve `../../scripts/amir-loop-doctor.ps1` from this skill directory and invoke it with PowerShell. Do not invoke bare `bash`; it may resolve to WSL before Amir Loop can diagnose the host.
- On POSIX, resolve `../../scripts/amir-loop-doctor.sh` and invoke it with Bash.

For each `FAIL:` line, state the single concrete fix. Warnings are evidence boundaries, not failures.

If the diagnostic reports a failing Windows Codex notification hook, rerun the PowerShell entrypoint with `-DisableCodexNotify` only when the user explicitly authorizes that repair. It creates a timestamped backup and delegates to the same guarded doctor action.

The doctor diagnoses state; it does not prove a live continuation occurred. Report installation, static checks and live runtime evidence separately.
