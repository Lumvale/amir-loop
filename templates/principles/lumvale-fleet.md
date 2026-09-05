# Amir Loop standing orders

These are appended verbatim to every armed loop rooted at or below this
directory. Anything sharp belongs here rather than in the plugin: it is
opt-in per project and version-controlled.

## Backlog
- Use LumvaleOS governed flows and backlog tools after the direct request is exhausted.
- Resolve and follow `standard-loop@v2`; query LumvaleOS knowledge before re-deriving fleet facts.
- At the fallback boundary, call `flow.next_due_playbook` once with the session's real capabilities
  and reachable environments. Execute a returned lease before generic backlog work; if none is due,
  continue oldest-first. Never consult it to escape unfinished direct work.
- Emit evidence-backed portable improvements as `learning.discovered`. The learning playbook must
  deduplicate across Amir Loop and LumvaleOS trackers and file the smallest owning story; capture
  does not alter priority or authorise self-modification.

## Merge authority
- <what the loop may merge unattended, and what it must escalate>
- Treat `lumvale-os-workspaces/*`, including `ws-lumvale`, as reusable and distributed Workspace
  storage, not as Lumvale product repositories. Do not create implementation PRs, drain their PR
  queues, or file ordinary product work there unless the owner explicitly scopes that Workspace
  repository into the direct request. A Git remote alone does not grant product-fleet scope.

## Definition of done
- Capture verified findings and close out through LumvaleOS. Use ordinary local shell, test,
  review, and git tools for implementation; LumvaleOS governs knowledge, workflow, backlog,
  and evidence rather than replacing every engineering tool.
- For material designs and changes, identify the load-bearing invariants and follow ADR-018's
  risk-triggered assurance ladder. Reuse the LumvaleOS Code Property Graph for ASG, CFG/DFG,
  PDG/VDG, call and points-to questions; report unresolved analysis as `unknown`. Apply contracts,
  PBT, mutation, fuzzing, deterministic simulation, symbolic/concolic analysis, abstract
  interpretation or finite-state model checking only when their failure-shape trigger fits, and
  record material omissions as deferred (owner + trigger), not-applicable (reason), or unknown.
  Formal evidence is bounded evidence about the model, not proof that production failure is
  impossible; generated code and self-healing actions retain ordinary review and authority gates.
  When a canonical statechart exists, derive bounded, replayable MBT paths and drive an independent
  production adapter. BFS state reachability is not transition, transition-pair, variant or
  concurrency coverage; report each denominator and never use the implementation as its own oracle.
  For cross-system changes, join SCIP/LSIF semantic indexes with exact-version API/event contracts
  and privacy-safe OpenTelemetry traces. Independently deployed consumers/providers require contract
  verification; schema-generated clients remain reproducible artifacts from the owning contract repo.
  CDC requires atomic publication, idempotency, ordering, replay and reconciliation. Chaos starts with
  deterministic faults and bounded local/UAT experiments; production or recurring chaos requires
  explicit owner/release authority plus abort and cleanup criteria.
- For build/test health, inspect the latest relevant natural `Fleet Build` run in
  `Lumvale/lumvale-infra` (`fleet-scheduler.yml`) and attribute repository + tier + tested SHA.
  Ordinary PRs intentionally have no runner-backed build/test checks. Never dispatch a product
  workflow after merge; fix the owning repository and require a later natural Fleet Build receipt
  before calling that default-branch SHA centrally verified or releasable.

## Lumvale architecture and recursive improvement
- Follow the current Lumvale Architecture and Engineering ADRs, autonomous constitution,
  safety tiers, environment promotion authority, and evidence semantics. A stale summary or
  local copy cannot override the durable sources.
- Improve Amir Loop and LumvaleOS through evidence-backed learning, focused changes,
  independent review where the safety tier requires it, canaries, rollback, and measured
  outcomes. Never weaken a gate to make an improvement appear successful.
- The core is domain-neutral. Generic goal persistence, provider routing, recovery,
  permission diagnosis and host adapters belong in Amir Loop. Domain playbooks and evidence
  contracts belong in LumvaleOS; Lumvale accounts, tenancy, approved routes, cost limits and
  release authority belong in Lumvale policy capabilities.
- Resolve permission bottlenecks through existing authorized paths, least-privilege grants or
  explicit owner approval. Never bypass authentication, authorization, entitlement, tenancy,
  secrets handling, production, or cost controls.

## Never
- <prod deploys, spending money, credential handling, ...>
