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

JSON=0
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

shopt -s nullglob
SESSION_STATES=("$PWD"/.claude/amir-loop.*.local.md)
S="$PWD/.claude/amir-loop.local.md"
CLAIM_DIR="$PWD/.claude/.amir-loop-worktree-claim"
CLAIM_STALE_AFTER="${AMIR_LOOP_CLAIM_STALE_SECONDS:-604800}"
CLAIM_NOW="${AMIR_LOOP_CLAIM_NOW:-$(date -u +%s)}"

read_claim() {
  CLAIM_OWNER="" CLAIM_HEARTBEAT="" CLAIM_AGE="" CLAIM_STATE="unclaimed"
  [ -d "$CLAIM_DIR" ] || return 0
  CLAIM_OWNER=$(cat "$CLAIM_DIR/owner" 2>/dev/null || true)
  CLAIM_HEARTBEAT=$(cat "$CLAIM_DIR/heartbeat" 2>/dev/null || true)
  case "$CLAIM_OWNER" in ''|*[!A-Za-z0-9._-]*) CLAIM_STATE=invalid; return 0 ;; esac
  case "$CLAIM_HEARTBEAT:$CLAIM_NOW:$CLAIM_STALE_AFTER" in *[!0-9:]*) CLAIM_STATE=invalid; return 0 ;; esac
  CLAIM_AGE=$((CLAIM_NOW - CLAIM_HEARTBEAT))
  [ "$CLAIM_AGE" -ge 0 ] || { CLAIM_STATE=invalid; return 0; }
  if [ "$CLAIM_AGE" -gt "$CLAIM_STALE_AFTER" ]; then CLAIM_STATE=stale; else CLAIM_STATE=live; fi
}
read_claim

# Machine consumers get a stable contract instead of parsing the human display and then opening
# every state file themselves. Keep this branch separate from the text path below: --json is
# additive, and the established text output remains byte-compatible for people and the extension.
if [ "$JSON" -eq 1 ]; then
  _vendor="$(cd "$(dirname "$0")/.." && pwd)/vendor/jq"
  case "$(uname -s 2>/dev/null)" in
    Linux) _cand="$_vendor/jq-linux-amd64" ;;
    Darwin) case "$(uname -m 2>/dev/null)" in
      arm64) _cand="$_vendor/jq-macos-arm64" ;;
      *) _cand="$_vendor/jq-macos-amd64" ;;
    esac ;;
    MINGW*|MSYS*|CYGWIN*) _cand="$_vendor/jq-windows-amd64.exe" ;;
    *) _cand="" ;;
  esac
  if [ -n "$_cand" ] && "$_cand" --version >/dev/null 2>&1; then
    JQ="$_cand"
  elif command -v jq >/dev/null 2>&1; then
    JQ=jq
  else
    printf '%s\n' '{"schema_version":1,"state":"unavailable","sessions":[],"error":"jq is unavailable"}'
    exit 0
  fi

  # Bash 3 (the macOS runner's system Bash) treats an empty array expansion as unbound under
  # `set -u`. Test the optional first element instead, and return before expanding an empty array.
  if [ -z "${SESSION_STATES[0]-}" ]; then
    if [ -f "$S" ]; then
      SESSION_STATES=("$S")
    else
      "$JQ" -nc --arg claim_state "$CLAIM_STATE" --arg owner "$CLAIM_OWNER" \
        --arg heartbeat "$CLAIM_HEARTBEAT" --arg age "$CLAIM_AGE" --arg threshold "$CLAIM_STALE_AFTER" \
        '{schema_version:1,state:"idle",session_count:0,sessions:[],worktree_claim:{state:$claim_state,owner:(if $owner=="" then null else $owner end),heartbeat_epoch:(if $heartbeat=="" then null else ($heartbeat|tonumber? // null) end),age_seconds:(if $age=="" then null else ($age|tonumber? // null) end),stale_after_seconds:($threshold|tonumber? // null)}}'
      exit 0
    fi
  fi

  sessions='[]'
  for SESSION_STATE in "${SESSION_STATES[@]}"; do
    FM=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$SESSION_STATE" 2>/dev/null)
    ITER=$(printf '%s' "$FM" | grep '^iteration:' | sed 's/iteration: *//' | tr -d '[:space:]')
    LIMIT=$(printf '%s' "$FM" | grep '^max_iterations:' | sed 's/max_iterations: *//' | tr -d '[:space:]')
    GOAL=$(printf '%s' "$FM" | grep '^completion_promise:' | sed 's/^completion_promise: *//; s/^"\(.*\)"$/\1/')
    STARTED=$(printf '%s' "$FM" | grep '^started_at:' | sed 's/^started_at: *//; s/^"\(.*\)"$/\1/')
    INVALID=0
    case "$ITER" in ''|*[!0-9]*) INVALID=1 ;; esac
    case "$LIMIT" in ''|*[!0-9]*) INVALID=1 ;; esac
    if [ "$INVALID" -eq 1 ]; then
      item=$("$JQ" -nc --arg path "$SESSION_STATE" --arg promise "$GOAL" --arg started "$STARTED" \
        '{path:$path,state:"invalid",iteration:null,max_iterations:null,completion_promise:$promise,started_at:$started}')
    else
      item=$("$JQ" -nc --arg path "$SESSION_STATE" --argjson iteration "$ITER" \
        --argjson max_iterations "$LIMIT" --arg promise "$GOAL" --arg started "$STARTED" \
        '{path:$path,state:"armed",iteration:$iteration,max_iterations:$max_iterations,completion_promise:$promise,started_at:$started}')
    fi
    sessions=$("$JQ" -nc --argjson sessions "$sessions" --argjson item "$item" '$sessions + [$item]')
  done

  if [ "$(printf '%s' "$sessions" | "$JQ" 'length')" -eq 0 ]; then
    aggregate=idle
  elif printf '%s' "$sessions" | "$JQ" -e 'any(.[]; .state == "invalid")' >/dev/null; then
    aggregate=invalid
  else
    aggregate=armed
  fi
  "$JQ" -nc --arg state "$aggregate" --argjson sessions "$sessions" \
    --arg claim_state "$CLAIM_STATE" --arg owner "$CLAIM_OWNER" --arg heartbeat "$CLAIM_HEARTBEAT" \
    --arg age "$CLAIM_AGE" --arg threshold "$CLAIM_STALE_AFTER" \
    '{schema_version:1,state:$state,session_count:($sessions|length),sessions:$sessions,worktree_claim:{state:$claim_state,owner:(if $owner=="" then null else $owner end),heartbeat_epoch:(if $heartbeat=="" then null else ($heartbeat|tonumber? // null) end),age_seconds:(if $age=="" then null else ($age|tonumber? // null) end),stale_after_seconds:($threshold|tonumber? // null)}}'
  exit 0
fi

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
case "$CLAIM_STATE" in
  unclaimed) echo "worktree claim: unclaimed" ;;
  live|stale) echo "worktree claim: $CLAIM_STATE owner=$CLAIM_OWNER age=${CLAIM_AGE}s stale-after=${CLAIM_STALE_AFTER}s" ;;
  invalid) echo "worktree claim: invalid (collision protection fails closed)" ;;
esac
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
