#!/bin/bash
# Amir Loop - read-only view of the current loop.
#
# Mirrors the principles-resolution climb in amir-loop-doctor.sh (and the hook)
# exactly: same loop, same order. Do not invent a variant here.
#
# Also mirrors the hook's own frontmatter extraction and validation
# (plugins/amir-loop/hooks/amir-loop-stop.sh, around the ITER/LIMIT case
# statements) exactly. The hook deletes the state file and allows the stop
# the instant iteration or max_iterations fails the `''|*[!0-9]*` test; status
# must never call that same state "armed", and must never silently salvage a
# digits-only number out of a field that failed that test - a diagnostic that
# reports a healthy loop the hook has already discarded is worse than none.
set -uo pipefail
shopt -s nullglob
SESSION_STATES=("$PWD"/.claude/amir-loop.*.local.md)
S="$PWD/.claude/amir-loop.local.md"
if [ "${#SESSION_STATES[@]}" -gt 0 ]; then
  echo "state: armed"
  echo "sessions: ${#SESSION_STATES[@]}"
  for SESSION_STATE in "${SESSION_STATES[@]}"; do
    echo "session state: $SESSION_STATE"
  done
elif [ ! -f "$S" ]; then
  echo "state: idle"
else
  FM=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$S" 2>/dev/null)
  ITER=$(printf '%s' "$FM" | grep '^iteration:' | sed 's/iteration: *//' | tr -d '[:space:]')
  LIMIT=$(printf '%s' "$FM" | grep '^max_iterations:' | sed 's/max_iterations: *//' | tr -d '[:space:]')
  INVALID=0
  case "$ITER" in ''|*[!0-9]*) INVALID=1 ;; esac
  case "$LIMIT" in ''|*[!0-9]*) INVALID=1 ;; esac
  if [ "$INVALID" -eq 1 ]; then
    echo "state: invalid"
    echo "reason: iteration or max_iterations is not a number - the hook will discard this state file and allow the stop on the next turn"
  else
    GOAL=$(printf '%s' "$FM" | grep '^completion_promise:' | sed 's/^completion_promise: *//; s/^"\(.*\)"$/\1/')
    STARTED=$(printf '%s' "$FM" | grep '^started_at:' | sed 's/^started_at: *//; s/^"\(.*\)"$/\1/')
    echo "state: armed"
    echo "iteration: $ITER of $LIMIT"
    echo "promise: $GOAL"
    echo "started: $STARTED"
  fi
fi
C="$PWD/.claude/.amir-loop-campaign"
if [ -f "$C" ]; then
  START=$(cat "$C" 2>/dev/null)
  case "$START" in ''|*[!0-9]*) echo "campaign: unreadable" ;;
    *) echo "campaign started: $(date -u -d "@$START" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$START" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$START")" ;;
  esac
fi
[ -f "$PWD/.claude/amir-loop-off" ] && echo "kill switch: present"
_ws="${AMIR_LOOP_WORKSPACE_ROOT:-${WORKSPACE_ROOT:-}}"
case "$_ws" in [A-Za-z]:*) command -v cygpath >/dev/null 2>&1 && _ws=$(cygpath -u "$_ws") ;; esac
if [ -n "$_ws" ] && [ -f "$_ws/workspace.yaml" ]; then
  echo "workspace policy root: $_ws"
  if [ -f "$_ws/.lumvaleos/amir-loop-principles.md" ]; then
    echo "principles: $_ws/.lumvaleos/amir-loop-principles.md"
    grep -m1 'lumvaleos-agent-policy:' "$_ws/.lumvaleos/amir-loop-principles.md" 2>/dev/null || true
  elif [ -f "$_ws/.claude/amir-loop-principles.md" ]; then
    echo "principles: $_ws/.claude/amir-loop-principles.md"
  else
    echo "principles: missing for selected Workspace (run lumvaleos policy render)"
  fi
else
  _dir="$PWD"
  while [ -n "$_dir" ]; do
    [ -f "$_dir/.claude/amir-loop-principles.md" ] && { echo "principles: $_dir/.claude/amir-loop-principles.md"; break; }
    [ -f "$_dir/workspace.yaml" ] && { echo "principles: none at Workspace boundary $_dir"; break; }
    _p=$(dirname "$_dir"); [ "$_p" = "$_dir" ] && { echo "principles: none"; break; }; _dir="$_p"
  done
fi
exit 0
