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

while [ $# -gt 0 ]; do
  case "$1" in
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

STATE=".claude/amir-loop.local.md"
OFF=".claude/amir-loop-off"
PRINCIPLES=".claude/amir-loop-principles.md"

mkdir -p .claude 2>/dev/null || { echo "error: cannot create .claude here" >&2; exit 1; }

if [ "$CANCEL" = "1" ]; then
  rm -f "$STATE"
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
  cat <<EOF

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
