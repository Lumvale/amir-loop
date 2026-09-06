# LumvaleOS Workspace policy integration

Amir Loop remains the portable owner of host lifecycle, bounded continuation, and verified
closeout. LumvaleOS remains the owner of Workspace knowledge, instructions, capability policy,
accounts, environments, leases, and evidence. The `amir-loop-lumvaleos` companion is the thin
integration between them and registers no second Stop hook.

Each LumvaleOS Workspace authors one versioned policy bundle. `lumvaleos policy render` publishes
the effective standing orders to `.lumvaleos/amir-loop-principles.md`; its header includes the
Workspace id and deterministic policy hash. Select it in the agent host with:

```text
AMIR_LOOP_WORKSPACE_ROOT=/path/to/ws-lumvale
```

The Workspace may itself have a Git remote so its authored policy and knowledge can be reused and
distributed. That remote does not turn the Workspace into a product repository. In particular,
repositories under `lumvale-os-workspaces/*` are excluded from ordinary product implementation,
PR-drain, and board-filing work unless the owner explicitly names one in the direct request.

`WORKSPACE_ROOT` is accepted when the same environment selects both LumvaleOS and Amir Loop.
The selected directory must contain `workspace.yaml`. A selected Workspace never falls through to
another ancestor's principles. If no Workspace is selected, the existing nearest-project lookup is
retained for portable, non-Lumvale use and stops at the first `workspace.yaml` boundary.

Rendered instruction text is snapshotted into the Amir Loop session state, so edits cannot silently
change an active run. LumvaleOS capability allow, deny, and required-grant rules are evaluated live
on every server call, so a revocation does not wait for a new loop.

Capability selection follows the same portability boundary. Amir Loop core describes the required
function (for example, a compact immutable-evidence reader) without naming a product or tool. A
Workspace or nearest-project policy may advertise the concrete capability and any governed fallback;
that policy is snapshotted into session state and remains subject to the goal-relevance, capability,
safety, and authority gates. Another product can therefore supply a different capability projection
without changing the portable Stop hook.

Workspace configuration can narrow behavior but cannot disable Amir Loop's bounds, direct-request
priority, evidence-backed closeout, or LumvaleOS tenancy, authentication, audit, secret, production,
and authority invariants.

For Lumvale fleet policy, the rendered principles also carry the portfolio technique-selection
contract. Material work invokes LumvaleOS `technique.strategy`; its result is a candidate set and
complete evidence ledger, not permission to run all methods or a claim that any method executed.
The loop may close only after selected candidates are recorded as evidence-backed `applied`, owned
`deferred`, reasoned `not_applicable`, or honest `unknown`. Existing AST/code/workflow graphs, MBT
and PBT remain in force. Workspace privacy and authority controls take precedence, so
restricted-sensitive material cannot become analyzable merely because a technique is relevant.
When LumvaleOS advertises `technique.record`, Amir Loop uses it to persist a known disposition into
the active Workspace's existing assurance store. It never hand-writes the evidence record, accepts
an absolute/out-of-Workspace assurance path, or treats the selector result as execution evidence.
