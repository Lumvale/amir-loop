load helper

setup() {
  command -v powershell.exe >/dev/null 2>&1 || skip "PowerShell is Windows-only"
  setup_script=$(cygpath -w "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-setup.ps1")
  init_script=$(cygpath -w "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-init.ps1")
  project="$BATS_TEST_TMPDIR/project with spaces"
  mkdir -p "$project"
}

@test "native setup bypasses WSL and forwards the prompt as one argv item" {
  cd "$project"
  prompt='Fix $(echo INJECTED) #42 --max-iterations 7'

  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$setup_script" -Prompt "$prompt"

  [ "$status" -eq 0 ]
  [ -f "$project/.claude/amir-loop.pending.local.md" ]
  grep -Fq 'Fix $(echo INJECTED) #42' "$project/.claude/amir-loop.pending.local.md"
  grep -q '^max_iterations: 7$' "$project/.claude/amir-loop.pending.local.md"
  [[ "$output" != *INJECTED$'\n'* ]]
}

@test "native init creates the packaged template then preserves an existing file" {
  template="$BATS_TEST_DIRNAME/../plugins/amir-loop/templates/principles/lumvale-fleet.md"

  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$init_script" -ProjectRoot "$(cygpath -w "$project")"
  [ "$status" -eq 0 ]
  cmp "$template" "$project/.claude/amir-loop-principles.md"

  printf 'OWNER STANDING ORDER\n' > "$project/.claude/amir-loop-principles.md"
  before=$(sha256sum "$project/.claude/amir-loop-principles.md")
  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$init_script" -ProjectRoot "$(cygpath -w "$project")"
  [ "$status" -eq 0 ]
  [[ "$output" == *'OWNER STANDING ORDER'* ]]
  [ "$before" = "$(sha256sum "$project/.claude/amir-loop-principles.md")" ]
}

@test "POSIX init has byte parity and preserves an existing file" {
  posix_init="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-init.sh"
  template="$BATS_TEST_DIRNAME/../plugins/amir-loop/templates/principles/lumvale-fleet.md"

  run bash "$posix_init" "$project"
  [ "$status" -eq 0 ]
  cmp "$template" "$project/.claude/amir-loop-principles.md"

  printf 'DO NOT REPLACE\n' > "$project/.claude/amir-loop-principles.md"
  run bash "$posix_init" "$project"
  [ "$status" -eq 0 ]
  [ "$(cat "$project/.claude/amir-loop-principles.md")" = 'DO NOT REPLACE' ]
}

@test "init entrypoints reject a misspelled project root without creating it" {
  missing="$BATS_TEST_TMPDIR/does not exist"

  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$init_script" -ProjectRoot "$(cygpath -w "$missing")"
  [ "$status" -ne 0 ]
  [ ! -e "$missing" ]

  run bash "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-init.sh" "$missing"
  [ "$status" -ne 0 ]
  [ ! -e "$missing" ]
}

@test "packaged and repository principles templates cannot drift" {
  cmp "$BATS_TEST_DIRNAME/../templates/principles/lumvale-fleet.md" \
    "$BATS_TEST_DIRNAME/../plugins/amir-loop/templates/principles/lumvale-fleet.md"
}

@test "start and init command instructions prohibit bare Bash on Windows" {
  start="$BATS_TEST_DIRNAME/../plugins/amir-loop/commands/amir-loop.md"
  init="$BATS_TEST_DIRNAME/../plugins/amir-loop/commands/amir-loop-init.md"
  grep -q 'amir-loop-setup.ps1' "$start"
  grep -q 'amir-loop-init.ps1' "$init"
  grep -q 'Do not invoke bare Bash' "$start"
  grep -q 'Do not invoke bare Bash' "$init"
  grep -q 'amir-loop-setup.ps1' "$BATS_TEST_DIRNAME/../plugins/amir-loop/skills/amir-loop-start/SKILL.md"
  grep -q 'Do not invoke bare `bash`' "$BATS_TEST_DIRNAME/../plugins/amir-loop/skills/amir-loop-start/SKILL.md"
  grep -q 'amir-loop-init.ps1' "$BATS_TEST_DIRNAME/../plugins/amir-loop/skills/amir-loop-init/SKILL.md"
}

@test "version-independent recovery invokes native setup with prompt boundaries intact" {
  launcher=$(cygpath -w "$BATS_TEST_DIRNAME/../scripts/amir-loop-current.ps1")
  cache="$BATS_TEST_TMPDIR/cache"
  root="$cache/1.0.0+codex.20260906223000"
  mkdir -p "$root/.claude-plugin" "$root/scripts"
  printf '{"name":"amir-loop","version":"1.0.0"}\n' > "$root/.claude-plugin/plugin.json"
  cat > "$root/scripts/amir-loop-setup.ps1" <<'EOF'
param([string]$Prompt)
Write-Output "prompt:<$Prompt>"
EOF

  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$launcher" setup \
    -CacheRoot "$(cygpath -w "$cache")" -Prompt 'value with spaces # and $(text)'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '\r')" = 'prompt:<value with spaces # and $(text)>' ]
}
