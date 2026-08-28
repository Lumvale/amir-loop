#!/bin/bash
# Amir Loop - read-only view of the current loop.
#
# Mirrors the principles-resolution climb in amir-loop-doctor.sh (and the hook)
# exactly: same loop, same order. Do not invent a variant here.
set -uo pipefail
S="$PWD/.claude/amir-loop.local.md"
if [ ! -f "$S" ]; then
  echo "state: idle"
else
  echo "state: armed"
  echo "iteration: $(grep -m1 '^iteration:' "$S" | tr -dc '0-9') of $(grep -m1 '^max_iterations:' "$S" | tr -dc '0-9')"
  echo "promise: $(grep -m1 '^completion_promise:' "$S" | sed 's/^completion_promise: *//; s/^"\(.*\)"$/\1/')"
  echo "started: $(grep -m1 '^started_at:' "$S" | sed 's/^started_at: *//; s/^"\(.*\)"$/\1/')"
fi
C="$PWD/.claude/.amir-loop-campaign"
if [ -f "$C" ]; then
  START=$(cat "$C" 2>/dev/null)
  case "$START" in ''|*[!0-9]*) echo "campaign: unreadable" ;;
    *) echo "campaign started: $(date -u -d "@$START" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$START")" ;;
  esac
fi
[ -f "$PWD/.claude/amir-loop-off" ] && echo "kill switch: present"
_dir="$PWD"
while [ -n "$_dir" ]; do
  [ -f "$_dir/.claude/amir-loop-principles.md" ] && { echo "principles: $_dir/.claude/amir-loop-principles.md"; break; }
  _p=$(dirname "$_dir"); [ "$_p" = "$_dir" ] && { echo "principles: none"; break; }; _dir="$_p"
done
exit 0
