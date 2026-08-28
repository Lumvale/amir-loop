load helper

@test "emits block in BOTH top-level and hookSpecificOutput shapes" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  run run_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.decision')" = "block" ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "Stop" ]
  [ "$(echo "$output" | jq -r '.reason')" = "$(echo "$output" | jq -r '.hookSpecificOutput.reason')" ]
}

@test "reads the last NON-EMPTY message, multi-line, in both transcript shapes" {
  for f in claude-code.jsonl vscode-copilot.jsonl; do
    use_fixture "$f"
    arm_state 1 10
    run run_hook
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.decision')" = "block" ]
    rm -rf "$BATS_TEST_TMPDIR/.claude"
  done
}
