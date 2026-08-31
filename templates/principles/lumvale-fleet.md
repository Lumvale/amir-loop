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

## Definition of done
- Capture verified findings and close out through LumvaleOS. Use ordinary local shell, test,
  review, and git tools for implementation; LumvaleOS governs knowledge, workflow, backlog,
  and evidence rather than replacing every engineering tool.

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
