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
ok()   { printf 'ok:   %s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; RC=1; }

# --- bash ---
ok "bash ${BASH_VERSION%%(*} at $(command -v bash)"

# --- jq: vendored, then PATH ---
_vendor="$(cd "$(dirname "$0")/.." && pwd)/vendor/jq"
case "$(uname -s 2>/dev/null)" in
  Linux)  _cand="$_vendor/jq-linux-amd64" ;;
  Darwin) case "$(uname -m)" in arm64) _cand="$_vendor/jq-macos-arm64";; *) _cand="$_vendor/jq-macos-amd64";; esac ;;
  MINGW*|MSYS*|CYGWIN*) _cand="$_vendor/jq-windows-amd64.exe" ;;
  *) _cand="" ;;
esac
if [ -n "$_cand" ] && [ -x "$_cand" ]; then ok "jq  vendored ($_cand)"
elif command -v jq >/dev/null 2>&1;   then warn "jq  from PATH ($(command -v jq)) - vendored binary missing for this platform"
else fail "jq  not found - the loop will allow every stop and appear broken"
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

exit $RC
