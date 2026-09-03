#!/usr/bin/env bash
#
# Point a hooks.json's launcher commands at Git Bash explicitly.
#
# WHY THIS EXISTS
#
# The shipped launchers are `bash -lc '...'`. On Windows, `bash` on PATH resolves to WSL
# (C:\Windows\system32\bash.exe) ahead of Git Bash, and WSL's invocation layer strips every
# variable reference from a `-c` string before bash parses it. The plugin root is therefore
# never resolvable there and the hook cannot run. The plugin cannot choose the host's `bash`,
# so this is an opt-in, per-host setup step rather than something the launcher can fix.
#
# See docs/windows-wsl-hooks.md and https://github.com/Lumvale/amir-loop/issues/30.
#
# The rewritten command deliberately contains NO variables and NO spaces: a leading quoted
# path is a PowerShell *parser* error, and some hosts run hook commands through PowerShell.
# `cygpath -ms` yields the 8.3 short form, in which a directory name containing a space
# becomes an eight-character name ending in ~1, so nothing needs quoting.
#
# Idempotent: running it twice makes no further change.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: patch-windows-hooks.sh [--check] [--bash <path-to-bash.exe>] <hooks.json>

  --check         Report whether the file needs patching; exit 1 if it does, 0 if already
                  applied. Makes no changes. Use this in a health check.
  --bash <path>   Use this bash.exe instead of probing for one.

Writes a one-time backup next to the target as <name>.bak-windows-hooks-<timestamp>.
USAGE
}

CHECK=0
BASH_EXE=""
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --bash) BASH_EXE="${2:-}"; [ -n "$BASH_EXE" ] || { echo "--bash needs a path" >&2; exit 2; }; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) [ -z "$TARGET" ] || { echo "only one hooks.json may be given" >&2; exit 2; }; TARGET="$1"; shift ;;
  esac
done

[ -n "$TARGET" ] || { usage >&2; exit 2; }
[ -f "$TARGET" ] || { echo "no such file: $TARGET" >&2; exit 2; }

# jq resolution: same idiom as hooks/amir-loop-stop.sh -- vendored static binary for this
# platform, then PATH. Unlike the hook, this script fails closed: a setup step that silently
# does nothing is worse than one that says it cannot run.
HERE=$(cd "$(dirname "$0")" && pwd)
_vendor="$HERE/../vendor/jq"
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
  echo "jq not found (looked for a vendored binary in $_vendor and for jq on PATH)" >&2
  exit 3
fi

# The plugin root is the parent of the directory holding hooks.json.
HOOKS_DIR=$(cd "$(dirname "$TARGET")" && pwd)
PLUGIN_ROOT=$(cd "$HOOKS_DIR/.." && pwd)

# Emit paths in a form both PowerShell and bash accept: forward slashes, no spaces.
#
# Shorten ONLY when the path actually contains a space. `cygpath -ms` shortens every
# component it can, so an already-space-free path comes back mangled into 8.3 names
# (.vscode/agent-plugins -> .vscode/AGENT-~1). That still works, but it makes the file
# unreadable and, worse, makes --check report "needs patching" for a file that is already
# functionally correct, because the comparison is textual. Found by running --check against
# a correctly hand-patched file and getting a false positive.
to_host_path() {
  if command -v cygpath >/dev/null 2>&1; then
    # Always ask cygpath for a mixed (drive-letter, forward-slash) path rather than trusting
    # whatever form `pwd` returned: a POSIX /c/... root works under Git Bash but a
    # PowerShell host cannot resolve it, and which form arrives here is not worth
    # predicting. -m keeps the path readable; -ms additionally shortens it to 8.3, which is
    # only needed when a component contains a space.
    case "$1" in
      *" "*) cygpath -ms "$1" ;;
      *)     cygpath -m  "$1" ;;
    esac
    return
  fi
  # No cygpath: not a Windows host, so a POSIX path is already correct. A space is still
  # unrepresentable, because a leading quoted path is a PowerShell parser error and there is
  # no other safe rendering -- say so rather than emit something broken.
  case "$1" in
    *" "*)
      echo "path contains a space and cygpath is unavailable, so no space-free form can be produced: $1" >&2
      exit 3 ;;
    *) printf '%s' "${1//\\//}" ;;
  esac
}

if [ -z "$BASH_EXE" ]; then
  for c in "${ProgramFiles:-/c/Program Files}/Git/bin/bash.exe" \
           "/c/Program Files/Git/bin/bash.exe" \
           "/c/Program Files (x86)/Git/bin/bash.exe" \
           "${LOCALAPPDATA:-/c/Users/$USER/AppData/Local}/Programs/Git/bin/bash.exe" ; do
    [ -x "$c" ] && { BASH_EXE="$c"; break; }
  done
fi
[ -n "$BASH_EXE" ] || {
  echo "could not find Git Bash. Pass --bash <path-to-bash.exe>." >&2
  exit 3
}
[ -x "$BASH_EXE" ] || { echo "not executable: $BASH_EXE" >&2; exit 3; }

SH=$(to_host_path "$BASH_EXE")
ROOT=$(to_host_path "$PLUGIN_ROOT")

# `cygpath -ms` is not guaranteed to remove a space: 8.3 name creation can be disabled per
# volume (`fsutil 8dot3name query`), and then it returns the long path unchanged. Writing that
# would produce a command a PowerShell host cannot parse -- a leading quoted path is a parser
# error there, so the space cannot be quoted away either. Fail closed rather than emit it.
for _p in "$SH" "$ROOT"; do
  case "$_p" in
    *" "*)
      echo "cannot render a space-free path for: $_p" >&2
      echo "8.3 short names are probably disabled on this volume (check: fsutil 8dot3name query)." >&2
      echo "Move the plugin, or pass --bash with a path that has no spaces." >&2
      exit 3 ;;
  esac
done

# Rebuild every launcher command, preserving its own --observe= event.
NEW=$("$JQ" --arg sh "$SH" --arg root "$ROOT" '
  .hooks |= with_entries(
    .value |= map(
      .hooks |= map(
        .command = ($sh + " " + $root + "/hooks/amir-loop-stop.sh"
          + (if (.command // "") | test("--observe=")
             then " --observe=" + ((.command) | capture("--observe=(?<e>[A-Za-z.-]+)").e)
             else "" end))
      )
    )
  )
' "$TARGET")

if [ "$NEW" = "$("$JQ" . "$TARGET")" ]; then
  echo "already pointed at $SH -- no change needed"
  exit 0
fi

if [ "$CHECK" -eq 1 ]; then
  # Deliberately not phrased as "broken". The shipped `bash -lc` launcher is correct on any
  # host that resolves `bash` to Git Bash, and patching such a host is pointless churn. This
  # only reports that the launchers are not pinned to an explicit interpreter.
  echo "not pinned to an explicit interpreter: $TARGET"
  echo "  current first launcher:"
  echo "    $("$JQ" -r '[.hooks | to_entries[] | .value[] | .hooks[] | .command][0]' "$TARGET")"
  echo "  pinning would rewrite them to:"
  echo "    $SH $ROOT/hooks/amir-loop-stop.sh [--observe=<event>]"
  echo
  echo "  Pin only if this host resolves a bare bash to WSL. Confirm in PowerShell with:"
  echo "    (Get-Command bash -All | Select-Object -First 1).Source"
  exit 1
fi

BACKUP="$TARGET.bak-windows-hooks-$(date +%Y%m%d-%H%M%S)"
cp "$TARGET" "$BACKUP"
printf '%s\n' "$NEW" > "$TARGET"

echo "patched $TARGET"
echo "  interpreter: $SH"
echo "  plugin root: $ROOT"
echo "  backup:      $BACKUP"
echo
echo "Reload the host window: hook definitions are read at plugin-load time, so the change"
echo "does not take effect until then and the old error reappears meanwhile."
