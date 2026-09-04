#!/bin/bash
set -euo pipefail

MODE="${1:-required}"
case "$MODE" in required|preferred|off) ;; *) echo "error: mode must be required, preferred, or off" >&2; exit 2 ;; esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_ROOT="${AMIR_LOOP_WORKSPACE_ROOT:-${WORKSPACE_ROOT:-$PWD}}"
case "$TARGET_ROOT" in
  [A-Za-z]:*) command -v cygpath >/dev/null 2>&1 && TARGET_ROOT=$(cygpath -u "$TARGET_ROOT") ;;
esac
if [ -n "${AMIR_LOOP_WORKSPACE_ROOT:-${WORKSPACE_ROOT:-}}" ] && [ ! -f "$TARGET_ROOT/workspace.yaml" ]; then
  echo "error: selected Workspace root has no workspace.yaml: $TARGET_ROOT" >&2
  exit 2
fi
TARGET="$TARGET_ROOT/.claude/amir-loop-dependencies.json"
mkdir -p "$TARGET_ROOT/.claude"
if [ -e "$TARGET" ]; then
  echo "error: $TARGET already exists; edit its lumvaleos policy explicitly" >&2
  exit 1
fi
sed "s/\"policy\": \"required\"/\"policy\": \"$MODE\"/" "$ROOT/templates/lumvaleos-required.json" > "$TARGET"
echo "Configured LumvaleOS as $MODE in $TARGET. Validate and render this Workspace's agent policy, then start a new agent session so host tools and hooks reload."
