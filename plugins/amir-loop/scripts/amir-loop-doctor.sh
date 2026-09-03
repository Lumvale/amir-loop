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
case "${1:-}" in
  "") ;;
  --disable-codex-notify) ACTION="disable-codex-notify" ;;
  --print-jq) ACTION="print-jq" ;;
  --help|-h)
    printf '%s\n' "Usage: amir-loop-doctor.sh [--disable-codex-notify|--print-jq]"
    printf '%s\n' "  --disable-codex-notify  Back up Codex config and remove its top-level notify hook"
    printf '%s\n' "  --print-jq              Print the resolved jq path/name and exit (test-only)"
    exit 0
    ;;
  *) printf 'FAIL: unknown option: %s\n' "$1"; exit 1 ;;
esac
ok()   { [ "$ACTION" = "print-jq" ] || printf 'ok:   %s\n' "$*"; }
warn() { [ "$ACTION" = "print-jq" ] || printf 'warn: %s\n' "$*"; }
fail() { [ "$ACTION" = "print-jq" ] || printf 'FAIL: %s\n' "$*"; RC=1; }

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

# --- principles resolution, CWD upwards ---
_dir="$PWD"; FOUND=""
while [ -n "$_dir" ]; do
  [ -f "$_dir/.claude/amir-loop-principles.md" ] && { FOUND="$_dir/.claude/amir-loop-principles.md"; break; }
  _p=$(dirname "$_dir"); [ "$_p" = "$_dir" ] && break; _dir="$_p"
done
[ -n "$FOUND" ] && ok "principles: $FOUND" || warn "principles: none found from $PWD upwards - the generic body will be used"

# --- runtime dependency policy, CWD upwards ---
_dir="$PWD"; POLICY=""
while [ -n "$_dir" ]; do
  [ -f "$_dir/.claude/amir-loop-dependencies.json" ] && { POLICY="$_dir/.claude/amir-loop-dependencies.json"; break; }
  _p=$(dirname "$_dir"); [ "$_p" = "$_dir" ] && break; _dir="$_p"
done
if [ -z "$POLICY" ]; then
  ok "dependencies: no policy found (portable default: off)"
elif "$JQ" -e '.version == 1 and (.dependencies | type == "array") and all(.dependencies[]; (.id | type == "string" and length > 0) and (.policy == "required" or .policy == "preferred" or .policy == "off"))' "$POLICY" >/dev/null 2>&1; then
  ok "dependencies: valid policy $POLICY"
  while IFS=$'\t' read -r _id _policy; do
    ok "dependency $_id: $_policy"
  done < <("$JQ" -r '.dependencies[] | [.id, .policy] | @tsv' "$POLICY")
else
  fail "dependencies: invalid policy $POLICY - expected version 1 and policies required, preferred, or off"
fi

# --- inference runtime profile, CWD upwards ---
_dir="$PWD"; RUNTIME_PROFILE=""
while [ -n "$_dir" ]; do
  [ -f "$_dir/.claude/amir-loop-runtime.json" ] && { RUNTIME_PROFILE="$_dir/.claude/amir-loop-runtime.json"; break; }
  _p=$(dirname "$_dir"); [ "$_p" = "$_dir" ] && break; _dir="$_p"
done
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

# --- cross-host installation parity ---
# The plugin version is intentionally stable at 1.0.0 while Codex cache-busts installs, so
# comparing manifest versions cannot detect a stale VS Code or Claude copy. Compare the actual
# shared hook fingerprint instead. Missing hosts are informational; a present-but-different copy
# is actionable because that host will behave differently from the doctor being run now.
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

exit $RC
