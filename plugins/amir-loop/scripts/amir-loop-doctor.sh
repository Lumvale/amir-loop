#!/bin/bash
# Amir Loop - diagnose why the loop is or is not working on this machine.
# Every check the hook performs silently, reported out loud.
#
# Mirrors plugins/amir-loop/hooks/amir-loop-stop.sh exactly for jq resolution and
# principles resolution: those two blocks must stay in lockstep with the hook, or this
# diagnostic will confidently report a state the hook does not actually see. The hook
# lives in hooks/, this script lives in scripts/ - both climb one directory then into
# vendor/jq, so `$(dirname "$0")/..` resolves to the same plugin root from either.
set -uo pipefail
RC=0
ACTION="diagnose"
JSON_MODE=0
case "${1:-}" in
  "") ;;
  --json) JSON_MODE=1 ;;
  --disable-codex-notify) ACTION="disable-codex-notify" ;;
  --print-jq) ACTION="print-jq" ;;
  --help|-h)
    printf '%s\n' "Usage: amir-loop-doctor.sh [--json|--disable-codex-notify|--print-jq]"
    printf '%s\n' "  --json                  Emit a compact, schema-versioned diagnostic object"
    printf '%s\n' "  --disable-codex-notify  Back up Codex config and remove its top-level notify hook"
    printf '%s\n' "  --print-jq              Print the resolved jq path/name and exit (test-only)"
    exit 0
    ;;
  *) printf 'FAIL: unknown option: %s\n' "$1"; exit 1 ;;
esac
DIAGNOSTICS=()
diagnostic_code() {
  case "$1" in
    bash\ *) echo runtime.bash ;;
    host\ bash:*) echo runtime.host_bash ;;
    jq\ \ *) echo dependency.jq ;;
    cygpath*) echo dependency.cygpath ;;
    *conflicting\ Stop-hook*|ralph-loop*|amir-loop-stop.sh*) echo hooks.conflict ;;
    Workspace\ policy\ root:*) echo policy.workspace ;;
    principles:*) echo policy.principles ;;
    policy\ provenance:*) echo policy.provenance ;;
    dependencies:*) echo policy.dependencies ;;
    dependency\ *) echo policy.dependency ;;
    LumvaleOS\ serving\ transport:*) echo lumvaleos.transport ;;
    LumvaleOS\ native\ MCP*|LumvaleOS\ transport\ receipt*) echo lumvaleos.native_transport ;;
    runtime\ provider:*) echo runtime.profile ;;
    runtime\ target:*) echo runtime.target ;;
    Bedrock\ *) echo runtime.activation ;;
    *loop\ state*|legacy\ project-wide*|no\ loop\ armed*|kill\ switch*|AMIR_LOOP_OFF*) echo loop.state ;;
    worktree\ claim:*) echo worktree.claim ;;
    cross-host\ copy*|cross-host\ parity:*) echo hooks.cross_host_parity ;;
    action\ provenance\ identity:*) echo provenance.identity ;;
    action\ provenance\ risk:*) echo provenance.risk ;;
    action\ provenance:*) echo provenance.ledger ;;
    *Codex\ notify*|Codex\ config*) echo codex.notify ;;
    *) echo diagnostic.other ;;
  esac
}
diagnostic_remediation() {
  case "$1" in
    runtime.host_bash) echo "Put Git for Windows bin ahead of System32 or run patch-windows-hooks.sh." ;;
    dependency.jq) echo "Restore the vendored jq binary for this platform or install jq on PATH." ;;
    dependency.cygpath) echo "Repair the Git for Windows installation so cygpath is available." ;;
    hooks.conflict) echo "Disable the conflicting or duplicate Stop-hook registration." ;;
    policy.principles) echo "Render or create principles for the selected project or Workspace." ;;
    policy.dependencies) echo "Repair amir-loop-dependencies.json to the documented version 1 schema." ;;
    lumvaleos.native_transport) echo "Repair native MCP transport and restart the agent session." ;;
    runtime.activation) echo "Expose the configured provider activation signal in the host session." ;;
    runtime.profile) echo "Repair amir-loop-runtime.json to the documented version 1 provider schema." ;;
    loop.state) echo "Remove the stale state or kill switch only after confirming the owning session is inactive." ;;
    worktree.claim) echo "Preserve live claims; reclaim only well-formed claims beyond the configured stale threshold." ;;
    hooks.cross_host_parity) echo "Upgrade or reinstall Amir Loop on the named host, then compare hook hashes again." ;;
    provenance.ledger) echo "Repair the append-only provenance ledger before relying on attribution." ;;
    provenance.identity) echo "Configure the host to include model identity in future hook events." ;;
    provenance.risk) echo "Review the named materialized target and repair the host path-conversion boundary." ;;
    codex.notify) echo "Review the Codex notify hook; use --disable-codex-notify only with explicit authorization." ;;
    *) echo "" ;;
  esac
}
emit_diagnostic() {
  _severity="$1"; shift
  _message="$*"
  _code=$(diagnostic_code "$_message")
  _remediation=""
  [ "$_severity" = "ok" ] || _remediation=$(diagnostic_remediation "$_code")
  DIAGNOSTICS+=("$_severity"$'\t'"$_code"$'\t'"$_message"$'\t'"$_remediation")
  if [ "$JSON_MODE" -eq 0 ] && [ "$ACTION" != "print-jq" ]; then
    case "$_severity" in ok) printf 'ok:   %s\n' "$_message";; warn) printf 'warn: %s\n' "$_message";; fail) printf 'FAIL: %s\n' "$_message";; esac
  fi
}
ok()   { emit_diagnostic ok "$*"; }
warn() { emit_diagnostic warn "$*"; }
fail() { emit_diagnostic fail "$*"; RC=1; }

render_json() {
  _plugin_root=$(cd "$(dirname "$0")/.." && pwd)
  _manifest="$_plugin_root/.codex-plugin/plugin.json"
  _plugin_version="unknown"
  [ -f "$_manifest" ] && _plugin_version=$("$JQ" -r '.version // "unknown"' "$_manifest" 2>/dev/null || echo unknown)
  _status=ok
  [ "$RC" -ne 0 ] && _status=fail
  if [ "$RC" -eq 0 ] && printf '%s\n' "${DIAGNOSTICS[@]}" | grep -q '^warn'; then _status=warn; fi
  printf '%s\n' "${DIAGNOSTICS[@]}" | "$JQ" -Rsc \
    --arg status "$_status" --arg root "$_plugin_root" --arg version "$_plugin_version" '
      split("\n") | map(select(length > 0) | split("\t") |
        {severity: .[0], code: .[1], message: .[2]} +
        (if (.[3] // "") == "" then {} else {remediation: .[3]} end)) as $checks |
      {schema_version: 1, status: $status,
       plugin: {name: "amir-loop", version: $version, root: $root},
       summary: {
         ok: ($checks | map(select(.severity == "ok")) | length),
         warn: ($checks | map(select(.severity == "warn")) | length),
         fail: ($checks | map(select(.severity == "fail")) | length),
         total: ($checks | length)
       }, checks: $checks}'
}

# --- bash ---
ok "bash ${BASH_VERSION%%(*} at $(command -v bash)"

# --- WSL risk for the bare `bash` the HOST resolves ---
# The Claude/Copilot launcher is a bare `bash`, resolved from the *Windows* PATH by the host.
# This script cannot observe that PATH: it is already inside Git Bash, whose PATH is
# MSYS-translated and prepends /usr/bin (Git's own bash), which the host never sees. So
# `command -v bash` above, and any walk of $PATH here, describe THIS shell and not the host.
# Walking $PATH here reports Git's bash and reads as "all clear" on a machine where the host
# demonstrably launches WSL -- a false green, which is worse than no check.
#
# Report the risk from a fact that is true of the host, and leave the one-line confirmation
# to the user. If System32 has a bash.exe, it is WSL, and it precedes anything appended to
# PATH. WSL strips variable references from a `-c` string before bash parses it, so the
# plugin root is never resolvable there and every hook is inert. See #30.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    if [ -e "${SYSTEMROOT:-/c/Windows}/System32/bash.exe" ] || [ -e "/c/Windows/System32/bash.exe" ]; then
      # Name this installation's own copy of the setup script, not a repo-relative path:
      # a Claude Code install ships only plugins/amir-loop, so "plugins/amir-loop/scripts/..."
      # is a path the user cannot cd to.
      warn "host bash: System32 ships a bash.exe (WSL) and precedes anything appended to PATH, so the host may launch WSL, where every hook is inert. Confirm in PowerShell with: (Get-Command bash -All | Select-Object -First 1).Source - if that prints System32, put Git for Windows' bin ahead of System32 on PATH, or run $(dirname "$0")/patch-windows-hooks.sh (see https://github.com/Lumvale/amir-loop/blob/main/docs/windows-wsl-hooks.md)"
    else
      ok "host bash: no WSL bash.exe in System32, so a bare bash cannot resolve to WSL"
    fi
    ;;
esac

# --- jq: vendored, then PATH ---
_vendor="$(cd "$(dirname "$0")/.." && pwd)/vendor/jq"
case "$(uname -s 2>/dev/null)" in
  Linux)  _cand="$_vendor/jq-linux-amd64" ;;
  Darwin) case "$(uname -m 2>/dev/null)" in arm64) _cand="$_vendor/jq-macos-arm64";; *) _cand="$_vendor/jq-macos-amd64";; esac ;;
  MINGW*|MSYS*|CYGWIN*) _cand="$_vendor/jq-windows-amd64.exe" ;;
  *) _cand="" ;;
esac
if [ -n "$_cand" ] && "$_cand" --version >/dev/null 2>&1; then
  JQ="$_cand"
  ok "jq  vendored ($_cand)"
elif [ -n "$_cand" ] && [ -e "$_cand" ]; then
  if command -v jq >/dev/null 2>&1; then
    JQ="jq"
    warn "jq  vendored binary present but does not run on this platform ($_cand) - falling back to PATH jq ($(command -v jq))"
  else
    fail "jq  vendored binary present but does not run here ($_cand), and no jq on PATH - the loop will allow every stop and appear broken"
  fi
elif command -v jq >/dev/null 2>&1; then
  JQ="jq"
  warn "jq  from PATH ($(command -v jq)) - vendored binary missing for this platform"
else
  fail "jq  not found - no vendored binary for this platform and none on PATH - the loop will allow every stop and appear broken"
fi

# Test-only: report the resolved jq and stop, so tests/parity.bats can assert this
# matches the hook's own resolution without reimplementing the platform mapping.
if [ "$ACTION" = "print-jq" ]; then
  printf '%s\n' "${JQ:-}"
  exit "$RC"
fi

# --- Windows-only path translation ---
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    command -v cygpath >/dev/null 2>&1 && ok "cygpath present" || fail "cygpath missing on Windows - cwd/transcript paths will not convert" ;;
esac

# --- conflicting Stop hooks ---
# AMIR_LOOP_FAKE_ENABLED_PLUGINS exists solely to make this check testable without a real
# ~/.claude/settings.json; the real path below (parsing the settings file) is what runs
# whenever that var is unset, which is every real invocation.
SETTINGS="${HOME}/.claude/settings.json"
ENABLED="${AMIR_LOOP_FAKE_ENABLED_PLUGINS:-}"
if [ -z "$ENABLED" ] && [ -f "$SETTINGS" ]; then
  # enabledPlugins in settings.json is a map of "name@marketplace": true|false. Extract just
  # the keys that are mapped to true, matching on quoted-string-colon-true rather than the
  # brief's strip-characters approach (see task report for why: that approach corrupts any
  # plugin name containing t/r/u/e/:/", e.g. "ralph-loop" itself loses every 'r').
  ENABLED=$(grep -o '"[A-Za-z0-9@._-]*"[[:space:]]*:[[:space:]]*true' "$SETTINGS" 2>/dev/null | sed -E 's/^"([^"]*)".*/\1/' | tr '\n' ' ')
fi
case "$ENABLED" in
  *ralph-loop*) fail "ralph-loop is enabled and registers its own Stop hook - both will fire and both will increment the counter; disable one" ;;
  *) ok "no conflicting Stop-hook plugin detected" ;;
esac
if [ -f "$SETTINGS" ] && grep -q 'amir-loop-stop' "$SETTINGS" 2>/dev/null; then
  fail "amir-loop-stop.sh is registered in ~/.claude/settings.json AND shipped by the plugin - these are mutually exclusive"
fi

# --- Workspace-bound policy, then portable ancestry fallback ---
FOUND=""; POLICY=""; RUNTIME_PROFILE=""
_ws="${AMIR_LOOP_WORKSPACE_ROOT:-${WORKSPACE_ROOT:-}}"
case "$_ws" in [A-Za-z]:*) command -v cygpath >/dev/null 2>&1 && _ws=$(cygpath -u "$_ws") ;; esac
if [ -n "$_ws" ] && [ -f "$_ws/workspace.yaml" ]; then
  ok "Workspace policy root: $_ws"
  [ -f "$_ws/.lumvaleos/amir-loop-principles.md" ] && FOUND="$_ws/.lumvaleos/amir-loop-principles.md"
  [ -z "$FOUND" ] && [ -f "$_ws/.claude/amir-loop-principles.md" ] && FOUND="$_ws/.claude/amir-loop-principles.md"
  [ -f "$_ws/.claude/amir-loop-dependencies.json" ] && POLICY="$_ws/.claude/amir-loop-dependencies.json"
  [ -f "$_ws/.claude/amir-loop-runtime.json" ] && RUNTIME_PROFILE="$_ws/.claude/amir-loop-runtime.json"
else
  _dir="$PWD"
  while [ -n "$_dir" ]; do
    [ -z "$FOUND" ] && [ -f "$_dir/.claude/amir-loop-principles.md" ] && FOUND="$_dir/.claude/amir-loop-principles.md"
    [ -z "$POLICY" ] && [ -f "$_dir/.claude/amir-loop-dependencies.json" ] && POLICY="$_dir/.claude/amir-loop-dependencies.json"
    [ -z "$RUNTIME_PROFILE" ] && [ -f "$_dir/.claude/amir-loop-runtime.json" ] && RUNTIME_PROFILE="$_dir/.claude/amir-loop-runtime.json"
    [ -f "$_dir/workspace.yaml" ] && break
    _p=$(dirname "$_dir"); [ "$_p" = "$_dir" ] && break; _dir="$_p"
  done
fi
if [ -n "$FOUND" ]; then
  ok "principles: $FOUND"
  _policy_marker=$(grep -m1 'lumvaleos-agent-policy:' "$FOUND" 2>/dev/null || true)
  [ -n "$_policy_marker" ] && ok "policy provenance: $_policy_marker"
else
  warn "principles: none for the selected scope - use the generic body or run lumvaleos policy render"
fi

# --- runtime dependency policy ---
if [ -z "$POLICY" ]; then
  ok "dependencies: no policy found (portable default: off)"
elif "$JQ" -e '.version == 1 and (.dependencies | type == "array") and all(.dependencies[]; (.id | type == "string" and length > 0) and (.policy == "required" or .policy == "preferred" or .policy == "off") and ((.fallback? == null) or (.id == "lumvaleos" and .fallback.kind == "governed-cli-mcp-bridge" and .fallback.entrypoint == "amir-loop-lumvaleos/scripts/lumvaleos-preflight" and .fallback.scope == "read-only-authoritative-preflight" and .fallback.attempts == 1)))' "$POLICY" >/dev/null 2>&1; then
  ok "dependencies: valid policy $POLICY"
  while IFS=$'\t' read -r _id _policy _fallback_kind _fallback_entrypoint; do
    ok "dependency $_id: $_policy"
    if [ -n "$_fallback_kind" ]; then
      ok "dependency $_id fallback transport: $_fallback_kind via $_fallback_entrypoint (native transport remains primary)"
    fi
  done < <("$JQ" -r '.dependencies[] | [.id, .policy, (.fallback.kind // ""), (.fallback.entrypoint // "")] | @tsv' "$POLICY" | tr -d '\r')
else
  fail "dependencies: invalid policy $POLICY - expected version 1 and policies required, preferred, or off"
fi

_transport_receipt="${AMIR_LOOP_LUMVALEOS_TRANSPORT_RECEIPT:-}"
if [ -z "$_transport_receipt" ] && [ -n "${_ws:-}" ]; then
  _transport_receipt="$_ws/.lumvaleos/amir-loop-lumvaleos-transport.json"
fi
if [ -n "$_transport_receipt" ] && [ -f "$_transport_receipt" ]; then
  _now_epoch=$(date -u +%s 2>/dev/null || date +%s)
  if "$JQ" -e --argjson now "$_now_epoch" '.version == 1 and (.transport == "native-mcp" or .transport == "cli-mcp-bridge") and (.degraded | type == "boolean") and (.checked_at | type == "string" and length > 0) and (.expires_at_epoch | type == "number") and .expires_at_epoch > $now and (.workspace | type == "string" and length > 0)' "$_transport_receipt" >/dev/null 2>&1; then
    _serving_transport=$("$JQ" -r '.transport' "$_transport_receipt")
    _serving_degraded=$("$JQ" -r '.degraded' "$_transport_receipt")
    _serving_workspace=$("$JQ" -r '.workspace' "$_transport_receipt")
    ok "LumvaleOS serving transport: $_serving_transport degraded=$_serving_degraded workspace=$_serving_workspace"
    [ "$_serving_transport" = "cli-mcp-bridge" ] && warn "LumvaleOS native MCP is not restored; restart the agent session after repairing host transport"
  else
    warn "LumvaleOS transport receipt is invalid or expired: $_transport_receipt"
  fi
fi

# --- inference runtime profile ---
if [ -z "$RUNTIME_PROFILE" ]; then
  ok "runtime provider: no profile found (portable default: host-managed)"
elif "$JQ" -e '
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
  _provider=$("$JQ" -r '.provider' "$RUNTIME_PROFILE")
  _region=$("$JQ" -r '.region // "host-resolved"' "$RUNTIME_PROFILE")
  _model=$("$JQ" -r '.model // "host-resolved"' "$RUNTIME_PROFILE")
  ok "runtime provider: valid $_provider profile $RUNTIME_PROFILE"
  ok "runtime target: region=$_region model=$_model (credentials redacted)"
  if [ "$_provider" = "bedrock" ]; then
    if [ "${CLAUDE_CODE_USE_BEDROCK:-0}" = "1" ] || [ "${AMIR_LOOP_PROVIDER:-}" = "bedrock" ]; then
      ok "Bedrock activation signal present"
    else
      _required=$("$JQ" -r '.required // true' "$RUNTIME_PROFILE")
      if [ "$_required" = "true" ]; then
        fail "Bedrock profile is required but this process has no activation signal; expose CLAUDE_CODE_USE_BEDROCK=1 or AMIR_LOOP_PROVIDER=bedrock in the host session"
      else
        warn "Bedrock profile is configured but this doctor process has no activation signal"
      fi
    fi
  fi
else
  fail "runtime provider: invalid profile $RUNTIME_PROFILE - version 1 requires provider and Bedrock requires region, model, and credential_source; never store credentials here"
fi

# --- current loop state ---
shopt -s nullglob
_session_states=("$PWD"/.claude/amir-loop.*.local.md)
if [ "${#_session_states[@]}" -gt 0 ]; then
  ok "${#_session_states[@]} session-scoped loop state file(s) in this project"
elif [ -f "$PWD/.claude/amir-loop.local.md" ]; then
  warn "legacy project-wide loop state found: $PWD/.claude/amir-loop.local.md - current hooks ignore it so one chat cannot take over another"
else
  ok "no loop armed in this project"
fi
[ -f "$PWD/.claude/amir-loop-off" ] && warn "kill switch present: .claude/amir-loop-off - the hook will not re-arm"
[ "${AMIR_LOOP_OFF:-0}" = "1" ] && warn "AMIR_LOOP_OFF=1 is set in this environment"

_claim="$PWD/.claude/.amir-loop-worktree-claim"
_claim_now="${AMIR_LOOP_CLAIM_NOW:-$(date -u +%s)}"
_claim_stale="${AMIR_LOOP_CLAIM_STALE_SECONDS:-604800}"
if [ ! -d "$_claim" ]; then
  ok "worktree claim: unclaimed"
else
  _claim_owner=$(cat "$_claim/owner" 2>/dev/null || true)
  _claim_heartbeat=$(cat "$_claim/heartbeat" 2>/dev/null || true)
  _claim_valid=1
  case "$_claim_owner" in ''|*[!A-Za-z0-9._-]*) fail "worktree claim: invalid owner metadata"; _claim_valid=0 ;; esac
  case "$_claim_heartbeat:$_claim_now:$_claim_stale" in *[!0-9:]*) fail "worktree claim: invalid heartbeat or clock metadata"; _claim_valid=0 ;; esac
  if [ "$_claim_valid" -eq 1 ]; then
      _claim_age=$((_claim_now - _claim_heartbeat))
      if [ "$_claim_age" -lt 0 ]; then
        fail "worktree claim: future-dated heartbeat for owner ${_claim_owner:-unknown}"
      elif [ "$_claim_age" -gt "$_claim_stale" ]; then
        warn "worktree claim: stale owner=$_claim_owner age=${_claim_age}s stale-after=${_claim_stale}s"
      else
        ok "worktree claim: live owner=$_claim_owner age=${_claim_age}s stale-after=${_claim_stale}s"
      fi
  fi
fi

# --- cross-host installation parity ---
# Marketplace versions identify releases, but development installs and host caches can still
# diverge. Compare the actual shared hook fingerprint as well. Missing hosts are informational;
# a present-but-different copy is actionable because that host behaves differently.
BASE_HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/amir-loop-stop.sh"
BASE_SUM=$(cksum "$BASE_HOOK" 2>/dev/null | awk '{print $1 ":" $2}')
HOST_COPIES=()
for _copy in \
  "$HOME"/.codex/plugins/cache/lumvale/amir-loop/*/hooks/amir-loop-stop.sh \
  "$HOME"/.vscode/agent-plugins/github.com/Lumvale/amir-loop/plugins/amir-loop/hooks/amir-loop-stop.sh \
  "$HOME"/.claude/plugins/cache/lumvale/amir-loop/*/hooks/amir-loop-stop.sh \
  "$HOME"/.gemini/config/plugins/amir-loop/hooks/amir-loop-stop.sh; do
  [ -f "$_copy" ] && HOST_COPIES+=("$_copy")
done
if [ "${#HOST_COPIES[@]}" -eq 0 ]; then
  ok "cross-host parity: no other installed Amir Loop copies found under HOME"
else
  _drift=0
  for _copy in "${HOST_COPIES[@]}"; do
    _sum=$(cksum "$_copy" 2>/dev/null | awk '{print $1 ":" $2}')
    if [ -n "$BASE_SUM" ] && [ "$_sum" = "$BASE_SUM" ]; then
      ok "cross-host copy matches: $_copy"
    else
      warn "cross-host copy differs from this plugin: $_copy"
      _drift=1
    fi
  done
  [ "$_drift" = "0" ] && ok "cross-host parity: all discovered copies match"
fi

# --- prospective action provenance ---
# Hooks can identify only what their host payload exposes.  Summarise the append-only, redacted
# ledger and keep every missing host/model field explicit; retrospective inference belongs in an
# incident investigation, never in a diagnostic that might be mistaken for proof.
PROVENANCE_ROOT="${AMIR_LOOP_PROVENANCE_ROOT:-${AMIR_LOOP_WORKSPACE_ROOT:-${WORKSPACE_ROOT:-$PWD}}}"
case "$PROVENANCE_ROOT" in [A-Za-z]:*) command -v cygpath >/dev/null 2>&1 && PROVENANCE_ROOT=$(cygpath -u "$PROVENANCE_ROOT") ;; esac
PROVENANCE_LEDGER="$PROVENANCE_ROOT/.lumvaleos/agent-actions.jsonl"
if [ ! -f "$PROVENANCE_LEDGER" ]; then
  ok "action provenance: no ledger found ($PROVENANCE_LEDGER); only future hooked actions can be attributed"
elif ! "$JQ" -s -e 'all(.[]; type == "object" and .schema_version == 1)' "$PROVENANCE_LEDGER" >/dev/null 2>&1; then
  warn "action provenance: unreadable or invalid ledger $PROVENANCE_LEDGER - attribution unavailable"
else
  _events=$("$JQ" -s 'length' "$PROVENANCE_LEDGER")
  ok "action provenance: $_events event(s) at $PROVENANCE_LEDGER"
  while IFS=$'\t' read -r _h _m _n; do
    ok "action provenance identity: host=$_h model=$_m count=$_n"
  done < <("$JQ" -rs '
    group_by([.host_surface // "unknown", .model // "unknown"])[] |
    [.[0].host_surface // "unknown", .[0].model // "unknown", length] | @tsv
  ' "$PROVENANCE_LEDGER")
  _unknown_models=$("$JQ" -s '[.[] | select((.model // "unknown") == "unknown")] | length' "$PROVENANCE_LEDGER")
  [ "$_unknown_models" -eq 0 ] || warn "action provenance: model identity unavailable for $_unknown_models event(s); reported as unknown"
  while IFS=$'\t' read -r _at _h _m _session _turn _risk_target; do
    warn "action provenance risk: $_at host=$_h model=$_m session=$_session turn=$_turn drive-root-path-materialization target=$_risk_target"
  done < <("$JQ" -rs '
    [.[] | select(.risk == "drive-root-path-materialization") |
      [.observed_at, .host_surface, .model, .session_id, .turn_id,
       (.materialized_targets | map(select(test("^[A-Za-z]:/c/"; "i"))) | first // "unknown")]] |
    sort_by(.[0]) | reverse | .[:10][] | @tsv
  ' "$PROVENANCE_LEDGER")
fi

# --- Codex notify hook ---
# Codex runs `notify` as a host-level after-agent hook, independently of Amir Loop's
# Stop hook. On Windows, an oversized command can fail before the loop gets control.
# Keep this diagnostic advisory by default; disabling a user's notification hook is
# an explicit action and must never happen during a normal doctor run.
if [ -n "${AMIR_LOOP_CODEX_CONFIG:-}" ]; then
  CODEX_CONFIG="$AMIR_LOOP_CODEX_CONFIG"
elif [ -n "${CODEX_HOME:-}" ]; then
  CODEX_CONFIG="$CODEX_HOME/config.toml"
elif [ -n "${USERPROFILE:-}" ] && [ "$(uname -s 2>/dev/null)" != "Linux" ] && [ "$(uname -s 2>/dev/null)" != "Darwin" ]; then
  _profile="$USERPROFILE"
  if command -v cygpath >/dev/null 2>&1; then _profile=$(cygpath -u "$_profile"); fi
  CODEX_CONFIG="$_profile/.codex/config.toml"
else
  CODEX_CONFIG="${HOME}/.codex/config.toml"
fi

if [ -f "$CODEX_CONFIG" ]; then
  NOTIFY_LINES=$(grep -Ec '^[[:space:]]*notify[[:space:]]*=' "$CODEX_CONFIG" 2>/dev/null || true)
  if [ "$NOTIFY_LINES" -gt 0 ]; then
    if [ "$ACTION" = "disable-codex-notify" ]; then
      if [ "$NOTIFY_LINES" -ne 1 ]; then
        fail "Codex config has $NOTIFY_LINES notify entries; refusing automatic edit - review $CODEX_CONFIG manually"
      elif ! grep -E '^[[:space:]]*notify[[:space:]]*=.*\][[:space:]]*$' "$CODEX_CONFIG" >/dev/null 2>&1; then
        fail "Codex notify entry is not a single-line array; refusing automatic edit - review $CODEX_CONFIG manually"
      else
        _stamp=$(date '+%Y%m%d-%H%M%S')
        _backup="${CODEX_CONFIG}.backup-amir-loop-${_stamp}"
        if cp "$CODEX_CONFIG" "$_backup"; then
          _tmp="${CODEX_CONFIG}.amir-loop-tmp.$$"
          if awk '!/^[[:space:]]*notify[[:space:]]*=/' "$CODEX_CONFIG" > "$_tmp" && mv "$_tmp" "$CODEX_CONFIG"; then
            ok "disabled Codex notify hook in $CODEX_CONFIG (backup: $_backup)"
          else
            rm -f "$_tmp"
            fail "could not update Codex config; original backup is at $_backup"
          fi
        else
          fail "could not back up Codex config before editing: $CODEX_CONFIG"
        fi
      fi
    else
      warn "Codex notify hook configured in $CODEX_CONFIG; it is independent of Amir Loop and may fail before the Stop hook (use --disable-codex-notify for a backed-up repair)"
    fi
  else
    ok "no Codex notify hook configured ($CODEX_CONFIG)"
  fi
else
  ok "Codex config not found ($CODEX_CONFIG)"
fi

if [ "$JSON_MODE" -eq 1 ]; then
  render_json
fi
exit $RC
