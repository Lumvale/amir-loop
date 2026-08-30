#!/bin/bash
# Amir Loop - start or cancel a loop by hand, in the current project.
#
# The Stop hook (amir-loop-stop.sh) arms a loop automatically with a generic "continue"
# prompt. This is for when you want to drive one deliberately with your OWN prompt, or to
# stop one now.
#
#   amir-loop-setup.sh Build the parser and its tests --max-iterations 20
#   amir-loop-setup.sh --completion-promise 'ALL TESTS PASS' Fix the auth bug
#   amir-loop-setup.sh --cancel
#
# START clears the .claude/amir-loop-off kill switch; CANCEL sets it, so cancelling
# really stops rather than letting the Stop hook re-arm on the next turn.

set -uo pipefail

MAX=1000
PROMISE="AMIR LOOP COMPLETE"
CANCEL=0
PARTS=()

LITERAL=0
while [ $# -gt 0 ]; do
  if [ "$LITERAL" = "1" ]; then
    PARTS+=("$1"); shift; continue
  fi
  case "$1" in
    --) LITERAL=1; shift ;;
    --cancel) CANCEL=1; shift ;;
    --max-iterations)
      case "${2:-}" in
        ''|*[!0-9]*) echo "error: --max-iterations needs a whole number, got '${2:-}'" >&2; exit 1 ;;
      esac
      MAX="$2"; shift 2 ;;
    --completion-promise)
      [ -n "${2:-}" ] || { echo "error: --completion-promise needs text (quote multi-word)" >&2; exit 1; }
      PROMISE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) PARTS+=("$1"); shift ;;
  esac
done

STATE=".claude/amir-loop.pending.local.md"
OFF=".claude/amir-loop-off"

mkdir -p .claude 2>/dev/null || { echo "error: cannot create .claude here" >&2; exit 1; }

# Same project-scoped standing orders the Stop hook appends, resolved the same way:
# searched from CWD upwards, like .gitignore or .editorconfig. See amir-loop-stop.sh's
# principles-resolution block for why this must climb rather than check CWD alone.
PRINCIPLES=""
DEPENDENCIES=""
_dir="$PWD"
while [ -n "$_dir" ]; do
  if [ -z "$PRINCIPLES" ] && [ -f "$_dir/.claude/amir-loop-principles.md" ]; then
    PRINCIPLES="$_dir/.claude/amir-loop-principles.md"
  fi
  if [ -z "$DEPENDENCIES" ] && [ -f "$_dir/.claude/amir-loop-dependencies.json" ]; then
    DEPENDENCIES="$_dir/.claude/amir-loop-dependencies.json"
  fi
  [ -n "$PRINCIPLES" ] && [ -n "$DEPENDENCIES" ] && break
  _parent=$(dirname "$_dir")
  [ "$_parent" = "$_dir" ] && break
  _dir="$_parent"
done

DEPENDENCY_BRIEF=""
if [ -n "$DEPENDENCIES" ]; then
  _vendor="$(cd "$(dirname "$0")/.." && pwd)/vendor/jq"
  case "$(uname -s 2>/dev/null)" in
    Linux) _cand="$_vendor/jq-linux-amd64" ;;
    Darwin) case "$(uname -m 2>/dev/null)" in arm64) _cand="$_vendor/jq-macos-arm64";; *) _cand="$_vendor/jq-macos-amd64";; esac ;;
    MINGW*|MSYS*|CYGWIN*) _cand="$_vendor/jq-windows-amd64.exe" ;;
    *) _cand="" ;;
  esac
  if [ -n "$_cand" ] && "$_cand" --version >/dev/null 2>&1; then
    JQ="$_cand"
  elif command -v jq >/dev/null 2>&1; then
    JQ="jq"
  else
    JQ=""
  fi
  if [ -n "$JQ" ] && "$JQ" -e '
    .version == 1 and (.dependencies | type == "array") and
    all(.dependencies[]; (.id | type == "string" and length > 0) and
      (.policy == "required" or .policy == "preferred" or .policy == "off") and
      ((.kind // "tool") | type == "string") and
      ((.preflight // "") | type == "string") and
      ((.repair // "") | type == "string"))
  ' "$DEPENDENCIES" >/dev/null 2>&1; then
    DEPENDENCY_BRIEF=$("$JQ" -r '["## Runtime dependency policy", "",
      "Before substantive work, preflight each dependency below once for this run.",
      (.dependencies[] | select(.policy != "off") |
        "- " + .id + " (" + (.kind // "tool") + ", " + .policy + "): " +
        (.preflight // "probe that the capability is callable") +
        (if (.repair // "") == "" then "" else " Repair: " + .repair end)), "",
      "A failed required dependency must stop substantive work. Report the repair and output",
      "<amir-loop-blocked>DEPENDENCY_ID</amir-loop-blocked>. Preferred dependencies may degrade",
      "with one explicit warning; off dependencies are skipped."] | join("\n")' "$DEPENDENCIES")
  else
    DEPENDENCY_BRIEF="## Runtime dependency policy

The dependency policy at $DEPENDENCIES is invalid. Do not begin substantive work; report the
schema error and output <amir-loop-blocked>dependency-policy</amir-loop-blocked>."
  fi
fi

if [ "$CANCEL" = "1" ]; then
  rm -f .claude/amir-loop.local.md .claude/amir-loop.pending.local.md .claude/amir-loop.*.local.md
  : > "$OFF"
  echo "Amir Loop cancelled. The Stop hook will not re-arm in this project."
  echo "Run the start command again (or delete $OFF) to re-enable it."
  exit 0
fi

PROMPT="${PARTS[*]:-}"
if [ -z "$PROMPT" ]; then
  echo "error: no prompt given" >&2
  echo "  amir-loop-setup.sh <what to work on> [--max-iterations N] [--completion-promise TEXT]" >&2
  exit 1
fi

# 0 would mean "never stop" to the hook; clamp it the same way the hook does.
case "$MAX" in 0) MAX=1000 ;; esac

rm -f "$OFF"

{
  cat <<EOF
---
active: true
session_id: "pending"
iteration: 1
max_iterations: $MAX
completion_promise: "$PROMISE"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$PROMPT
EOF
  # Same project-scoped standing orders the Stop hook appends, so a hand-started loop and
  # an auto-armed one run under identical rules.
  if [ -f "$PRINCIPLES" ]; then
    printf '\n'
    cat "$PRINCIPLES"
  fi
  if [ -n "$DEPENDENCY_BRIEF" ]; then
    printf '\n\n%s\n' "$DEPENDENCY_BRIEF"
  fi
  cat <<EOF

## Goal precedence

The explicit prompt above is the PRIMARY GOAL. Continue it until every actionable part is
implemented, verified, and delivered, or until every in-scope way to advance it has been
exhausted. A status report, partial result, filed follow-up issue, pending check, or newly
discovered blocker means this goal still has work remaining; it is not permission to
switch scope.

Project standing orders and their backlog rules are FALLBACK WORK. Consult or select from
that backlog only after the primary goal is genuinely exhausted. An oldest-first or
highest-priority rule must never pre-empt unfinished work from the explicit prompt.

## Related-work reconciliation

Treat directly related tracker items and open pull requests as part of the PRIMARY GOAL.
Once the request is understood, perform one bounded search of the relevant repositories,
issue trackers, boards, and open pull requests using the component, symptoms, identifiers,
root cause, and intended outcome. Reuse existing investigation and avoid filing duplicates.

Classify credible matches before acting:

- CONFIRMED DUPLICATE: same root cause and materially the same required outcome. Select a
  canonical item, cross-link evidence, and close the duplicate only when authorised and the
  canonical item represents all remaining acceptance criteria.
- CO-RESOLVABLE: distinct tracked work safely completed by the same coherent implementation
  and verification. Include it and update or close it with delivered evidence.
- RELATED BUT DISTINCT: overlapping context but a different root cause, scope, or acceptance
  criteria. Link it and leave it open; do not expand the current goal.

Never infer duplication from title similarity alone. Before finishing, reconcile the matches,
link delivered evidence, and close only work that is actually satisfied and authorised. This
is bounded related work, not permission to roam the board.

## Context durability

After any context compaction or conversation summarisation, re-read this session-scoped file
before acting. Reconstruct the PRIMARY GOAL from the explicit prompt and verified repository or
tracker evidence. A summary's suggested next step is a hint, not new authority: ignore it when it
would switch to fallback backlog work while the primary goal still has actionable work.

If, and only if, the work above is genuinely finished and verified, output
<promise>$PROMISE</promise> to end the loop.

Finishing one item is not finishing. If you have just filed follow-up work, or named
anything as pending, blocked, deferred, or a next step, that is your own evidence there is
more to do - pick the next thing up and keep going instead of promising. Do not promise to
escape a hard step, and do not promise because you are unsure how to continue: say what is
blocking you and keep working.
EOF
} > "$STATE"

echo "Amir Loop armed in this project."
echo "  iterations : up to $MAX (you get MAX-1 extra turns; the counter starts at 1)"
echo "  to stop    : output <promise>$PROMISE</promise> when it is genuinely TRUE"
echo "  state      : $STATE"
echo ""
echo "$PROMPT"
