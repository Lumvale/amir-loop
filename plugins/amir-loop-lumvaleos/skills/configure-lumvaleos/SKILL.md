---
name: configure-lumvaleos
description: Configure Amir Loop runtime dependency policy for LumvaleOS as required, preferred, or off.
---

# Configure LumvaleOS governance

Use this skill when the user asks Amir Loop to require, prefer, or disable LumvaleOS governance.

1. Confirm the core `amir-loop` plugin is installed; this companion supplies policy, not a second Stop hook.
2. Resolve `../../scripts/configure-lumvaleos.sh` from this skill directory and run it from
   the intended Workspace root, or with `AMIR_LOOP_WORKSPACE_ROOT`/`WORKSPACE_ROOT` selecting it,
   using `bash PATH MODE`, where MODE is `required`,
   `preferred`, or `off` (default `required`). Claude hosts may equivalently use
   `${CLAUDE_PLUGIN_ROOT}/scripts/configure-lumvaleos.sh`.
3. Never overwrite an existing `.claude/amir-loop-dependencies.json`. Read it and make the smallest explicit edit instead.
4. Resolve the intended LumvaleOS Workspace explicitly. Run `lumvaleos policy validate`, then
   `lumvaleos policy render` for that Workspace. Do not copy another Workspace's generated files.
5. Set `AMIR_LOOP_WORKSPACE_ROOT` (or the shared `WORKSPACE_ROOT`) in the host launcher to the
   intended Workspace. Confirm `loop.policy.resolve` returns its Workspace id and effective hash.
6. Run Amir Loop doctor and report the dependency policy, Workspace id, and policy hash.
7. Explain that a new agent session or host restart is required to reload native instructions,
   MCP configuration, and changed hooks.

In `required` mode, first call `loop.policy.resolve`, verify the Workspace id/hash, then call a
LumvaleOS status or knowledge capability. If policy resolution or LumvaleOS is unavailable, do not
begin substantive fleet work or silently replace its governed knowledge, flow, backlog, evidence,
or capability authorization. Report the repair and emit
`<amir-loop-blocked>lumvaleos</amir-loop-blocked>` so Amir Loop pauses without losing the primary
goal. Ordinary repository inspection, builds, tests, and git operations remain native tools after
the preflight succeeds.
