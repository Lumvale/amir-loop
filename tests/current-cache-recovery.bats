load helper

setup() {
  command -v powershell.exe >/dev/null 2>&1 || skip "PowerShell is Windows-only"
  launcher=$(cygpath -w "$BATS_TEST_DIRNAME/../scripts/amir-loop-current.ps1")
  cache="$BATS_TEST_TMPDIR/cache"
  mkdir -p "$cache"
}

make_plugin() {
  version=$1
  name=${2:-amir-loop}
  command=${3:-status}
  root="$cache/$version"
  mkdir -p "$root/.claude-plugin" "$root/scripts"
  printf '{"name":"%s","version":"1.0.0"}\n' "$name" > "$root/.claude-plugin/plugin.json"
  cat > "$root/scripts/amir-loop-$command.ps1" <<EOF
Write-Output '$version'
EOF
}

make_shell_plugin() {
  version=$1
  root="$cache/$version"
  mkdir -p "$root/.claude-plugin" "$root/scripts"
  printf '{"name":"amir-loop","version":"1.0.0"}\n' > "$root/.claude-plugin/plugin.json"
  cat > "$root/scripts/amir-loop-status.sh" <<'EOF'
#!/usr/bin/env bash
printf 'argc:%s\n' "$#"
printf 'arg:<%s>\n' "$@"
EOF
}

@test "recovery chooses the newest valid cache without timestamps" {
  make_plugin '1.0.0+codex.20260905163000'
  make_plugin '1.0.0+codex.20260906194500'
  touch -t 203001010000 "$cache/1.0.0+codex.20260905163000"

  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$launcher" status -CacheRoot "$(cygpath -w "$cache")"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '\r')" = '1.0.0+codex.20260906194500' ]
}

@test "recovery ignores a newer decoy with the wrong plugin identity" {
  make_plugin '1.0.0+codex.20260906194500'
  make_plugin '9.9.9+codex.99999999999999' 'not-amir-loop'

  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$launcher" status -CacheRoot "$(cygpath -w "$cache")"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '\r')" = '1.0.0+codex.20260906194500' ]
}

@test "recovery orders semantic versions numerically" {
  make_plugin '1.9.0+codex.20260907194500'
  make_plugin '1.10.0+codex.20260906194500'

  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$launcher" status -CacheRoot "$(cygpath -w "$cache")"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '\r')" = '1.10.0+codex.20260906194500' ]
}

@test "recovery invokes shell fallback through Git Bash with path and argv intact" {
  cache="$BATS_TEST_TMPDIR/cache with spaces"
  mkdir -p "$cache"
  make_shell_plugin '2.0.0+codex.20260906194500'

  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$launcher" status -Json -CacheRoot "$(cygpath -w "$cache")" -CommandArguments 'value with spaces'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '\r')" = $'argc:2\narg:<value with spaces>\narg:<--json>' ]
}

@test "recovery ignores malformed manifests" {
  make_plugin '1.0.0+codex.20260906194500'
  mkdir -p "$cache/2.0.0+codex.20260907194500/.claude-plugin" "$cache/2.0.0+codex.20260907194500/scripts"
  printf '{broken' > "$cache/2.0.0+codex.20260907194500/.claude-plugin/plugin.json"
  : > "$cache/2.0.0+codex.20260907194500/scripts/amir-loop-status.ps1"

  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$launcher" status -CacheRoot "$(cygpath -w "$cache")"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '\r')" = '1.0.0+codex.20260906194500' ]
}

@test "recovery rejects an invalid explicit root instead of falling back" {
  mkdir -p "$cache/not-a-plugin"

  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$launcher" status -InstalledRoot "$(cygpath -w "$cache/not-a-plugin")"
  [ "$status" -ne 0 ]
  [[ "$output" == *'explicit Amir Loop root is invalid'* ]]
}

@test "recovery reports an empty cache precisely" {
  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$launcher" status -CacheRoot "$(cygpath -w "$cache")"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No valid Amir Loop installation with a 'status' entrypoint"* ]]
}
