#!/bin/bash
# Amir Loop - a self-contained auto-arming Stop hook.
#
# Creates a session-scoped .claude/amir-loop.<session>.local.md on the first Stop so
# concurrent chats rooted in the same project cannot inherit or overwrite each other's
# goals, then decides whether to block the stop and feed the prompt back.
#
# LINEAGE. The state-file shape and the {"decision":"block","reason":...} protocol come
# from Anthropic's ralph-wiggum plugin; the implementation is ours and shares no code.
# It stopped delegating because that plugin greps the transcript for '"role":"assistant"',
# which is Claude Code's format. VS Code Copilot Chat writes a DIFFERENT shape:
#     {"type":"assistant.message","data":{"content":"..."},"id":...,"timestamp":...}
# so the grep found nothing, the plugin took its "no assistant messages" branch, deleted
# the state file and allowed the stop - on the very first arm, every time.
#
# Codex supplies the same cwd/session/transcript fields plus last_assistant_message and
# turn_id. Prefer those stable fields there: Codex explicitly does not promise that its
# transcript JSON format is stable. The top-level decision/reason output below is also
# Codex's native Stop-continuation shape.
#
# This file is deliberately independent: it works behind every host adapter, and it cannot be broken
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
# TRANSIENT RETRIES: AMIR_LOOP_RETRY_MAX (default 3) retries a provider/network
# failure without consuming a loop iteration. Once exhausted, the hook fails open so
# the host can surface the error to the user instead of retrying forever.
#
# Unexpected conditions ALLOW THE STOP. Failing closed would mean a session that can
# never end.

set -uo pipefail

# The Stop hook must never turn an internal shell error into a host error. The
# launcher also fails open, but this covers direct Bash execution on Codex/Linux
# and protects against future paths that return non-zero unexpectedly.
trap 'exit 0' ERR

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
OBSERVE_EVENT=""
for arg in "$@"; do
  [ "$arg" = "--claude-code" ] && CLAUDE_CODE_ONLY=1
  case "$arg" in --observe=*) OBSERVE_EVENT="${arg#--observe=}" ;; esac
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

# Test-only escape hatch: report which jq this invocation resolved to, then exit.
# Never set in normal operation - it exists so tests/parity.bats can assert the hook
# and amir-loop-doctor.sh agree on jq resolution without reimplementing the platform
# mapping a third time. Placed after resolution (so it reports the real answer) but
# before every other side effect, so it cannot perturb the fail-open invariant or the
# hook's normal exit-0/no-output-or-one-JSON-object contract.
if [ "${AMIR_LOOP_JQ_DEBUG:-0}" = "1" ]; then
  printf '%s\n' "$JQ"
  exit 0
fi

[ "${AMIR_LOOP_OFF:-0}" = "1" ] && allow_stop

CWD=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.cwd // empty' 2>/dev/null)
# No cwd in the payload used to fall back to `$PWD`, which is not a safe guess: the hook then
# ARMS A LOOP in whatever directory the hook process happened to be in. Measured 2026-09-03 on
# Windows, once the launcher fix in #24 made these hooks execute at all - an empty payload
# scattered `.claude/.amir-loop-campaign`, `amir-loop.nosession.local.md` and nested `.claude`
# and `.lumvaleos` directories into three unrelated git worktrees, simply because a shell had
# cd'd there. A loop armed against the wrong workspace also reads the wrong backlog.
#
# A hook that cannot tell which workspace it is in must not choose one. Standing down is the
# fail-open direction this file already takes everywhere else: the stop is allowed, and the
# next turn with a readable payload arms normally.
[ -n "$CWD" ] || allow_stop
if command -v cygpath >/dev/null 2>&1; then
  CWD=$(cygpath -u "$CWD" 2>/dev/null) || allow_stop
fi
[ -d "$CWD" ] || allow_stop
[ -f "$CWD/.claude/amir-loop-off" ] && allow_stop

SESSION=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.session_id // "nosession"' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.transcript_path // empty' 2>/dev/null)
TURN_ID=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.turn_id // empty' 2>/dev/null)
LAST_ASSISTANT=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.last_assistant_message // empty' 2>/dev/null)

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

SESSION_KEY=$(printf '%s' "$SESSION" | tr -c 'A-Za-z0-9._-' '_')
[ -n "$SESSION_KEY" ] || SESSION_KEY="nosession"
STATE_NAME="amir-loop.$SESSION_KEY.local.md"
STATE="$CWD/.claude/$STATE_NAME"
PENDING_STATE="$CWD/.claude/amir-loop.pending.local.md"
CAMPAIGN="$CWD/.claude/.amir-loop-campaign"
MARKER="$CWD/.claude/.amir-loop-done-$SESSION"
RETRY_FILE="$CWD/.claude/.amir-loop-retry-$SESSION"
CLOSEOUT_FILE="$CWD/.claude/.amir-loop-closeout-$SESSION_KEY.json"
EXACT_OUTPUT_FILE="$CWD/.claude/.amir-loop-exact-output-$SESSION_KEY"

# The loop drops SEVEN files into `$CWD/.claude/`, in whatever repository it was run from.
# None is repository content, and every one of them shows in `git status` until somebody adds an
# ignore rule by hand — per repo, forever, one artefact at a time as each is discovered.
#
# Measured 2026-09-03 in `lumvale-os`: rules existed for `.amir-loop-campaign` and
# `amir-loop.*.local.md` (the latter added only AFTER one was committed to `main` by a
# `git add -A` that had no way to know it was scratch), and FOUR were uncovered —
# `-done-`, `-retry-`, `-closeout-`, `-exact-output-`. Two stray `-done-` markers made
# `git_provenance` report `dirty: True` on `lumvale-os-live`, the checkout the LumvaleOS MCP
# server SERVES, so that engine's staleness disclosure fired on every CLI invocation and every
# empty MCP answer — permanently, over ten bytes of loop scratch. A warning that is always on is
# one nobody reads, which is the failure that disclosure exists to prevent.
#
# So the loop now ignores its own litter, in the directory it already owns and already writes to.
# A `.claude/.gitignore` needs no path migration, invents no state-directory convention for a
# PORTABLE plugin, and fixes every consumer repository — including the ones nobody has thought
# about — instead of waiting for each to be discovered.
#
# It lists itself, so the fix does not become the next stray file.
#
# Merge, never clobber: a project may already keep a `.claude/.gitignore`, and replacing it would
# silently drop rules that are not ours. Only the lines below are the loop's to own, and each is
# appended only when absent. Best-effort throughout — an unwritable or unreadable file costs the
# tidiness, never the Stop hook, which must not fail a session over housekeeping.
#
# Takes the directory, then its rules. TWO directories need this, not one: the hook's own
# `mkdir -p "$CWD/.claude" "$CWD/.lumvaleos"` creates both, and `.lumvaleos/` receives
# `playbook-events.jsonl` (an outbox) and `.playbook-heartbeat`. That second directory was found
# the way the first four artefacts were — `git add -A` in this very change swept
# `.lumvaleos/playbook-events.jsonl` into the commit that was fixing the problem, and it had to be
# taken back out. The list of places the loop litters is longer than anyone remembers, which is
# the argument for prefix rules maintained by the loop rather than by hand.
amir_loop_self_ignore() {
  _ai_dir="$1"
  shift
  [ -d "$_ai_dir" ] || return 0
  _ai_file="$_ai_dir/.gitignore"
  for _ai_rule in '/.gitignore' "$@"; do
    if [ -f "$_ai_file" ]; then
      grep -qxF "$_ai_rule" "$_ai_file" 2>/dev/null && continue
    fi
    # The redirection is inside a group whose stderr is already discarded. `printf ... >> "$f"
    # 2>/dev/null` is NOT equivalent: redirections are applied left to right, so a failure to OPEN
    # the target is reported before `2>/dev/null` takes effect. Caught by this change's own test —
    # with the path made a directory, bash printed `Is a directory` and, because a Stop hook's
    # caller parses stdout+stderr as one stream, that line prepended itself to the JSON and broke
    # the parse. Housekeeping must never be able to corrupt the hook's contract.
    { printf '%s\n' "$_ai_rule" >> "$_ai_file"; } 2>/dev/null || return 0
  done
  return 0
}

# Non-Stop lifecycle events use the same portable launcher. They are deliberately
# best-effort: an emission failure can lose a hint, but may never corrupt or complete a
# direct goal. LumvaleOS deduplicates these workspace-scoped facts when it reconciles the
# outbox. Payloads contain identifiers and classifications only, never prompt/tool bodies.
if [ -n "$OBSERVE_EVENT" ]; then
  mkdir -p "$CWD/.claude" "$CWD/.lumvaleos" 2>/dev/null || exit 0
  amir_loop_self_ignore "$CWD/.claude" '/.amir-loop-*' '/amir-loop.*.local.md'
  amir_loop_self_ignore "$CWD/.lumvaleos" '/playbook-events.jsonl' '/.playbook-heartbeat'
  if [ "$OBSERVE_EVENT" = "user-prompt" ]; then
    prompt=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.prompt // empty' 2>/dev/null)
    if [ -z "$prompt" ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
      prompt=$("$JQ" -rs '
        [ .[] |
          if .type == "user.message" then (.data.content // "")
          elif .message.role == "user" then
            (if (.message.content | type) == "array" then
               [.message.content[]? | select(.type == "text") | .text] | join("\n")
             else (.message.content // "") end)
          elif (.userMessage? | type) == "string" then .userMessage
          else empty end |
          select(type == "string" and length > 0)
        ] | last // empty
      ' "$TRANSCRIPT" 2>/dev/null || true)
    fi
    if printf '%s' "$prompt" | grep -Eiq '(^|[[:space:]])(reply|respond|output|return)[[:space:]]+with[[:space:]]+exactly([[:space:]:]|$)'; then
      printf '%s\n' "${TURN_ID:-legacy}" > "$EXACT_OUTPUT_FILE" 2>/dev/null || true
    else
      rm -f "$EXACT_OUTPUT_FILE" 2>/dev/null || true
    fi
    exit 0
  fi

  event_type="$OBSERVE_EVENT"
  tool_name=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.tool_name // empty' 2>/dev/null)
  if [ "$OBSERVE_EVENT" = "post-tool" ]; then
    case "$tool_name" in
      apply_patch|Edit|Write) event_type="source.changed" ;;
      mcp__lumvaleos__lumvaleos_preflight)
        preflight_ok=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '
          [.. | objects | (.overall_status? // .status? // empty)] |
          map(select(. == "ok" or . == "healthy")) | length' 2>/dev/null)
        [ "${preflight_ok:-0}" -gt 0 ] || exit 0
        event_type="environment.reachable"
        ;;
      mcp__lumvaleos__knowledge_capture)
        capture_error=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '[.. | objects | .isError? // empty] | any' 2>/dev/null)
        [ "$capture_error" = "true" ] && exit 0
        event_type="learning.discovered"
        ;;
      Bash)
        command_text=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)
        exit_code=$(printf '%s' "$HOOK_INPUT" | "$JQ" -r '[.. | objects | .exit_code? // empty] | first // 0' 2>/dev/null)
        case "$exit_code" in ''|*[!0-9-]*) exit_code=0 ;; esac
        if [ "$exit_code" -ne 0 ] && printf '%s' "$command_text" | grep -Eiq '(^|[[:space:]])(pytest|bats|npm test|pnpm test|yarn test|terraform validate|cargo test|go test|dotnet test)([[:space:]]|$)'; then
          event_type="test.failed"
        else
          exit 0
        fi
        ;;
      *) exit 0 ;;
    esac
  fi
  occurred_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  workspace_id=$(printf '%s' "$CWD" | sha256sum 2>/dev/null | cut -c1-32)
  [ -n "$workspace_id" ] || workspace_id="$CWD"
  event_id=$(printf '%s|%s|%s|%s' "$workspace_id" "$event_type" "${TURN_ID:-$SESSION_KEY}" "$tool_name" |
    sha256sum 2>/dev/null | cut -c1-40)
  [ -n "$event_id" ] || event_id="${SESSION_KEY}-${event_type}-${TURN_ID:-legacy}"
  "$JQ" -nc --arg id "$event_id" --arg type "$event_type" --arg at "$occurred_at" \
    --arg workspace "$workspace_id" --arg session "$SESSION_KEY" --arg host "${AMIR_LOOP_HOST:-unknown}" \
    '{specversion:"1.0", id:$id, type:$type, source:"amir-loop.host-hook", time:$at,
      workspace_id:$workspace, subject:$session, data:{host:$host}}' \
    >> "$CWD/.lumvaleos/playbook-events.jsonl" 2>/dev/null || true
  if [ "$event_type" = "session.started" ]; then
    heartbeat_file="$CWD/.lumvaleos/.playbook-heartbeat"
    now_epoch=$(date -u +%s)
    last_epoch=$(cat "$heartbeat_file" 2>/dev/null || true)
    case "$last_epoch" in ''|*[!0-9]*) last_epoch=0 ;; esac
    if [ $((now_epoch - last_epoch)) -ge "${AMIR_LOOP_HEARTBEAT_SECONDS:-21600}" ]; then
      printf '%s\n' "$now_epoch" > "$heartbeat_file" 2>/dev/null || true
      hb_id=$(printf '%s|heartbeat|%s' "$workspace_id" "$((now_epoch / 21600))" | sha256sum | cut -c1-40)
      "$JQ" -nc --arg id "$hb_id" --arg at "$occurred_at" --arg workspace "$workspace_id" \
        '{specversion:"1.0", id:$id, type:"heartbeat.reconcile", source:"amir-loop.host-hook",
          time:$at, workspace_id:$workspace, subject:"startup-sparse-heartbeat", data:{}}' \
        >> "$CWD/.lumvaleos/playbook-events.jsonl" 2>/dev/null || true
    fi
  fi
  exit 0
fi

# A manually started loop cannot know the host session id. The setup command writes one
# pending state file; the next Stop in that chat atomically claims it. Auto-armed loops
# never consult the old project-global amir-loop.local.md, because doing so allowed an
# unrelated chat in the same workspace to take over the current direct request.
if [ ! -f "$STATE" ] && [ -f "$PENDING_STATE" ]; then
  mv "$PENDING_STATE" "$STATE" 2>/dev/null || allow_stop
fi
# Optional per-project or Workspace-bound standing orders. A selected LumvaleOS Workspace
# wins over filesystem ancestry so one Workspace can never inherit another's policy merely
# because their Source Folders share a parent directory.
#
# Searched from $CWD UPWARDS, like .gitignore or .editorconfig. A session rooted in a
# sub-repo (C:\lumvale\lumvale-os) must still inherit the fleet's standing orders from
# C:\lumvale\.claude - without this it silently armed with the bare generic body, which
# is how two sub-repo loops ended up running with no backlog rules at all.
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
  _dir="$CWD"
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

# Dependencies are a portable project policy, not a hard-coded vendor integration. The
# hook validates and renders the contract into the loop brief; the agent performs the
# actual capability probe because only the host knows which MCP/tools are live.
DEPENDENCY_BRIEF=""
if [ -n "$DEPENDENCIES" ]; then
  if "$JQ" -e '
    .version == 1 and (.dependencies | type == "array") and
    all(.dependencies[];
      (.id | type == "string" and length > 0) and
      (.policy == "required" or .policy == "preferred" or .policy == "off") and
      ((.kind // "tool") | type == "string") and
      ((.preflight // "") | type == "string") and
      ((.repair // "") | type == "string"))
  ' "$DEPENDENCIES" >/dev/null 2>&1; then
    DEPENDENCY_BRIEF=$("$JQ" -r '
      ["## Runtime dependency policy",
       "",
       "Before substantive work, preflight each dependency below once for this run. Do not",
       "claim a dependency was used unless its tool call succeeded in this session.",
       "",
       (.dependencies[] | select(.policy != "off") |
         "- " + .id + " (" + (.kind // "tool") + ", " + .policy + "): " +
         (.preflight // "probe that the capability is callable") +
         (if (.repair // "") == "" then "" else " Repair: " + .repair end)),
       "",
       "Policy semantics:",
       "- required: if its preflight fails, do not substitute an ungoverned path or begin",
       "  substantive work. Report the failure and repair, then output",
       "  <amir-loop-blocked>DEPENDENCY_ID</amir-loop-blocked>. This pauses the loop safely",
       "  without declaring the goal complete; a later human turn can resume it.",
       "- preferred: use it when available. If unavailable, report the degraded mode once and",
       "  continue with the best safe fallback.",
       "- off: no preflight or use is required."] | join("\n")
    ' "$DEPENDENCIES" 2>/dev/null) || DEPENDENCY_BRIEF=""
  else
    DEPENDENCY_BRIEF="## Runtime dependency policy

The dependency policy at $DEPENDENCIES is invalid. Treat policy configuration as a required
dependency failure: do not begin substantive work. Report that the file must use schema version
1 with dependency id and policy required, preferred, or off, then output
<amir-loop-blocked>dependency-policy</amir-loop-blocked>."
  fi
fi

# Provider profiles are native, portable Amir Loop policy. They contain identifiers and
# preflight instructions only — never AWS keys or bearer tokens. The host remains responsible
# for inference; this contract makes the expected provider/model/region explicit to the agent
# and gives Bedrock deployments a fail-closed preflight before substantive work.
RUNTIME_BRIEF=""
if [ -n "$RUNTIME_PROFILE" ]; then
  if "$JQ" -e '
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
       "or a Bedrock bearer token; never require long-lived static keys. Confirm model access and",
       "region compatibility through the host/provider status surface. A required mismatch must",
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

# --- calendar window ---------------------------------------------------------------
DEADLINE=""
if [ -n "${AMIR_LOOP_UNTIL:-}" ]; then
  WHEN="$AMIR_LOOP_UNTIL"
  case "$WHEN" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) WHEN="$WHEN 23:59:59" ;;
  esac
  # GNU `date -d "STRING"` first; BSD/macOS date has no -d, so fall back to its
  # `-j -f FORMAT STRING` form. By this point $WHEN is always "%Y-%m-%d %H:%M:%S"
  # (bare dates were normalised above; a caller-supplied time is expected in that
  # shape too), which is the format the BSD branch parses against.
  DEADLINE=$(date -d "$WHEN" +%s 2>/dev/null) \
    || DEADLINE=$(date -j -f "%Y-%m-%d %H:%M:%S" "$WHEN" +%s 2>/dev/null) \
    || DEADLINE="invalid"
  [ -n "$DEADLINE" ] || DEADLINE="invalid"
else
  DAYS="${AMIR_LOOP_DAYS:-5}"
  case "$DAYS" in
    0) DEADLINE="" ;;
    ''|*[!0-9]*) DEADLINE="invalid" ;;
    *)
      mkdir -p "$CWD/.claude" 2>/dev/null || allow_stop
      amir_loop_self_ignore "$CWD/.claude" '/.amir-loop-*' '/amir-loop.*.local.md'
      amir_loop_self_ignore "$CWD/.lumvaleos" '/playbook-events.jsonl' '/.playbook-heartbeat'
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
  case "$MARKED_AT" in
    turn:*)
      # Codex gives every user request a stable turn_id. The same id means this is
      # another Stop evaluation for the completed turn; a different id is a new request.
      if [ -n "$TURN_ID" ] && [ "$MARKED_AT" = "turn:$TURN_ID" ]; then
        allow_stop
      fi
      rm -f "$MARKER"
      ;;
    *)
      # A numeric marker is the Claude/Copilot human-turn count. If this invocation is
      # Codex, switch marker schemes rather than trying to parse Codex's unstable transcript.
      if [ -n "$TURN_ID" ]; then
        rm -f "$MARKER"
      else
        case "$MARKED_AT" in ''|*[!0-9]*) MARKED_AT=999999 ;; esac
        if [ "$(user_turns)" -gt "$MARKED_AT" ] 2>/dev/null; then
          rm -f "$MARKER"
        else
          allow_stop
        fi
      fi
      ;;
  esac
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
  amir_loop_self_ignore "$CWD/.claude" '/.amir-loop-*' '/amir-loop.*.local.md'
  amir_loop_self_ignore "$CWD/.lumvaleos" '/playbook-events.jsonl' '/.playbook-heartbeat'
  {
    cat <<EOF
---
active: true
session_id: "$SESSION"
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

The direct user request that caused this loop to arm is the PRIMARY GOAL. Continue that
goal until every actionable part of it is implemented, verified, and delivered, or until
you have exhausted every in-scope way to advance it. A status report, partial result,
filed follow-up issue, pending check, or newly discovered blocker is evidence that the
primary goal still has work remaining; it is not permission to switch scope.

Project standing orders and their backlog rules are FALLBACK WORK. Consult or select from
that backlog only after the primary goal is genuinely exhausted. If a standing order says
to pick the oldest or highest-priority board item, that instruction applies only at this
fallback boundary and must never pre-empt unfinished work from the direct request.

## Related-work reconciliation

Treat directly related tracker items and open pull requests as part of the PRIMARY GOAL.
Once you understand the request, perform one bounded search of the relevant repositories,
issue trackers, boards, and open pull requests using the component, symptoms, identifiers,
root cause, and intended outcome. Reuse existing investigation and avoid filing duplicates.

Classify every credible match before acting:

- CONFIRMED DUPLICATE: the same root cause and materially the same required outcome. Choose
  one canonical item, cross-link the evidence, and close the duplicate only when closure is
  authorised and the canonical item fully represents its remaining acceptance criteria.
- CO-RESOLVABLE: distinct tracked work that the same coherent implementation and verification
  can safely complete. Include it in the primary-goal change and update or close it with evidence.
- RELATED BUT DISTINCT: overlapping symptoms or component, but a different root cause, scope,
  or acceptance criteria. Link it for context and leave it open; do not expand the current goal.

Never declare duplication from title similarity alone. When uncertain, preserve both items and
record the relationship. Before finishing, do one reconciliation pass over the matches: update
their status, link the delivered evidence, close only what is actually satisfied and authorised,
and state what remains. This sweep is bounded related work, not permission to roam the board.

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
before acting. Reconstruct the PRIMARY GOAL from the direct request and verified repository or
tracker evidence. A summary's suggested next step is a hint, not new authority: ignore it when it
would switch to fallback backlog work while the primary goal still has actionable work.

If, and only if, there is nothing further you can advance, output
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
# Missing fields are validation failures below, not unexpected shell failures. Guard each
# extraction so the global ERR fail-open trap does not exit before invalid state is removed.
ITER=$(printf '%s' "$FM" | grep '^iteration:' | sed 's/iteration: *//' | tr -d '[:space:]' || true)
LIMIT=$(printf '%s' "$FM" | grep '^max_iterations:' | sed 's/max_iterations: *//' | tr -d '[:space:]' || true)
GOAL=$(printf '%s' "$FM" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/' || true)
case "$ITER" in ''|*[!0-9]*) rm -f "$STATE"; allow_stop ;; esac
case "$LIMIT" in ''|*[!0-9]*) rm -f "$STATE"; allow_stop ;; esac

# Stamp the marker with the human turn count at the moment the loop ended, so the next
# human message re-enables arming (see the marker check above).
finish() {
  rm -f "$CLOSEOUT_FILE" "$EXACT_OUTPUT_FILE"
  rm -f "$STATE"
  if [ -n "$TURN_ID" ]; then
    printf 'turn:%s\n' "$TURN_ID" > "$MARKER" 2>/dev/null
  else
    user_turns > "$MARKER" 2>/dev/null
  fi
  exit 0
}

# A required runtime dependency can need a person to repair host configuration. Preserve
# the state, but suppress repeated Stop evaluations for this same human turn. A new user
# turn clears the marker above and resumes the same primary goal.
suspend() {
  if [ -n "$TURN_ID" ]; then
    printf 'turn:%s\n' "$TURN_ID" > "$MARKER" 2>/dev/null
  else
    user_turns > "$MARKER" 2>/dev/null
  fi
  exit 0
}

# Turn cap reached -> a legitimate end.
[ "$LIMIT" -gt 0 ] && [ "$ITER" -ge "$LIMIT" ] && finish

# --- completion promise ------------------------------------------------------------
# Codex provides last_assistant_message as a stable Stop-hook field. Claude and Copilot
# currently require transcript parsing. If neither source is available, allow the stop
# WITHOUT the marker so the next turn can arm again - unreadable input is not completion.
LAST="$LAST_ASSISTANT"

# Slurp and take the last NON-EMPTY transcript message. Two traps, both of which read as "unreadable":
#   1. message text is MULTI-LINE, so a per-line `tail -1` returns the last LINE, not the
#      last message;
#   2. the final assistant.message is routinely a tool-only turn with content "", so a
#      plain `last` is empty.
if [ -z "$LAST" ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  LAST=$("$JQ" -rs '[.[] | select(.type=="assistant.message") | .data.content // "" | select(length>0)] | last // empty' "$TRANSCRIPT" 2>/dev/null)
  if [ -z "$LAST" ]; then
    LAST=$("$JQ" -rs '[.[] | select(.message.role=="assistant") | ([.message.content[]? | select(.type=="text") | .text] | join("\n")) | select(length>0)] | last // empty' "$TRANSCRIPT" 2>/dev/null)
  fi
fi
# A provider can fail after the agent has started a turn (for example VS Code's
# `net::ERR_INCOMPLETE_CHUNKED_ENCODING`). In that case there may be no useful final
# message, or the host may pass the error text through as the final message. Treat known
# transient transport failures as retryable work: preserve the current iteration and
# ask the host to retry the same step. Unknown failures remain fail-open.
FAILED_TURN=0
case "$HOOK_INPUT $LAST" in
  *"ERR_INCOMPLETE_CHUNKED_ENCODING"*|*"ERR_EMPTY_RESPONSE"*|*"ERR_CONNECTION_RESET"*|*"ECONNRESET"*|*"ETIMEDOUT"*|*"fetch failed"*|*"Please check your firewall rules and network connection"*|*"Sorry, your request failed"*|*"[System: Empty message content sanitised"*|*"ThrottlingException"*|*"ServiceUnavailableException"*|*"ModelStreamErrorException"*|*"ModelTimeoutException"*|*"AWS default-chain credential resolve timed out"*)
    FAILED_TURN=1 ;;
esac
if [ "$FAILED_TURN" = "1" ]; then
  RETRY_MAX="${AMIR_LOOP_RETRY_MAX:-3}"
  case "$RETRY_MAX" in ''|*[!0-9]*) RETRY_MAX=3 ;; esac
  # A missing retry file means zero previous retries. Under the global ERR fail-open trap,
  # an unguarded `cat` here exits the whole hook before it can emit the first retry.
  RETRIES=$(cat "$RETRY_FILE" 2>/dev/null || true)
  case "$RETRIES" in ''|*[!0-9]*) RETRIES=0 ;; esac
  if [ "$RETRIES" -ge "$RETRY_MAX" ]; then
    rm -f "$RETRY_FILE"
    allow_stop
  fi
  RETRIES=$((RETRIES + 1))
  printf '%s\n' "$RETRIES" > "$RETRY_FILE" 2>/dev/null || true
  RETRY_PROMPT="The previous attempt failed with a transient provider or network error. Retry the same concrete step now (attempt $RETRIES of $RETRY_MAX). Do not output <promise>$GOAL</promise> for this failed attempt; only finish after a successful, verified result. If the error persists after the retry budget, report the failure clearly and continue with any offline work available."
  if [ -n "$TURN_ID" ]; then
    "$JQ" -n --arg prompt "$RETRY_PROMPT" \
          --arg msg "Amir Loop retry $RETRIES/$RETRY_MAX | transient provider/network failure" \
          '{decision: "block", reason: $prompt, systemMessage: $msg}'
  else
    "$JQ" -n --arg prompt "$RETRY_PROMPT" \
          --arg msg "Amir Loop retry $RETRIES/$RETRY_MAX | transient provider/network failure" \
          '{decision: "block", reason: $prompt, systemMessage: $msg,
            hookSpecificOutput: {hookEventName: "Stop", decision: "block", reason: $prompt}}'
  fi
  exit 0
fi
rm -f "$RETRY_FILE"
[ -n "$LAST" ] || allow_stop

# UserPromptSubmit records a narrowly-scoped exact-output contract. Such a direct user
# instruction must win over loop ceremony: adding closeout tags would itself violate the
# requested output. The marker is still stamped so the same turn cannot auto-arm again.
if [ -f "$EXACT_OUTPUT_FILE" ]; then
  exact_turn=$(cat "$EXACT_OUTPUT_FILE" 2>/dev/null || true)
  if { [ -n "$TURN_ID" ] && [ "$exact_turn" = "$TURN_ID" ]; } || \
     { [ -z "$TURN_ID" ] && [ "$exact_turn" = "legacy" ]; }; then
    finish
  fi
  rm -f "$EXACT_OUTPUT_FILE"
fi

case "$LAST" in
  *"<amir-loop-blocked>"*"</amir-loop-blocked>"*) suspend ;;
esac

if [ -n "$GOAL" ] && [ "$GOAL" != "null" ]; then
  # Phase 2: only a nonce issued for a validated closeout proposal can authorize the
  # promise. The confirmation response is intentionally small and cannot manufacture a
  # fresh proposal while escaping a continuation prompt.
  if [ -f "$CLOSEOUT_FILE" ]; then
    nonce=$("$JQ" -r '.nonce // empty' "$CLOSEOUT_FILE" 2>/dev/null || true)
    case "$LAST" in
      *"<amir-loop-confirm>$nonce</amir-loop-confirm>"*"<promise>$GOAL</promise>"*)
        [ -n "$nonce" ] && finish
        ;;
    esac
    # Any response other than the exact confirmation invalidates the staged proposal.
    rm -f "$CLOSEOUT_FILE"
  fi

  # Phase 1: extract one compact JSON object and validate every deterministic closeout
  # field. A proposal containing the promise is rejected: one response cannot perform
  # both phases. Required dependencies and dispatcher claims must already be terminal.
  closeout=$(printf '%s' "$LAST" | sed -n 's|.*<amir-loop-closeout>\(.*\)</amir-loop-closeout>.*|\1|p' | tail -n 1)
  if [ -n "$closeout" ] && ! printf '%s' "$LAST" | grep -Fq "<promise>$GOAL</promise>"; then
    if printf '%s' "$closeout" | "$JQ" -e '
      .version == 1 and .direct_goal_exhausted == true and
      .continuation_escape == false and
      (.actionable_items | type == "array" and length == 0) and
      (.pending | type == "object") and
      ([.pending.pr, .pending.test, .pending.migration, .pending.deployment,
        .pending.cutover, .pending.follow_up, .pending.verification] |
        all(. == false or . == null or . == [])) and
      (.dependencies | type == "array" and all(.[];
        .required != true or
        (.status == "healthy" and (.evidence_id | type == "string" and length > 0) and
         (.checked_at | type == "string" and length > 0)))) and
      (.playbook | type == "object") and
      (.playbook.status == "none" or
       ((.playbook.status == "completed" or .playbook.status == "failed") and
        .playbook.dispatcher_terminal == true and
        (.playbook.receipt_id | type == "string" and length > 0)))
    ' >/dev/null 2>&1; then
      nonce=$(printf '%s:%s:%s:%s' "$SESSION_KEY" "$TURN_ID" "$ITER" "$(date -u +%s%N 2>/dev/null || date -u +%s)" |
        sha256sum 2>/dev/null | cut -c1-24)
      [ -n "$nonce" ] || nonce="${SESSION_KEY}-${ITER}-$(date -u +%s)"
      printf '%s' "$closeout" | "$JQ" --arg nonce "$nonce" --arg staged_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + {nonce: $nonce, staged_at: $staged_at}' > "$CLOSEOUT_FILE" 2>/dev/null || allow_stop
      CLOSEOUT_PROMPT="The closeout proposal passed deterministic phase-one validation. Before confirming, re-check the preceding answer and current repository/dispatcher state: no actionable item, PR, test, migration, deployment, cutover, follow-up, verification, required dependency, or leased playbook may remain. If that remains true, reply with exactly these two tokens and no status report:
<amir-loop-confirm>$nonce</amir-loop-confirm>
<promise>$GOAL</promise>
If anything remains, do not confirm; continue the next concrete action and later submit a fresh <amir-loop-closeout> proposal."
      "$JQ" -n --arg prompt "$CLOSEOUT_PROMPT" \
        --arg msg "Amir Loop closeout phase 2 | independent confirmation required" \
        '{decision: "block", reason: $prompt, systemMessage: $msg}'
      exit 0
    fi
  fi

  # A bare promise is the supplied false-completion regression. Keep the state and make
  # the machine-readable contract explicit instead of accepting a keyword.
  case "$LAST" in
    *"<promise>$GOAL</promise>"*)
      PROMPT_TEXT="Completion was not accepted because a promise token is not evidence. Continue the direct user goal. When all work is genuinely exhausted, first submit one compact JSON object as <amir-loop-closeout>{...}</amir-loop-closeout> with version=1, direct_goal_exhausted=true, continuation_escape=false, actionable_items=[], every pending field (pr, test, migration, deployment, cutover, follow_up, verification) false, each required dependency healthy with checked_at and evidence_id, and playbook status none or dispatcher-terminal completed/failed with receipt_id. Do not include the promise in phase one."
      "$JQ" -n --arg prompt "$PROMPT_TEXT" --arg msg "Amir Loop rejected unverified completion promise" \
        '{decision: "block", reason: $prompt, systemMessage: $msg}'
      exit 0
      ;;
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

Your standing orders for this run are in .claude/$STATE_NAME. Re-read that file now if the
conversation was compacted or summarised, and whenever you need them. Reconstruct the primary
goal from the direct request and verified evidence; a summary's suggested next step does not
authorise switching scope. This file belongs only to this chat; do not adopt another session's loop.

Continue the DIRECT USER REQUEST that started this loop. It is the primary goal. Do not pick
general board or standing-order backlog work while any actionable implementation, verification,
delivery, pending check, follow-up, or workaround remains for that direct request. Backlog work is
fallback work only after the primary goal is genuinely exhausted.

At that fallback boundary, follow whatever fallback rule your standing orders define.
Never make that rule a reason to leave unfinished primary-goal work.

If you have not yet done so, perform one BOUNDED RELATED-WORK SWEEP for this direct request across
the relevant issue trackers, boards, and open pull requests. Consolidate only confirmed duplicates,
include co-resolvable items covered by the same fix, and link but preserve related-distinct items.
Do not repeat searches without new evidence, and do not use this sweep to switch to general backlog.

Take the next concrete step on the primary goal now. Do not reply with an empty message: if you
have nothing to say, perform the next action instead.

Output <promise>$GOAL</promise> only when the work is exhausted - never to escape a hard
step, and never straight after an empty or failed turn. If turns are failing, say what is
failing."
fi

# Codex consumes only the top-level Stop continuation shape. Do not also send Copilot's
# nested block shape there: two continuation decisions in one Codex result can race the
# host's internal continuation-turn creation.
if [ -n "$TURN_ID" ]; then
  "$JQ" -n --arg prompt "$PROMPT_TEXT" \
        --arg msg "Amir Loop iteration $NEXT/$LIMIT | to stop: output <promise>$GOAL</promise> (only when it is TRUE)" \
        '{decision: "block", reason: $prompt, systemMessage: $msg}'
  exit 0
fi

# Emit both legacy host shapes. Claude Code reads decision/reason at the TOP LEVEL; VS
# Code Copilot Chat reads them from a NESTED hookSpecificOutput and ignores the top-level pair:
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
