#!/bin/bash
# Atomic, fail-closed worktree ownership for campaign dispatchers and host hooks.
set -uo pipefail

usage() { echo "usage: $0 acquire|check|release WORKTREE SESSION_ID" >&2; exit 2; }
[ "$#" -eq 3 ] || usage
ACTION="$1" ROOT="$2"
SESSION=$(printf '%s' "$3" | tr -c 'A-Za-z0-9._-' '_')
[ -n "$SESSION" ] || usage
[ -d "$ROOT" ] || { echo "worktree does not exist: $ROOT" >&2; exit 2; }

CLAUDE_DIR="$ROOT/.claude"
CLAIM="$CLAUDE_DIR/.amir-loop-worktree-claim"
OWNER="$CLAIM/owner"
HEARTBEAT="$CLAIM/heartbeat"
NOW="${AMIR_LOOP_CLAIM_NOW:-$(date -u +%s)}"
STALE_AFTER="${AMIR_LOOP_CLAIM_STALE_SECONDS:-604800}"
case "$NOW:$STALE_AFTER" in *[!0-9:]*) echo "invalid claim clock configuration" >&2; exit 2 ;; esac

read_claim() {
  CLAIMED_SESSION=$(cat "$OWNER" 2>/dev/null || true)
  CLAIM_HEARTBEAT=$(cat "$HEARTBEAT" 2>/dev/null || true)
  case "$CLAIMED_SESSION" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$CLAIM_HEARTBEAT" in ''|*[!0-9]*) return 1 ;; esac
}

write_claim() {
  tmp_owner="$CLAIM/.owner.$$" tmp_heartbeat="$CLAIM/.heartbeat.$$"
  printf '%s\n' "$SESSION" > "$tmp_owner" &&
    printf '%s\n' "$NOW" > "$tmp_heartbeat" &&
    mv "$tmp_owner" "$OWNER" && mv "$tmp_heartbeat" "$HEARTBEAT"
}

collision() {
  echo "worktree claim collision: $ROOT is claimed by ${CLAIMED_SESSION:-unknown}; refusing session $SESSION" >&2
  exit 73
}

case "$ACTION" in
  acquire)
    mkdir -p "$CLAUDE_DIR" || exit 74
    if mkdir "$CLAIM" 2>/dev/null; then
      write_claim || { rm -f "$CLAIM"/.owner.$$ "$CLAIM"/.heartbeat.$$; rmdir "$CLAIM" 2>/dev/null; exit 74; }
      exit 0
    fi
    read_claim || collision
    if [ "$CLAIMED_SESSION" = "$SESSION" ]; then write_claim || exit 74; exit 0; fi
    age=$((NOW - CLAIM_HEARTBEAT))
    [ "$age" -ge 0 ] || collision
    [ "$age" -gt "$STALE_AFTER" ] || collision
    stale="${CLAIM}.stale.$$"
    mv "$CLAIM" "$stale" 2>/dev/null || collision
    if mkdir "$CLAIM" 2>/dev/null && write_claim; then rm -rf "$stale"; exit 0; fi
    [ -d "$CLAIM" ] || mv "$stale" "$CLAIM" 2>/dev/null || true
    collision
    ;;
  check)
    [ -d "$CLAIM" ] || exit 1
    read_claim || collision
    [ "$CLAIMED_SESSION" = "$SESSION" ] || collision
    ;;
  release)
    [ -d "$CLAIM" ] || exit 0
    read_claim || collision
    [ "$CLAIMED_SESSION" = "$SESSION" ] || collision
    released="${CLAIM}.released.$$"
    mv "$CLAIM" "$released" 2>/dev/null || collision
    rm -rf "$released"
    ;;
  *) usage ;;
esac
