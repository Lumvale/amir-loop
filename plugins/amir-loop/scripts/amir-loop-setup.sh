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

# --cancel and -h/--help have no legitimate use mixed into a free-text prompt: --cancel
# is only ever invoked by the dedicated /amir-loop-cancel command (always alone, as its
# sole argument), and -h/--help is a human running this script directly to read usage.
# /amir-loop, by contrast, forwards a user-typed prompt verbatim as $ARGUMENTS - a prompt
# that happens to start with the word "-h" or "--cancel" must arm a loop with that text,
# not be swallowed as a flag. Restricting those two spellings to "this is the only
# argument" preserves every real caller while treating a multi-word prompt beginning
# with either word as what it is: text. --max-iterations and --completion-promise stay
# recognized anywhere in the argument list, since the command's own argument-hint
# documents them as usable alongside a prompt.
# ONE ARGUMENT, TOKENIZED HERE RATHER THAN BY THE SHELL (#21)
#
# `/amir-loop` used to interpolate `$ARGUMENTS` UNQUOTED into the command line, so the shell
# tokenized a user-typed prompt before this script ever saw it. Two consequences, measured:
#
#   `Work on findings #3639, #3641 --max-iterations 25`  ->  ARGC=3: "Work" "on" "findings"
#
# Everything from `#` was a comment. The prompt was truncated AND `--max-iterations 25` was
# silently discarded, so a requested cap of 25 became the default 1000 with no warning - a 40x
# widening of the loop's primary safety bound, invisible in the banner.
#
#   `Fix the $(echo INJECTED) bug`  ->  "Fix" "the" "INJECTED" "bug"
#
# The substitution RAN. A prompt is untrusted free text and must never reach a shell as code.
#
# The command now passes "$ARGUMENTS" quoted, so the shell performs no splitting at all and this
# script receives exactly one argument. We re-split it ourselves, honouring quotes and backslash
# escapes and NOTHING else: `#`, `$(...)`, backticks, `;`, `|` and `&` are ordinary characters in
# a sentence, and that is how they are treated.
#
# Multi-argument callers (direct CLI use, the test suite) are untouched: only the single-argument
# form is re-split, and splitting a lone word yields that word.
# `$2` = 1 means "quotes are ordinary characters". Silent on failure; the caller reports.
_tokenize() {
  local raw="$1" literal="${2:-0}" cur="" quote="" ch started=0 i n
  TOKENS=()
  n=${#raw}
  for ((i = 0; i < n; i++)); do
    ch="${raw:i:1}"
    if [ -n "$quote" ]; then
      if [ "$ch" = "$quote" ]; then quote=""; else cur+="$ch"; fi
      continue
    fi
    case "$ch" in
      "'"|'"')
        if [ "$literal" = "1" ]; then cur+="$ch"; else quote="$ch"; fi
        started=1 ;;
      '\')     i=$((i + 1)); [ "$i" -lt "$n" ] && { cur+="${raw:i:1}"; started=1; } ;;
      ' '|$'\t'|$'\n'|$'\r')
        if [ "$started" = "1" ]; then TOKENS+=("$cur"); cur=""; started=0; fi ;;
      *) cur+="$ch"; started=1 ;;
    esac
  done
  [ -n "$quote" ] && return 1
  [ "$started" = "1" ] && TOKENS+=("$cur")
  return 0
}

if [ $# -eq 1 ]; then
  if ! _tokenize "$1"; then
    # An apostrophe in prose - "fix the O'Brien bug", "don't retry" - is far more likely than a
    # quoting mistake. Refusing to start work over English punctuation would be a worse failure
    # than the one being fixed, so the text is taken as written. The only thing lost is grouping,
    # which matters solely to --completion-promise, and the fallback SAYS so: this widens what is
    # accepted, it never silently drops anything.
    echo "note: unbalanced quote treated as literal text; quote grouping is off for this run" >&2
    _tokenize "$1" 1
  fi
  set -- ${TOKENS+"${TOKENS[@]}"}
fi

ORIG_ARGC=$#

LITERAL=0
while [ $# -gt 0 ]; do
  if [ "$LITERAL" = "1" ]; then
    PARTS+=("$1"); shift; continue
  fi
  case "$1" in
    --) LITERAL=1; shift ;;
    --cancel)
      if [ "$ORIG_ARGC" -eq 1 ]; then CANCEL=1; shift; else PARTS+=("$1"); shift; fi ;;
    --max-iterations)
      case "${2:-}" in
        ''|*[!0-9]*) echo "error: --max-iterations needs a whole number, got '${2:-}'" >&2; exit 1 ;;
      esac
      MAX="$2"; shift 2 ;;
    --completion-promise)
      [ -n "${2:-}" ] || { echo "error: --completion-promise needs text (quote multi-word)" >&2; exit 1; }
      PROMISE="$2"; shift 2 ;;
    -h|--help)
      if [ "$ORIG_ARGC" -eq 1 ]; then
        sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0
      else
        PARTS+=("$1"); shift
      fi ;;
    *) PARTS+=("$1"); shift ;;
  esac
done

STATE=".claude/amir-loop.pending.local.md"
OFF=".claude/amir-loop-off"

mkdir -p .claude 2>/dev/null || { echo "error: cannot create .claude here" >&2; exit 1; }

# Same Workspace-bound/project standing orders the Stop hook appends, resolved the same way.
PRINCIPLES=""
DEPENDENCIES=""
RUNTIME_PROFILE=""
POLICY_BRIEF=""
_workspace_root="${AMIR_LOOP_WORKSPACE_ROOT:-${WORKSPACE_ROOT:-}}"
case "$_workspace_root" in
  [A-Za-z]:*) command -v cygpath >/dev/null 2>&1 && _workspace_root=$(cygpath -u "$_workspace_root") ;;
esac
if [ -n "$_workspace_root" ] && [ -f "$_workspace_root/workspace.yaml" ]; then
  if [ -f "$_workspace_root/.lumvaleos/amir-loop-principles.md" ]; then
    PRINCIPLES="$_workspace_root/.lumvaleos/amir-loop-principles.md"
  elif [ -f "$_workspace_root/.claude/amir-loop-principles.md" ]; then
    PRINCIPLES="$_workspace_root/.claude/amir-loop-principles.md"
  else
    POLICY_BRIEF="The selected LumvaleOS Workspace at $_workspace_root has no rendered Amir Loop policy. Do not inherit standing orders from an ancestor or another Workspace. Run LumvaleOS policy validation/rendering before governed fallback work."
  fi
  [ -f "$_workspace_root/.claude/amir-loop-dependencies.json" ] && DEPENDENCIES="$_workspace_root/.claude/amir-loop-dependencies.json"
  [ -f "$_workspace_root/.claude/amir-loop-runtime.json" ] && RUNTIME_PROFILE="$_workspace_root/.claude/amir-loop-runtime.json"
else
  _dir="$PWD"
  while [ -n "$_dir" ]; do
    if [ -z "$PRINCIPLES" ] && [ -f "$_dir/.claude/amir-loop-principles.md" ]; then
      PRINCIPLES="$_dir/.claude/amir-loop-principles.md"
    fi
    if [ -z "$DEPENDENCIES" ] && [ -f "$_dir/.claude/amir-loop-dependencies.json" ]; then
      DEPENDENCIES="$_dir/.claude/amir-loop-dependencies.json"
    fi
    if [ -z "$RUNTIME_PROFILE" ] && [ -f "$_dir/.claude/amir-loop-runtime.json" ]; then
      RUNTIME_PROFILE="$_dir/.claude/amir-loop-runtime.json"
    fi
    [ -f "$_dir/workspace.yaml" ] && break
    [ -n "$PRINCIPLES" ] && [ -n "$DEPENDENCIES" ] && [ -n "$RUNTIME_PROFILE" ] && break
    _parent=$(dirname "$_dir")
    [ "$_parent" = "$_dir" ] && break
    _dir="$_parent"
  done
fi

DEPENDENCY_BRIEF=""
JQ=""
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

RUNTIME_BRIEF=""
if [ -n "$RUNTIME_PROFILE" ]; then
  if [ -z "$JQ" ]; then
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
    fi
  fi
  if [ -n "$JQ" ] && "$JQ" -e '
    .version == 1 and (.provider | type == "string" and length > 0) and
    ((.required // true) | type == "boolean") and
    ((.region // "") | type == "string") and
    ((.model // "") | type == "string") and
    ((.credential_source // "host") | type == "string") and
    ((.preflight // "") | type == "string") and
    ((.repair // "") | type == "string") and
    (.provider != "bedrock" or
      ((.region | type == "string" and length > 0) and
       (.model | type == "string" and length > 0) and
       (.credential_source | type == "string" and length > 0)))
  ' "$RUNTIME_PROFILE" >/dev/null 2>&1; then
    PROFILE_PROVIDER=$("$JQ" -r '.provider' "$RUNTIME_PROFILE" 2>/dev/null || true)
    PROFILE_REQUIRED=$("$JQ" -r '.required // true' "$RUNTIME_PROFILE" 2>/dev/null || true)
    ACTIVE_PROVIDER="${AMIR_LOOP_PROVIDER:-}"
    if [ -z "$ACTIVE_PROVIDER" ] && [ "${CLAUDE_CODE_USE_BEDROCK:-0}" = "1" ]; then
      ACTIVE_PROVIDER="bedrock"
    fi
    [ -n "$ACTIVE_PROVIDER" ] || ACTIVE_PROVIDER="host"
    RUNTIME_BRIEF=$("$JQ" -r '
      ["## Inference runtime profile", "",
       "Before substantive work, verify the active host runtime matches this profile. Do not",
       "print, persist, or include credentials in evidence.", "",
       "- provider: " + .provider,
       "- required: " + ((.required // true) | tostring),
       "- region: " + (.region // "host-resolved"),
       "- model: " + (.model // "host-resolved"),
       "- credential source: " + (.credential_source // "host"),
       "- preflight: " + (.preflight // "confirm provider, model, region and credential availability without exposing secrets"),
       (if (.repair // "") == "" then empty else "- repair: " + .repair end), "",
       "For provider=bedrock, accept the AWS SDK default credential chain, workload identity,",
       "or a Bedrock bearer token; never require long-lived static keys. A required mismatch must",
       "pause with <amir-loop-blocked>runtime-provider</amir-loop-blocked>; it is not completion."] |
       join("\n")
    ' "$RUNTIME_PROFILE" 2>/dev/null) || RUNTIME_BRIEF=""
    RUNTIME_BRIEF="$RUNTIME_BRIEF
- observed provider activation: $ACTIVE_PROVIDER"
    if [ "$PROFILE_REQUIRED" = "true" ] && [ "$ACTIVE_PROVIDER" != "$PROFILE_PROVIDER" ]; then
      RUNTIME_BRIEF="$RUNTIME_BRIEF

The required provider profile does not match the host activation signal. Do not begin
substantive work. Repair the host and output
<amir-loop-blocked>runtime-provider</amir-loop-blocked>."
    fi
  else
    RUNTIME_BRIEF="## Inference runtime profile

The runtime profile at $RUNTIME_PROFILE is invalid. Do not begin substantive work. Version 1
requires provider and, for provider=bedrock, non-empty region, model, and credential_source.
Never put credentials in this file. Report the repair and output
<amir-loop-blocked>runtime-provider</amir-loop-blocked>."
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
  if [ -n "$POLICY_BRIEF" ]; then
    printf '\n\n## Workspace policy status\n\n%s\n' "$POLICY_BRIEF"
  fi
  if [ -n "$DEPENDENCY_BRIEF" ]; then
    printf '\n\n%s\n' "$DEPENDENCY_BRIEF"
  fi
  if [ -n "$RUNTIME_BRIEF" ]; then
    printf '\n\n%s\n' "$RUNTIME_BRIEF"
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

EOF
  # Domain-neutral fallback. Anything naming a specific dispatcher, backlog or tracker
  # belongs in the project's principles file, not in a portable plugin that arms itself
  # in every session - the same rule the principles block above states. A project that
  # has said nothing still needs a rule for what "fallback work" means, so supply one
  # that assumes no product, no board and no governance system.
  if [ ! -f "$PRINCIPLES" ]; then
    cat <<'GENERIC_EOF'
## Fallback work

Acting as a collective of principals and domain experts of relevant fields, implement all
pending and scoped work items and next steps autonomously. If any tasks are genuinely
blocked or require my input, interactively ask me for the necessary actions and provide
your recommended solutions to resolve them. If you don't really need me then always make
decisions acting as a collective of principals and experts of all relevant fields.

GENERIC_EOF
  fi
  cat <<EOF
## Context durability

After any context compaction or conversation summarisation, re-read this session-scoped file
before acting. Reconstruct the PRIMARY GOAL from the explicit prompt and verified repository or
tracker evidence. A summary's suggested next step is a hint, not new authority: ignore it when it
would switch to fallback backlog work while the primary goal still has actionable work.

If, and only if, the work above is genuinely finished and verified, output
<promise>$PROMISE</promise> to end the loop.

## Governed recursive improvement

Pursue self-correction, self-healing, reusable learning and capability growth when they
advance the primary goal. Use supported hooks and agent SDK surfaces to diagnose provider,
permission and integration failures; select only declared routing fallbacks and use only
authority the user or governing system already granted. Never treat a permission bottleneck
as permission to bypass authentication, authorization, entitlement, tenancy, cost, safety
or production gates. A change to the loop's own governance requires independent evidence
and the review tier declared by the governing architecture. Recovery is complete only after
the affected dependency and required evidence validate successfully.

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
