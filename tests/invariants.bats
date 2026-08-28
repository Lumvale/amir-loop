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

@test "detects total loss of the final message content, both shapes" {
  for f in claude-code.jsonl vscode-copilot.jsonl; do
    use_fixture "$f"
    arm_state 1 10
    run run_hook
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.decision')" = "block" ]
    rm -rf "$BATS_TEST_TMPDIR/.claude"
  done
}

@test "pins multi-line fidelity of the final message via the completion promise, both shapes" {
  local promise="AMIR LOOP COMPLETE"

  arm_state 1 10
  cat > "$BATS_TEST_TMPDIR/transcript.jsonl" <<EOF
{"message":{"role":"user","content":[{"type":"text","text":"start the work"}]}}
{"message":{"role":"assistant","content":[{"type":"text","text":"<promise>$promise</promise>\nand some trailing prose"}]}}
EOF
  TRANSCRIPT="$BATS_TEST_TMPDIR/transcript.jsonl"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md" ]
  rm -f "$BATS_TEST_TMPDIR/transcript.jsonl"
  rm -rf "$BATS_TEST_TMPDIR/.claude"

  arm_state 1 10
  cat > "$BATS_TEST_TMPDIR/transcript.jsonl" <<EOF
{"type":"user.message","data":{"content":"start the work"},"id":1,"timestamp":1}
{"type":"assistant.message","data":{"content":"<promise>$promise</promise>\nand some trailing prose"},"id":2,"timestamp":2}
EOF
  TRANSCRIPT="$BATS_TEST_TMPDIR/transcript.jsonl"
  run run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md" ]
  rm -f "$BATS_TEST_TMPDIR/transcript.jsonl"
  rm -rf "$BATS_TEST_TMPDIR/.claude"
}
