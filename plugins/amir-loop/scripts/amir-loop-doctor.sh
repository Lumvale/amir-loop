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
  --help|-h)
    printf '%s\n' "Usage: amir-loop-doctor.sh [--disable-codex-notify]"
    printf '%s\n' "  --disable-codex-notify  Back up Codex config and remove its top-level notify hook"
    exit 0
    ;;
  *) printf 'FAIL: unknown option: %s\n' "$1"; exit 1 ;;
esac
ok()   { printf 'ok:   %s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; RC=1; }

# --- bash ---
ok "bash ${BASH_VERSION%%(*} at $(command -v bash)"

# --- jq: vendored, then PATH ---
_vendor="$(cd "$(dirname "$0")/.." && pwd)/vendor/jq"
case "$(uname -s 2>/dev/null)" in
  Linux)  _cand="$_vendor/jq-linux-amd64" ;;
  Darwin) case "$(uname -m 2>/dev/null)" in arm64) _cand="$_vendor/jq-macos-arm64";; *) _cand="$_vendor/jq-macos-amd64";; esac ;;
  MINGW*|MSYS*|CYGWIN*) _cand="$_vendor/jq-windows-amd64.exe" ;;
  *) _cand="" ;;
esac
if [ -n "$_cand" ] && "$_cand" --version >/dev/null 2>&1; then
  ok "jq  vendored ($_cand)"
elif [ -n "$_cand" ] && [ -e "$_cand" ]; then
  if command -v jq >/dev/null 2>&1; then
    warn "jq  vendored binary present but does not run on this platform ($_cand) - falling back to PATH jq ($(command -v jq))"
  else
    fail "jq  vendored binary present but does not run here ($_cand), and no jq on PATH - the loop will allow every stop and appear broken"
  fi
elif command -v jq >/dev/null 2>&1; then
  warn "jq  from PATH ($(command -v jq)) - vendored binary missing for this platform"
else
  fail "jq  not found - no vendored binary for this platform and none on PATH - the loop will allow every stop and appear broken"
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

# --- current loop state ---
if [ -f "$PWD/.claude/amir-loop.local.md" ]; then
  ok "loop armed: iteration $(grep -m1 '^iteration:' "$PWD/.claude/amir-loop.local.md" | tr -dc '0-9') of $(grep -m1 '^max_iterations:' "$PWD/.claude/amir-loop.local.md" | tr -dc '0-9')"
else
  ok "no loop armed in this project"
fi
[ -f "$PWD/.claude/amir-loop-off" ] && warn "kill switch present: .claude/amir-loop-off - the hook will not re-arm"
[ "${AMIR_LOOP_OFF:-0}" = "1" ] && warn "AMIR_LOOP_OFF=1 is set in this environment"

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
