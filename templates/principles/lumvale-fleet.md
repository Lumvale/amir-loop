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

## Never
- <prod deploys, spending money, credential handling, ...>
