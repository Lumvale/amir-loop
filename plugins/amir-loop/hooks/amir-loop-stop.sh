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

# --claude-code: the install shape for ~/.claude/settings.json. It means two things:
#   1. never auto-arm - Claude Code is where the scheduled routines run, and those are
#      deliberately bounded discrete passes;
#   2. stand down entirely in a VS Code session - `chat.useClaudeHooks` makes VS Code run
#      ~/.claude/settings.json hooks TOO, so without this both this hook and the `amir`
#      plugin's fire on the same stop and both increment the counter.
# Passed as a FLAG, never as `VAR=0 cmd`: that env-prefix form is bash-only, and VS Code
# runs hook commands through PowerShell, which reports it as
#   The term 'AMIR_LOOP_AUTOARM=0' is not recognized as the name of a cmdlet
CLAUDE_CODE_ONLY=0
for arg in "$@"; do
  [ "$arg" = "--claude-code" ] && CLAUDE_CODE_ONLY=1
done

HOOK_INPUT=$(cat)

# jq resolution: vendored static binary for this platform, then PATH, then fail open.
# A missing jq used to exit here silently, which presented as "the plugin is broken".
_vendor="$(cd "$(dirname "$0")/.." && pwd)/vendor/jq"
case "$(uname -s 2>/dev/null)" in
  Linux)   _cand="$_vendor/jq-linux-amd64" ;;
  Darwin)  case "$(uname -m 2>/dev/null)" in
             arm64) _cand="$_vendor/jq-macos-arm64" ;;
             *)     _cand="$_vendor/jq-macos-amd64" ;;
           esac ;;
  MINGW*|MSYS*|CYGWIN*) _cand="$_vendor/jq-windows-amd64.exe" ;;
  *) _cand="" ;;
esac
if [ -n "$_cand" ] && "$_cand" --version >/dev/null 2>&1; then
  JQ="$_cand"
elif command -v jq >/dev/null 2>&1; then
  JQ="jq"
else
  allow_stop
fi

[ "${AMIR_LOOP_OFF:-0}" = "1" ] && allow_stop

CWD=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD="$PWD"
if command -v cygpath >/dev/null 2>&1; then
  CWD=$(cygpath -u "$CWD" 2>/dev/null) || allow_stop
fi
[ -d "$CWD" ] || allow_stop
[ -f "$CWD/.claude/amir-loop-off" ] && allow_stop

SESSION=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.session_id // "nosession"' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.transcript_path // empty' 2>/dev/null)

# A VS Code session is identifiable from the payload itself - its transcripts live under
# GitHub.copilot-chat - so no environment sniffing is needed. In that host the `amir`
# plugin owns the Stop hook; this invocation stands down rather than double-firing.
if [ "$CLAUDE_CODE_ONLY" = "1" ]; then
  case "$TRANSCRIPT" in
    *copilot-chat*|*copilot_chat*) allow_stop ;;
  esac
fi
if [ -n "$TRANSCRIPT" ] && command -v cygpath >/dev/null 2>&1; then
  TRANSCRIPT=$(cygpath -u "$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT=""
fi

STATE="$CWD/.claude/amir-loop.local.md"
CAMPAIGN="$CWD/.claude/.amir-loop-campaign"
MARKER="$CWD/.claude/.amir-loop-done-$SESSION"
# Optional per-project standing orders, appended to every armed loop. Absent => the
# generic posture below is all the agent gets, which is the safe default for any project.
#
# Searched from $CWD UPWARDS, like .gitignore or .editorconfig. A session rooted in a
# sub-repo (C:\lumvale\lumvale-os) must still inherit the fleet's standing orders from
# C:\lumvale\.claude - without this it silently armed with the bare generic body, which
# is how two sub-repo loops ended up running with no backlog rules at all.
PRINCIPLES=""
_dir="$CWD"
while [ -n "$_dir" ]; do
  if [ -f "$_dir/.claude/amir-loop-principles.md" ]; then
    PRINCIPLES="$_dir/.claude/amir-loop-principles.md"
    break
  fi
  _parent=$(dirname "$_dir")
  [ "$_parent" = "$_dir" ] && break
  _dir="$_parent"
done

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

# How many turns the human has taken. Both transcript shapes; 0 if unreadable.
user_turns() {
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || { echo 0; return; }
  local n
  n=$("$JQ" -rs '[.[] | select(.type=="user.message" or .message.role=="user")] | length' "$TRANSCRIPT" 2>/dev/null)
  case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

# One completed loop per HUMAN REQUEST, not per session. The marker stops a finished loop
# re-arming on the very next stop; it must NOT silence the session forever, because a chat
# session outlives a loop and survives checkpoint restores - the symptom of getting that
# wrong is "it worked once, then never again".
#
# The marker records the human turn count at the moment the loop ended. If the human has
# spoken since, that is a new request and the loop is allowed to arm again.
if [ -f "$MARKER" ]; then
  MARKED_AT=$(cat "$MARKER" 2>/dev/null)
  case "$MARKED_AT" in ''|*[!0-9]*) MARKED_AT=999999 ;; esac
  if [ "$(user_turns)" -gt "$MARKED_AT" ] 2>/dev/null; then
    rm -f "$MARKER"
  else
    allow_stop
  fi
fi

MAX_ITER="${AMIR_LOOP_MAX:-1000}"
case "$MAX_ITER" in
  ''|*[!0-9]*|0) MAX_ITER=1000 ;;
esac
PROMISE="AMIR LOOP COMPLETE"

# --- arm ---------------------------------------------------------------------------
# AMIR_LOOP_AUTOARM=0 means "continue a loop someone started, never start one". That is
# the right setting for a host whose sessions are already bounded on purpose - Claude
# Code's scheduled routines are discrete passes, and auto-arming would turn each of them
# into a 1000-turn loop. There, the loop is opt-in per session via the command.
if [ ! -f "$STATE" ] && { [ "$CLAUDE_CODE_ONLY" = "1" ] || [ "${AMIR_LOOP_AUTOARM:-1}" = "0" ]; }; then
  allow_stop
fi

if [ ! -f "$STATE" ]; then
  mkdir -p "$CWD/.claude" 2>/dev/null || allow_stop
  {
    cat <<EOF
---
active: true
iteration: 1
max_iterations: $MAX_ITER
completion_promise: "$PROMISE"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

Continue the task you were working on in this session. Re-read what you have already
done, then take the next concrete step on it.

Work as a collective of principal engineers and domain experts. Decide autonomously
wherever a competent team would. Escalate only a genuine blocker, and when you do, say
what is blocked, why it needs a person, your recommended solution, the alternatives you
weighed, and what you will do if there is no reply.

Do not stall on a soft blocker. Mock it, stub it, containerise it, or work around it so
progress continues, and file follow-up work for anything you deliberately deferred.

Capture what you learn as you go, so the next session does not re-derive it.
EOF
    # Project-scoped standing orders, appended verbatim when present. This is where
    # anything sharp belongs - merge authority, which backlog to pull from, a mandate to
    # modernise - because it is opt-in per project and version-controlled, rather than
    # baked into a portable plugin that arms itself in every session.
    if [ -f "$PRINCIPLES" ]; then
      printf '\n'
      cat "$PRINCIPLES"
    fi
    cat <<EOF

If, and only if, there is nothing further you can advance, output
<promise>$PROMISE</promise> to end the loop.

The promise means the WORK IS EXHAUSTED, not that the task you happened to pick is done.
Finishing one item is not finishing. If you have just filed follow-up work, or named
anything as pending, blocked, deferred, or a next step, that is your own evidence there is
more to do - pick the next thing up and keep going instead of promising. Do not promise to
escape a hard step, and do not promise because you are unsure how to continue: say what is
blocking you and keep working.
EOF
  } > "$STATE" || allow_stop
fi

FM=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE" 2>/dev/null)
ITER=$(printf '%s' "$FM" | grep '^iteration:' | sed 's/iteration: *//' | tr -d '[:space:]')
LIMIT=$(printf '%s' "$FM" | grep '^max_iterations:' | sed 's/max_iterations: *//' | tr -d '[:space:]')
GOAL=$(printf '%s' "$FM" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')
case "$ITER" in ''|*[!0-9]*) rm -f "$STATE"; allow_stop ;; esac
case "$LIMIT" in ''|*[!0-9]*) rm -f "$STATE"; allow_stop ;; esac

# Stamp the marker with the human turn count at the moment the loop ended, so the next
# human message re-enables arming (see the marker check above).
finish() { rm -f "$STATE"; user_turns > "$MARKER" 2>/dev/null; exit 0; }

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
LAST=$("$JQ" -rs '[.[] | select(.type=="assistant.message") | .data.content // "" | select(length>0)] | last // empty' "$TRANSCRIPT" 2>/dev/null)
if [ -z "$LAST" ]; then
  LAST=$("$JQ" -rs '[.[] | select(.message.role=="assistant") | ([.message.content[]? | select(.type=="text") | .text] | join("\n")) | select(length>0)] | last // empty' "$TRANSCRIPT" 2>/dev/null)
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

# Feed the FULL brief once, then a short pointer. Re-injecting the whole standing orders on
# every iteration is both expensive and harmful: a ~8k-character block repeated each turn
# degraded a real run into empty responses ("[System: Empty message content sanitised to
# satisfy protocol]") after which the model faked the promise to escape. The brief is on
# disk and the agent can re-read it; it does not need to be re-sent.
if [ "$ITER" -gt 1 ]; then
  PROMPT_TEXT="Continue the loop - iteration $NEXT of $LIMIT.

Your standing orders for this run are in .claude/amir-loop.local.md. Re-read that file when
you need them.

Take the next concrete step on the work now. Do not reply with an empty message: if you have
nothing to say, perform the next action instead.

Output <promise>$GOAL</promise> only when the work is exhausted - never to escape a hard
step, and never straight after an empty or failed turn. If turns are failing, say what is
failing."
fi

# Emit BOTH shapes. Claude Code reads decision/reason at the TOP LEVEL; VS Code Copilot
# Chat reads them from a NESTED hookSpecificOutput and ignores the top-level pair:
#     let d = l.hookSpecificOutput;  d?.decision === "block" && d.reason && reasons.add(...)
# and then continues only when `shouldContinue && reasons.length`. Emitting only the
# top-level form is why the loop displayed its message but never actually continued a VS
# Code session - the log line to check is:
#     [ToolCallingLoop] Stop hook result: shouldContinue=false, reasons=undefined
"$JQ" -n --arg prompt "$PROMPT_TEXT" \
      --arg msg "Amir Loop iteration $NEXT/$LIMIT | to stop: output <promise>$GOAL</promise> (only when it is TRUE)" \
      '{
         decision: "block",
         reason: $prompt,
         systemMessage: $msg,
         hookSpecificOutput: {
           hookEventName: "Stop",
           decision: "block",
           reason: $prompt
         }
       }'
exit 0
