#!/usr/bin/env bash
set -euo pipefail

project_root=${1:-$PWD}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
template="$script_dir/../templates/principles/lumvale-fleet.md"
target="$project_root/.claude/amir-loop-principles.md"

[ -f "$template" ] || { printf 'error: packaged principles template is missing: %s\n' "$template" >&2; exit 1; }
[ -d "$project_root" ] || { printf 'error: project root does not exist or is not a directory: %s\n' "$project_root" >&2; exit 1; }
if [ -e "$target" ]; then
  cat -- "$target"
  printf 'warning: existing principles were preserved without modification: %s\n' "$target" >&2
  exit 0
fi

mkdir -p -- "$project_root/.claude"
cp -- "$template" "$target"
printf 'Created: %s\n' "$target"
printf '%s\n' 'Next: fill the Backlog, Merge authority, Definition of done, and Never placeholders.'
