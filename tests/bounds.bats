load helper

@test "turn cap reached finishes the loop and writes a marker" {
  use_fixture vscode-copilot.jsonl
  arm_state 10 10
  run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md" ]
  [ -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1" ]
}

@test "iteration increments on continue" {
  use_fixture vscode-copilot.jsonl
  arm_state 3 10
  run run_hook
  grep -q '^iteration: 4$' "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
}

@test "AMIR_LOOP_MAX of 0 or junk clamps to the 1000 default" {
  for v in 0 banana; do
    use_fixture vscode-copilot.jsonl
    AMIR_LOOP_MAX="$v" run run_hook
    grep -q '^max_iterations: 1000$' "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
    rm -rf "$BATS_TEST_TMPDIR/.claude"
  done
}

@test "expired calendar window allows the stop" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo 0 > "$BATS_TEST_TMPDIR/.claude/.amir-loop-campaign"
  AMIR_LOOP_DAYS=1 run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "AMIR_LOOP_DAYS=0 means no deadline" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo 0 > "$BATS_TEST_TMPDIR/.claude/.amir-loop-campaign"
  AMIR_LOOP_DAYS=0 run run_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
}

@test "AMIR_LOOP_UNTIL far in the future permits continuation" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  AMIR_LOOP_UNTIL=2099-01-01 run run_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
}

@test "AMIR_LOOP_UNTIL in the past allows the stop" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  AMIR_LOOP_UNTIL=2000-01-01 run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
