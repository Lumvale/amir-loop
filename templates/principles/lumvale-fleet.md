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

## Before you believe an instrument
- **Treat versioned plugin-cache paths as ephemeral evidence, not stable entrypoints.** A host may
  refresh its cache while an agent still holds an older skill path. On Windows, prefer native
  PowerShell entrypoints; when recovery is required, use the repository-side
  `scripts/amir-loop-current.ps1`, which validates plugin identity and fails closed on ambiguous
  cache versions. Doctor/status output proves installed and persisted state only—never infer a live
  continuation from a cache, state file, claim, or fresh heartbeat.
- **Run a control before believing a ZERO.** Anything that can answer "nothing found" can answer it
  because it broke, and here the two are usually byte-identical: `gh search issues` exits 0 on an
  empty index, so `board.search` returned `matched: 0` with `errors: {}` and `passes.search: "ok"`.
  Measured 2026-09-06: three consecutive searches returned 0 and were one step from being read as an
  empty board. Ask the same instrument something whose answer you already know before a zero becomes
  a finding.
- **Ask the registry at the moment you reach for the shell, not when you plan.** The trigger is an
  action — *"I am about to write a script"*, *"I am about to derive a fact about a repo, the fleet,
  the board or CI from raw `gh`/`git` output"* — not a category you have to classify the work into.
  Call `capability.suggest_for_task` with the task in your own words and read its `hazards` block,
  not only its suggestions.
- **An instrument that is a repo SCRIPT is invisible to the registry.** `lumvale-infra` alone carries
  `check-gate-reachability.mjs`, `check-gates-wired.mjs` and `audit-fleet-workflow-surfaces.mjs`, none
  of which any capability query returns. Grep `scripts/` in the owning repository before concluding
  the estate cannot answer your question.
- **Project your fields on any listing call.** `board.actionable {limit: 400}` returned 159,718
  characters on one line and took four follow-up reads to recover about twenty rows. Pass `fields`
  where it exists, `--jq` where you are driving `gh` directly, and file the absence where neither does.
- **Read `origin/main`, not your checkout.** Every number here is about the default branch, and
  working trees in this fleet run 12-45 commits behind. A pass that measured CI triggers from the
  working tree got 4/15 where the truth was 6/29. Re-fetch, then compare the local `origin/main` SHA
  against `repos/Lumvale/<repo>/commits/main` before publishing a number.

## Definition of done
- Before consequential design, implementation, review, research, incident, schedule or playbook
  closure, resolve `lumvale-docs/engineering/techniques/README.md` fresh and call LumvaleOS
  `technique.strategy` with the concrete question, changed paths, surface and risk tier. Carry every
  selected candidate in a `technique_decision`: `applied` requires its executor, exact artifact/run,
  freshness and limitations; `deferred` requires owner + reopening trigger; `not_applicable`
  requires a reason; missing evidence remains `unknown`. Do not mechanically run all catalog entries.
  The broader catalog widens and never replaces AST/code/workflow graphs, MBT or PBT. Privacy,
  authority, review, ingestion and release controls override relevance, especially for
  restricted-sensitive and not-yet-classified information.
- Capture verified findings and close out through LumvaleOS. Use ordinary local shell, test,
  review, and git tools for implementation; LumvaleOS governs knowledge, workflow, backlog,
  and evidence rather than replacing every engineering tool.
- For material designs and changes, identify the load-bearing invariants and follow ADR-018's
  risk-triggered assurance ladder. Extend the existing LumvaleOS AST + call/import code-graph seam
  for semantic, CFG/DFG, PDG/VDG, call and points-to questions; those richer views are gaps until
  implemented, and unresolved analysis remains `unknown`. Apply contracts,
  PBT, mutation, fuzzing, deterministic simulation, symbolic/concolic analysis, abstract
  interpretation or finite-state model checking only when their failure-shape trigger fits, and
  record material omissions as deferred (owner + trigger), not-applicable (reason), or unknown.
  Formal evidence is bounded evidence about the model, not proof that production failure is
  impossible; finite-state model checking requires a shared executable oracle with implementation
  tests, and generated code and self-healing actions retain ordinary review and authority gates.
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
- Before the final push or merge, rebase onto current `main`, run the repository's
  pre-verification/pre-push contract, and fix failures locally. Bind command evidence and
  self-review to the resulting full head SHA; if rebase or any edit changes HEAD, renew both. This
  is the first correctness barrier. The six-hour Fleet Build is the later fleet integration and
  promotion-evidence layer, with manual dispatch reserved for genuinely urgent diagnosis.

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
