#!/bin/bash
set -euo pipefail

MODE="${1:-required}"
case "$MODE" in required|preferred|off) ;; *) echo "error: mode must be required, preferred, or off" >&2; exit 2 ;; esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET=".claude/amir-loop-dependencies.json"
mkdir -p .claude
if [ -e "$TARGET" ]; then
  echo "error: $TARGET already exists; edit its lumvaleos policy explicitly" >&2
  exit 1
fi
sed "s/\"policy\": \"required\"/\"policy\": \"$MODE\"/" "$ROOT/templates/lumvaleos-required.json" > "$TARGET"
echo "Configured LumvaleOS as $MODE in $TARGET. Start a new agent session so host tools and hooks reload."
