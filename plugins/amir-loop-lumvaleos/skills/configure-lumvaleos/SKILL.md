---
name: configure-lumvaleos
description: Configure Amir Loop runtime dependency policy for LumvaleOS as required, preferred, or off.
---

# Configure LumvaleOS governance

Use this skill when the user asks Amir Loop to require, prefer, or disable LumvaleOS governance.

1. Confirm the core `amir-loop` plugin is installed; this companion supplies policy, not a second Stop hook.
2. Select the intended Workspace root with `AMIR_LOOP_WORKSPACE_ROOT` or the shared
   `WORKSPACE_ROOT`, then run the platform-native entrypoint, where MODE is
   `required`, `preferred`, or `off` (default `required`):
   - Windows: resolve `../../scripts/configure-lumvaleos.ps1` from this skill directory and
     invoke it with PowerShell and `-Mode MODE`. Do not invoke bare `bash`; it may resolve to WSL.
   - POSIX: resolve `../../scripts/configure-lumvaleos.sh` and invoke it with Bash and `MODE`.
3. Never overwrite an existing `.claude/amir-loop-dependencies.json`. Read it and make the smallest explicit edit instead.
4. Run `lumvaleos policy validate`, then `lumvaleos policy render` for that Workspace. Do not
   copy another Workspace's generated files.
5. Set the same Workspace selector in the host launcher. Confirm `loop.policy.resolve` returns
   its Workspace id and effective hash.
6. Run the native `amir-loop-doctor` skill and report the dependency policy, Workspace id, and
   policy hash.
7. Explain that a new agent session or host restart is required to reload native instructions,
   MCP configuration, and changed hooks.

In `required` mode, first call `loop.policy.resolve`, verify the Workspace id/hash, then call a
LumvaleOS status or knowledge capability. If the native host returns a typed transport-closed or
transport-unavailable error, normalize it to exact typed status `transport_closed` or
`transport_unavailable`; never forward free-form host error text. Run
`../../scripts/lumvaleos-preflight.ps1` on Windows or
`../../scripts/lumvaleos-preflight.sh` on POSIX exactly once with the intended Workspace. This
declared adapter invokes only the authoritative read-only MCP preflight through the LumvaleOS CLI.
Proceed only for its compact `ok=true` result, and report `transport=cli-mcp-bridge` plus
`degraded=true`; never describe that as native MCP success. If policy resolution and both governed
transports are unavailable, do not begin substantive fleet work or silently replace its governed
knowledge, flow, backlog, evidence, or capability authorization. Report the repair and emit
`<amir-loop-blocked>lumvaleos</amir-loop-blocked>` so Amir Loop pauses without losing the primary
goal. Ordinary repository inspection, builds, tests, and git operations remain native tools after
the preflight succeeds.
