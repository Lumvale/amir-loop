#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-}"
manifest="plugins/amir-loop/.codex-plugin/plugin.json"

if [[ -z "$base_ref" ]]; then
  echo "usage: $0 <base-commit>" >&2
  exit 2
fi

git cat-file -e "${base_ref}^{commit}"

if ! git diff --quiet "$base_ref" -- plugins/amir-loop \
  ":(exclude)$manifest"; then
  current_version="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest")"
  base_version="$(git show "${base_ref}:${manifest}" | sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p')"

  if [[ -z "$current_version" || -z "$base_version" ]]; then
    echo "FAIL: could not read the Codex plugin version from $manifest" >&2
    exit 1
  fi

  if [[ "$current_version" == "$base_version" ]]; then
    echo "FAIL: plugins/amir-loop changed but Codex version remains $current_version" >&2
    echo "Bump $manifest so Windows installs into a new cache path instead of overwriting a live plugin." >&2
    exit 1
  fi

  echo "OK: Codex plugin version changed from $base_version to $current_version"
else
  echo "OK: no versioned Amir Loop plugin content changed"
fi
