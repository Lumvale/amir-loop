load helper

@test "native doctor skill routes Windows through PowerShell, never bare bash" {
  skill="$BATS_TEST_DIRNAME/../plugins/amir-loop/skills/amir-loop-doctor/SKILL.md"
  [ -f "$skill" ]
  grep -q 'amir-loop-doctor.ps1' "$skill"
  grep -q 'Do not invoke bare `bash`' "$skill"
  [ -f "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.ps1" ]
}

@test "LumvaleOS skill has native Windows and POSIX entrypoints" {
  skill="$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/skills/configure-lumvaleos/SKILL.md"
  grep -q 'configure-lumvaleos.ps1' "$skill"
  grep -q 'configure-lumvaleos.sh' "$skill"
  [ -f "$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/scripts/configure-lumvaleos.ps1" ]
}

@test "PowerShell policy entrypoint configures once and refuses overwrite" {
  command -v powershell.exe >/dev/null 2>&1 || skip "PowerShell is Windows-only"
  project="$BATS_TEST_TMPDIR/project"
  mkdir -p "$project"
  script=$(cygpath -w "$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/scripts/configure-lumvaleos.ps1")
  project_win=$(cygpath -w "$project")

  run powershell.exe -NoProfile -Command "Set-Location -LiteralPath '$project_win'; & '$script' -Mode preferred"
  [ "$status" -eq 0 ]
  jq -e '.dependencies[0].policy == "preferred"' "$project/.claude/amir-loop-dependencies.json" >/dev/null

  run powershell.exe -NoProfile -Command "Set-Location -LiteralPath '$project_win'; & '$script' -Mode required"
  [ "$status" -ne 0 ]
  jq -e '.dependencies[0].policy == "preferred"' "$project/.claude/amir-loop-dependencies.json" >/dev/null
}

@test "PowerShell policy entrypoint refuses a selected non-Workspace" {
  command -v powershell.exe >/dev/null 2>&1 || skip "PowerShell is Windows-only"
  project="$BATS_TEST_TMPDIR/not-a-workspace"
  mkdir -p "$project"
  script=$(cygpath -w "$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/scripts/configure-lumvaleos.ps1")
  project_win=$(cygpath -w "$project")

  run env AMIR_LOOP_WORKSPACE_ROOT="$project_win" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script"
  [ "$status" -eq 2 ]
  [ ! -e "$project/.claude/amir-loop-dependencies.json" ]
}

@test "PowerShell doctor bypasses a System32 bash first on PATH" {
  command -v powershell.exe >/dev/null 2>&1 || skip "PowerShell is Windows-only"
  script=$(cygpath -w "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.ps1")
  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script" -PrintJq
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'jq-windows-amd64.exe'
}

@test "PowerShell doctor forwards the shared JSON contract" {
  command -v powershell.exe >/dev/null 2>&1 || skip "PowerShell is Windows-only"
  script=$(cygpath -w "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.ps1")
  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script" -Json
  [ "$status" -eq 0 ]
  echo "$output" | tr -d '\r' | jq -e '
    .schema_version == 1 and .plugin.name == "amir-loop" and
    .summary.total == (.checks | length)
  ' >/dev/null
}

@test "PowerShell and POSIX doctors expose the same semantic JSON schema" {
  command -v powershell.exe >/dev/null 2>&1 || skip "PowerShell is Windows-only"
  posix="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.sh"
  script=$(cygpath -w "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.ps1")
  posix_json=$(bash "$posix" --json)
  run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$script" --json
  [ "$status" -eq 0 ]
  powershell_json=$(echo "$output" | tr -d '\r')
  [ "$(echo "$posix_json" | jq -c '[.schema_version, .plugin.name, .checks | map([.severity,.code])]')" = \
    "$(echo "$powershell_json" | jq -c '[.schema_version, .plugin.name, .checks | map([.severity,.code])]')" ]
}

@test "PowerShell status bypasses System32 bash and forwards a session as argv" {
  command -v powershell.exe >/dev/null 2>&1 || skip "PowerShell is Windows-only"
  project="$BATS_TEST_TMPDIR/project with spaces"
  mkdir -p "$project/.claude/.amir-loop-worktree-claim"
  printf -- '---\nsession_id: "session-one"\niteration: 3\nmax_iterations: 9\ncompletion_promise: "DONE"\nstarted_at: "2026-09-06T00:00:00Z"\n---\n' > "$project/.claude/amir-loop.session-one.local.md"
  printf 'session-one\n' > "$project/.claude/.amir-loop-worktree-claim/owner"
  printf '100\n' > "$project/.claude/.amir-loop-worktree-claim/heartbeat"
  script=$(cygpath -w "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-status.ps1")
  project_win=$(cygpath -w "$project")

  run powershell.exe -NoProfile -Command "Set-Location -LiteralPath '$project_win'; \$env:AMIR_LOOP_CLAIM_NOW='105'; & '$script' -Json -Session 'session-one'"

  [ "$status" -eq 0 ]
  echo "$output" | tr -d '\r' | jq -e '.selection.source == "argument" and .selection.session_id == "session-one" and .reconciliation.state == "armed-claimed"' >/dev/null
}
