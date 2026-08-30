load helper

write_policy() {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cat > "$BATS_TEST_TMPDIR/.claude/amir-loop-dependencies.json" <<EOF
{
  "version": 1,
  "dependencies": [
    {
      "id": "lumvaleos",
      "kind": "mcp",
      "policy": "$1",
      "preflight": "Call LumvaleOS status.",
      "repair": "Enable the MCP and restart."
    }
  ]
}
EOF
}

@test "required dependency is rendered into an auto-armed loop" {
  write_policy required
  CODEX_LAST_ASSISTANT="work remains" run run_codex_hook
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"' >/dev/null
  grep -q 'lumvaleos (mcp, required)' "$TEST_STATE"
  grep -q '<amir-loop-blocked>DEPENDENCY_ID</amir-loop-blocked>' "$TEST_STATE"
}

@test "off dependency is omitted from the active preflight list" {
  write_policy off
  CODEX_LAST_ASSISTANT="work remains" run run_codex_hook
  [ "$status" -eq 0 ]
  ! grep -q 'lumvaleos (mcp, off)' "$TEST_STATE"
}

@test "invalid dependency policy fails closed in the brief" {
  write_policy sometimes
  CODEX_LAST_ASSISTANT="work remains" run run_codex_hook
  [ "$status" -eq 0 ]
  grep -q 'dependency policy.*invalid' "$TEST_STATE"
  grep -q '<amir-loop-blocked>dependency-policy</amir-loop-blocked>' "$TEST_STATE"
}

@test "dependency blocked token pauses without deleting loop state" {
  arm_state 2 20
  CODEX_LAST_ASSISTANT="LumvaleOS is unavailable. <amir-loop-blocked>lumvaleos</amir-loop-blocked>" run run_codex_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$TEST_STATE" ]
  [ -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1" ]
  grep -q '^iteration: 2$' "$TEST_STATE"
}

@test "a new human turn resumes a dependency-blocked loop" {
  arm_state 2 20
  CODEX_TURN_ID="turn-1" CODEX_LAST_ASSISTANT="<amir-loop-blocked>lumvaleos</amir-loop-blocked>" run run_codex_hook
  [ -f "$TEST_STATE" ]

  CODEX_TURN_ID="turn-2" CODEX_LAST_ASSISTANT="LumvaleOS preflight succeeded" run run_codex_hook
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"' >/dev/null
  grep -q '^iteration: 3$' "$TEST_STATE"
}

@test "doctor reports valid and invalid dependency policy" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  write_policy preferred
  cd "$BATS_TEST_TMPDIR"
  run bash "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'dependency lumvaleos: preferred'

  write_policy invalid
  run bash "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.sh"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'FAIL: dependencies: invalid policy'
}

@test "LumvaleOS companion configures once and never overwrites" {
  cd "$BATS_TEST_TMPDIR"
  script="$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/scripts/configure-lumvaleos.sh"
  run bash "$script" preferred
  [ "$status" -eq 0 ]
  jq -e '.dependencies[0].policy == "preferred"' .claude/amir-loop-dependencies.json >/dev/null

  run bash "$script" required
  [ "$status" -eq 1 ]
  jq -e '.dependencies[0].policy == "preferred"' .claude/amir-loop-dependencies.json >/dev/null
}

@test "manual setup renders the same dependency preflight contract" {
  write_policy required
  cd "$BATS_TEST_TMPDIR"
  setup_script="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-setup.sh"
  run bash "$setup_script" "Finish the direct task" --max-iterations 10
  [ "$status" -eq 0 ]
  grep -q 'lumvaleos (mcp, required)' .claude/amir-loop.pending.local.md
  grep -q '<amir-loop-blocked>DEPENDENCY_ID</amir-loop-blocked>' .claude/amir-loop.pending.local.md
}
