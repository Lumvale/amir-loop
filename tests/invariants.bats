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
  [ ! -f "$TEST_STATE" ]
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
  [ ! -f "$TEST_STATE" ]
  rm -f "$BATS_TEST_TMPDIR/transcript.jsonl"
  rm -rf "$BATS_TEST_TMPDIR/.claude"
}

@test "principles are inherited from a grandparent .claude directory" {
  mkdir -p "$BATS_TEST_TMPDIR/fleet/.claude" "$BATS_TEST_TMPDIR/fleet/repo/sub"
  echo "FLEET STANDING ORDERS SENTINEL" \
    > "$BATS_TEST_TMPDIR/fleet/.claude/amir-loop-principles.md"
  cp "$FIXTURES/vscode-copilot.jsonl" "$BATS_TEST_TMPDIR/t.jsonl"
  run bash -c "printf '{\"cwd\":\"$BATS_TEST_TMPDIR/fleet/repo/sub\",\"session_id\":\"s1\",\"transcript_path\":\"$BATS_TEST_TMPDIR/t.jsonl\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  grep -q "FLEET STANDING ORDERS SENTINEL" \
    "$BATS_TEST_TMPDIR/fleet/repo/sub/.claude/amir-loop.s1.local.md"
}

@test "principles resolution climbs ancestors only, never siblings" {
  mkdir -p "$BATS_TEST_TMPDIR/decoy/.claude" "$BATS_TEST_TMPDIR/work"
  echo "DECOY PRINCIPLES MUST NOT BE LOADED" \
    > "$BATS_TEST_TMPDIR/decoy/.claude/amir-loop-principles.md"
  cp "$FIXTURES/vscode-copilot.jsonl" "$BATS_TEST_TMPDIR/t.jsonl"
  run bash -c "printf '{\"cwd\":\"$BATS_TEST_TMPDIR/work\",\"session_id\":\"s1\",\"transcript_path\":\"$BATS_TEST_TMPDIR/t.jsonl\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  grep -q "Work as a collective of principal engineers" \
    "$BATS_TEST_TMPDIR/work/.claude/amir-loop.s1.local.md"
  ! grep -q "DECOY PRINCIPLES MUST NOT BE LOADED" \
    "$BATS_TEST_TMPDIR/work/.claude/amir-loop.s1.local.md"
}

@test "iteration 1 sends the full brief; iteration 2 sends only the pointer" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  run run_hook
  echo "$output" | jq -r '.reason' | grep -q "Do the work."

  arm_state 5 10
  run run_hook
  reason=$(echo "$output" | jq -r '.reason')
  echo "$reason" | grep -q "Re-read that file"
  echo "$reason" | grep -q "Continue the DIRECT USER REQUEST"
  echo "$reason" | grep -q "fallback work only after the primary goal"
  ! echo "$reason" | grep -q "Do the work."
}

@test "standing-order backlog is explicitly subordinate to the direct goal" {
  mkdir -p "$BATS_TEST_TMPDIR/fleet/.claude" "$BATS_TEST_TMPDIR/fleet/repo"
  echo "Pick the oldest board story immediately." \
    > "$BATS_TEST_TMPDIR/fleet/.claude/amir-loop-principles.md"
  cp "$FIXTURES/vscode-copilot.jsonl" "$BATS_TEST_TMPDIR/t.jsonl"

  run bash -c "printf '{\"cwd\":\"$BATS_TEST_TMPDIR/fleet/repo\",\"session_id\":\"s1\",\"transcript_path\":\"$BATS_TEST_TMPDIR/t.jsonl\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]

  state="$BATS_TEST_TMPDIR/fleet/repo/.claude/amir-loop.s1.local.md"
  grep -q "direct user request.*PRIMARY GOAL" "$state"
  grep -q "backlog rules are FALLBACK WORK" "$state"
  principles_line=$(grep -n "Pick the oldest board story" "$state" | cut -d: -f1)
  precedence_line=$(grep -n "## Goal precedence" "$state" | cut -d: -f1)
  [ "$precedence_line" -gt "$principles_line" ]
  grep -q "## Related-work reconciliation" "$state"
  grep -q "CONFIRMED DUPLICATE" "$state"
  grep -q "CO-RESOLVABLE" "$state"
  grep -q "RELATED BUT DISTINCT" "$state"
}

@test "manual setup gives its explicit prompt precedence over standing orders" {
  setup_script="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-setup.sh"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo "Pick the oldest board story immediately." \
    > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  cd "$BATS_TEST_TMPDIR"

  run bash "$setup_script" "Finish the direct incident repair first"
  [ "$status" -eq 0 ]
  state="$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
  grep -q "The explicit prompt above is the PRIMARY GOAL" "$state"
  principles_line=$(grep -n "Pick the oldest board story" "$state" | cut -d: -f1)
  precedence_line=$(grep -n "## Goal precedence" "$state" | cut -d: -f1)
  [ "$precedence_line" -gt "$principles_line" ]
  grep -q "## Related-work reconciliation" "$state"
  grep -q "Never infer duplication from title similarity alone" "$state"
}

@test "continuation keeps related-work search bounded inside the direct goal" {
  use_fixture vscode-copilot.jsonl
  arm_state 5 10
  run run_hook
  [ "$status" -eq 0 ]
  reason=$(echo "$output" | jq -r '.reason')
  echo "$reason" | grep -q "BOUNDED RELATED-WORK SWEEP"
  echo "$reason" | grep -q "Consolidate only confirmed duplicates"
  echo "$reason" | grep -q "link but preserve related-distinct items"
  echo "$reason" | grep -q "do not use this sweep to switch to general backlog"
}

@test "a legacy project-wide loop cannot take over a new session" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cat > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md" <<EOF
---
active: true
iteration: 3
max_iterations: 20
completion_promise: "AMIR LOOP COMPLETE"
---

LEGACY OLDEST-BOARD GOAL MUST NOT LEAK
EOF
  use_fixture vscode-copilot.jsonl

  run run_hook
  [ "$status" -eq 0 ]
  [ -f "$TEST_STATE" ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md" ]
  ! echo "$output" | grep -q "LEGACY OLDEST-BOARD GOAL MUST NOT LEAK"
}

@test "concurrent sessions receive independent loop state" {
  use_fixture vscode-copilot.jsonl
  run run_hook
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop.s1.local.md" ]

  run bash -c "jq -n --arg cwd '$BATS_TEST_TMPDIR' --arg tp '$TRANSCRIPT' '{cwd: \$cwd, session_id: \"s2\", transcript_path: \$tp}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop.s2.local.md" ]
  grep -q 'session_id: "s1"' "$BATS_TEST_TMPDIR/.claude/amir-loop.s1.local.md"
  grep -q 'session_id: "s2"' "$BATS_TEST_TMPDIR/.claude/amir-loop.s2.local.md"
}

@test "marker with unchanged human turn count allows the stop" {
  use_fixture vscode-copilot.jsonl
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo 1 > "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1"
  run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "marker below the human turn count re-arms the loop" {
  use_fixture vscode-copilot.jsonl
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo 0 > "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1"
  run run_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1" ]
}

@test "promise in the LAST message finishes the loop" {
  arm_state 1 10
  printf '%s\n' \
    '{"type":"assistant.message","data":{"content":"<promise>AMIR LOOP COMPLETE</promise>"},"id":1,"timestamp":1}' \
    > "$BATS_TEST_TMPDIR/t.jsonl"
  TRANSCRIPT="$BATS_TEST_TMPDIR/t.jsonl"
  run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$TEST_STATE" ]
}

@test "promise in an EARLIER message does not finish the loop" {
  arm_state 1 10
  printf '%s\n%s\n' \
    '{"type":"assistant.message","data":{"content":"<promise>AMIR LOOP COMPLETE</promise>"},"id":1,"timestamp":1}' \
    '{"type":"assistant.message","data":{"content":"actually there is more to do"},"id":2,"timestamp":2}' \
    > "$BATS_TEST_TMPDIR/t.jsonl"
  TRANSCRIPT="$BATS_TEST_TMPDIR/t.jsonl"
  run run_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
}

@test "--claude-code stands down in a copilot-chat session" {
  use_fixture_as_copilot vscode-copilot.jsonl
  arm_state 1 10
  run run_hook --claude-code
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "--claude-code never auto-arms when no state exists" {
  use_fixture claude-code.jsonl
  run run_hook --claude-code
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$TEST_STATE" ]
}

@test "AMIR_LOOP_AUTOARM=0 continues an existing loop but starts none" {
  use_fixture claude-code.jsonl
  AMIR_LOOP_AUTOARM=0 run run_hook
  [ -z "$output" ]
  arm_state 1 10
  AMIR_LOOP_AUTOARM=0 run run_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
}

@test "Codex continues from last_assistant_message without parsing a transcript" {
  arm_state 1 10
  CODEX_LAST_ASSISTANT="there is more work" run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput // empty')" = "" ]
}

@test "Codex completion promise finishes without parsing a transcript" {
  arm_state 1 10
  CODEX_LAST_ASSISTANT="verified <promise>AMIR LOOP COMPLETE</promise>" run run_codex_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$TEST_STATE" ]
  [ "$(cat "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1")" = "turn:turn-1" ]
}

@test "Codex completion marker suppresses re-arm in the completed turn" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo "turn:turn-1" > "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1"
  CODEX_TURN_ID="turn-1" run run_codex_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$TEST_STATE" ]
}

@test "Codex completion marker re-arms on a new user turn" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo "turn:turn-1" > "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1"
  CODEX_TURN_ID="turn-2" run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1" ]
}

@test "transient provider failure retries without consuming an iteration" {
  arm_state 1 10
  CODEX_LAST_ASSISTANT="Sorry, your request failed. Error Code: net::ERR_INCOMPLETE_CHUNKED_ENCODING" \
    run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  echo "$output" | jq -r '.reason' | grep -q "transient provider or network error"
  grep -q '^iteration: 1$' "$TEST_STATE"
  [ "$(cat "$BATS_TEST_TMPDIR/.claude/.amir-loop-retry-s1")" = "1" ]
}

@test "transient retry budget fails open after the configured limit" {
  arm_state 1 10
  AMIR_LOOP_RETRY_MAX=1 CODEX_LAST_ASSISTANT="ERR_INCOMPLETE_CHUNKED_ENCODING" run run_codex_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  AMIR_LOOP_RETRY_MAX=1 CODEX_LAST_ASSISTANT="ERR_INCOMPLETE_CHUNKED_ENCODING" run run_codex_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-retry-s1" ]
}

@test "common transport error codes use the bounded retry path" {
  for signal in ERR_EMPTY_RESPONSE ERR_CONNECTION_RESET ECONNRESET ETIMEDOUT "fetch failed"; do
    rm -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-retry-s1"
    arm_state 1 10
    CODEX_LAST_ASSISTANT="$signal" run run_codex_hook
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.decision')" = "block" ]
    grep -q '^iteration: 1$' "$TEST_STATE"
  done
}

@test "continuation prompt restores the direct goal after compaction" {
  arm_state 2 10
  CODEX_LAST_ASSISTANT="work remains" run run_codex_hook
  [ "$status" -eq 0 ]
  reason=$(echo "$output" | jq -r '.reason')
  echo "$reason" | grep -qi 'compacted or summarised'
  echo "$reason" | grep -q "summary's suggested next step does not"
}

@test "Codex Windows hook expands PLUGIN_ROOT with PowerShell syntax" {
  local hooks="$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/hooks.json"
  run jq -r '.hooks.Stop[0].hooks[0].commandWindows' "$hooks"
  [ "$status" -eq 0 ]
  [[ "$output" == *'$env:PLUGIN_ROOT'* ]]
  [[ "$output" != *'%PLUGIN_ROOT%'* ]]
}

@test "generic hook command reads Codex plugin root at runtime" {
  local hooks="$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/hooks.json"
  run jq -r '.hooks.Stop[0].hooks[0].command' "$hooks"
  [ "$status" -eq 0 ]
  [[ "$output" == *'CODEX_PLUGIN_ROOT'* ]]
  [[ "$output" != *'${CLAUDE_PLUGIN_ROOT}'* ]]
}

@test "generic hook launcher fails open when no plugin root is provided" {
  local hooks="$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/hooks.json"
  run jq -r '.hooks.Stop[0].hooks[0].command' "$hooks"
  [ "$status" -eq 0 ]
  [[ "$output" == *'printenv CLAUDE_PLUGIN_ROOT PLUGIN_ROOT CODEX_PLUGIN_ROOT'* ]]
  [[ "$output" != *'exec bash'* ]]
}

@test "generic hook command reads the plugin root at runtime on Windows" {
  local hooks="$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/hooks.json"
  run jq -r '.hooks.Stop[0].hooks[0].command' "$hooks"
  [ "$status" -eq 0 ]
  [[ "$output" == *'printenv CLAUDE_PLUGIN_ROOT PLUGIN_ROOT CODEX_PLUGIN_ROOT'* ]]
  [[ "$output" == *'bash {}/hooks/amir-loop-stop.sh'* ]]
  [[ "$output" != *'${CLAUDE_PLUGIN_ROOT}'* ]]
}
