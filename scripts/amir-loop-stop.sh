#!/bin/bash
# Amir Loop - a self-contained auto-arming Stop hook.
#
# Creates .claude/amir-loop.local.md on the first Stop of a session so the loop arms
# itself, then decides whether to block the stop and feed the prompt back.
#
# LINEAGE. The state-file shape and the {"decision":"block","reason":...} protocol come
# from Anthropic's ralph-wiggum plugin; the implementation is ours and shares no code.
# It stopped delegating because that plugin greps the transcript for '"role":"assistant"',
# which is Claude Code's format. VS Code Copilot Chat writes a DIFFERENT shape:
#     {"type":"assistant.message","data":{"content":"..."},"id":...,"timestamp":...}
# so the grep found nothing, the plugin took its "no assistant messages" branch, deleted
# the state file and allowed the stop - on the very first arm, every time.
#
# This file is deliberately independent: it works in both hosts, and it cannot be broken
# by a marketplace plugin being updated or withdrawn. It does NOT interoperate with
# /ralph-loop, which writes a differently-named state file this hook ignores.
#
# BOUNDS - two, whichever trips first. Neither replaces the other:
#   AMIR_LOOP_MAX     per-session turn cap (default 1000). 0/junk clamped to the default,
#                     because 0 would mean "never stop".
#   AMIR_LOOP_DAYS    calendar window from the first arm (default 5), recorded in
#                     .claude/.amir-loop-campaign. 0 = no deadline. Junk => dormant.
#   AMIR_LOOP_UNTIL   absolute date override. Unparseable => treated as expired.
# KILL SWITCHES: AMIR_LOOP_OFF=1, or a .claude/amir-loop-off file.
#
# Unexpected conditions ALLOW THE STOP. Failing closed would mean a session that can
# never end.

set -uo pipefail

allow_stop() { exit 0; }

HOOK_INPUT=$(cat)
command -v jq >/dev/null 2>&1 || allow_stop
[ "${AMIR_LOOP_OFF:-0}" = "1" ] && allow_stop

CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"
if command -v cygpath >/dev/null 2>&1; then
  CWD=$(cygpath -u "$CWD" 2>/dev/null) || allow_stop
fi
[ -d "$CWD" ] || allow_stop
[ -f "$CWD/.claude/amir-loop-off" ] && allow_stop

SESSION=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // "nosession"' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -n "$TRANSCRIPT" ] && command -v cygpath >/dev/null 2>&1; then
  TRANSCRIPT=$(cygpath -u "$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT=""
fi

STATE="$CWD/.claude/amir-loop.local.md"
CAMPAIGN="$CWD/.claude/.amir-loop-campaign"
MARKER="$CWD/.claude/.amir-loop-done-$SESSION"

# --- calendar window ---------------------------------------------------------------
DEADLINE=""
if [ -n "${AMIR_LOOP_UNTIL:-}" ]; then
  WHEN="$AMIR_LOOP_UNTIL"
  case "$WHEN" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) WHEN="$WHEN 23:59:59" ;;
  esac
  DEADLINE=$(date -d "$WHEN" +%s 2>/dev/null) || DEADLINE="invalid"
  [ -n "$DEADLINE" ] || DEADLINE="invalid"
else
  DAYS="${AMIR_LOOP_DAYS:-5}"
  case "$DAYS" in
    0) DEADLINE="" ;;
    ''|*[!0-9]*) DEADLINE="invalid" ;;
    *)
      mkdir -p "$CWD/.claude" 2>/dev/null || allow_stop
      [ -f "$CAMPAIGN" ] || date -u +%s > "$CAMPAIGN" 2>/dev/null || allow_stop
      START=$(cat "$CAMPAIGN" 2>/dev/null)
      case "$START" in
        ''|*[!0-9]*) DEADLINE="invalid" ;;
        *) DEADLINE=$(( START + DAYS * 86400 )) ;;
      esac
      ;;
  esac
fi
[ "$DEADLINE" = "invalid" ] && allow_stop
if [ -n "$DEADLINE" ]; then
  [ "$(date -u +%s)" -ge "$DEADLINE" ] && allow_stop
fi

# One completed loop per session. Only ever set after a LEGITIMATE end (promise or max
# iterations) - never after a parse failure, or one bad turn disarms the whole session.
[ -f "$MARKER" ] && allow_stop

MAX_ITER="${AMIR_LOOP_MAX:-1000}"
case "$MAX_ITER" in
  ''|*[!0-9]*|0) MAX_ITER=1000 ;;
esac
PROMISE="AMIR LOOP COMPLETE"

# --- arm ---------------------------------------------------------------------------
if [ ! -f "$STATE" ]; then
  mkdir -p "$CWD/.claude" 2>/dev/null || allow_stop
  cat > "$STATE" <<EOF || allow_stop
---
active: true
iteration: 1
max_iterations: $MAX_ITER
completion_promise: "$PROMISE"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

Continue the task you were working on in this session. Re-read what you have already
done, then take the next concrete step on it.

If, and only if, the work is genuinely finished and you have verified it, output
<promise>$PROMISE</promise> to end the loop. Do not output that to escape a hard step,
and do not output it because you are unsure how to continue - say what is blocking you
and keep working instead.
EOF
fi

FM=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE" 2>/dev/null)
ITER=$(printf '%s' "$FM" | grep '^iteration:' | sed 's/iteration: *//' | tr -d '[:space:]')
LIMIT=$(printf '%s' "$FM" | grep '^max_iterations:' | sed 's/max_iterations: *//' | tr -d '[:space:]')
GOAL=$(printf '%s' "$FM" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')
case "$ITER" in ''|*[!0-9]*) rm -f "$STATE"; allow_stop ;; esac
case "$LIMIT" in ''|*[!0-9]*) rm -f "$STATE"; allow_stop ;; esac

finish() { rm -f "$STATE"; : > "$MARKER" 2>/dev/null; exit 0; }

# Turn cap reached -> a legitimate end.
[ "$LIMIT" -gt 0 ] && [ "$ITER" -ge "$LIMIT" ] && finish

# --- completion promise ------------------------------------------------------------
# If the transcript cannot be read we allow the stop WITHOUT the marker, so the next turn
# can arm again - an unreadable transcript is not a finished task.
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || allow_stop

# Slurp and take the last NON-EMPTY message. Two traps, both of which read as "unreadable":
#   1. message text is MULTI-LINE, so a per-line `tail -1` returns the last LINE, not the
#      last message;
#   2. the final assistant.message is routinely a tool-only turn with content "", so a
#      plain `last` is empty.
LAST=$(jq -rs '[.[] | select(.type=="assistant.message") | .data.content // "" | select(length>0)] | last // empty' "$TRANSCRIPT" 2>/dev/null)
if [ -z "$LAST" ]; then
  LAST=$(jq -rs '[.[] | select(.message.role=="assistant") | ([.message.content[]? | select(.type=="text") | .text] | join("\n")) | select(length>0)] | last // empty' "$TRANSCRIPT" 2>/dev/null)
fi
[ -n "$LAST" ] || allow_stop

if [ -n "$GOAL" ] && [ "$GOAL" != "null" ]; then
  case "$LAST" in
    *"<promise>$GOAL</promise>"*) finish ;;
  esac
fi

# --- continue ----------------------------------------------------------------------
NEXT=$(( ITER + 1 ))
TMP="$STATE.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT/" "$STATE" > "$TMP" 2>/dev/null && mv "$TMP" "$STATE" 2>/dev/null || {
  rm -f "$TMP"; allow_stop
}

PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$STATE")
[ -n "$PROMPT_TEXT" ] || allow_stop

jq -n --arg prompt "$PROMPT_TEXT" \
      --arg msg "Amir Loop iteration $NEXT/$LIMIT | to stop: output <promise>$GOAL</promise> (only when it is TRUE)" \
      '{decision: "block", reason: $prompt, systemMessage: $msg}'
exit 0
