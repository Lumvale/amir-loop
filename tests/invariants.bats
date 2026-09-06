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

@test "bare completion token is rejected across legacy host transcript shapes" {
  for shape in claude antigravity vscode; do
    arm_state 1 10
    if [ "$shape" = "vscode" ]; then
      printf '%s\n' '{"type":"assistant.message","data":{"content":"<promise>AMIR LOOP COMPLETE</promise>"}}' > "$BATS_TEST_TMPDIR/t.jsonl"
    else
      printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"<promise>AMIR LOOP COMPLETE</promise>"}]}}' > "$BATS_TEST_TMPDIR/t.jsonl"
    fi
    TRANSCRIPT="$BATS_TEST_TMPDIR/t.jsonl"
    run run_hook
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.decision')" = "block" ]
    [ -f "$TEST_STATE" ]
    rm -rf "$BATS_TEST_TMPDIR/.claude"
  done
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
  echo "$reason" | grep -q "merely because the"
  echo "$reason" | grep -q "primary goal is exhausted"
  echo "$reason" | grep -q "reader advertised"
  ! echo "$reason" | grep -Eq "LumvaleOS|fleet\.await_run"
  reason_bytes=$(printf '%s' "$reason" | wc -c | tr -d '[:space:]')
  [ "$reason_bytes" -le 2048 ]
  ! echo "$reason" | grep -q "Do the work."
}

@test "repeat continuation stays within the byte budget on Codex" {
  arm_state 5 10
  run run_codex_hook
  [ "$status" -eq 0 ]
  reason=$(echo "$output" | jq -r '.reason')
  reason_bytes=$(printf '%s' "$reason" | wc -c | tr -d '[:space:]')
  [ "$reason_bytes" -le 2048 ]
  echo "$reason" | grep -q "applicable Workspace or product policy"
  ! echo "$reason" | grep -Eq "LumvaleOS|fleet\.await_run"
  [ "$(echo "$output" | jq -r '.hookSpecificOutput // empty')" = "" ]
}

@test "standing orders are gated by workspace and current-goal relevance" {
  mkdir -p "$BATS_TEST_TMPDIR/fleet/.claude" "$BATS_TEST_TMPDIR/fleet/repo"
  echo "Pick the oldest board story immediately." \
    > "$BATS_TEST_TMPDIR/fleet/.claude/amir-loop-principles.md"
  cp "$FIXTURES/vscode-copilot.jsonl" "$BATS_TEST_TMPDIR/t.jsonl"

  run bash -c "printf '{\"cwd\":\"$BATS_TEST_TMPDIR/fleet/repo\",\"session_id\":\"s1\",\"transcript_path\":\"$BATS_TEST_TMPDIR/t.jsonl\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]

  state="$BATS_TEST_TMPDIR/fleet/repo/.claude/amir-loop.s1.local.md"
  grep -q "direct user request.*PRIMARY GOAL" "$state"
  grep -q "## Standing-order applicability" "$state"
  grep -q "governance inputs, not" "$state"
  grep -q "automatic scope" "$state"
  grep -q "active workspace enables that domain" "$state"
  grep -q "current goal is materially relevant" "$state"
  grep -q "trigger or reconciliation condition" "$state"
  grep -q "required environment and capabilities" "$state"
  grep -q "expand or pre-empt the user's goal" "$state"
  grep -q "safety and authority requirements" "$state"
  grep -q "ancestor directory is not evidence" "$state"
  grep -q "required dependency's preflight remains mandatory" "$state"
  grep -q "actions exposed by that dependency remain subject" "$state"
  grep -q "does not unlock unrelated fallback work" "$state"
  principles_line=$(grep -n "Pick the oldest board story" "$state" | cut -d: -f1)
  precedence_line=$(grep -n "## Goal precedence" "$state" | cut -d: -f1)
  [ "$precedence_line" -gt "$principles_line" ]
  grep -q "## Related-work reconciliation" "$state"
  grep -q "CONFIRMED DUPLICATE" "$state"
  grep -q "CO-RESOLVABLE" "$state"
  grep -q "RELATED BUT DISTINCT" "$state"
  grep -q "## Shared-worktree safety" "$state"
  grep -q "not proof that this session owns it exclusively" "$state"
  grep -q "stage only the exact paths" "$state"
  grep -q "inspect the staged diff and stat" "$state"
  shared_line=$(grep -n "## Shared-worktree safety" "$state" | cut -d: -f1)
  context_line=$(grep -n "## Context durability" "$state" | cut -d: -f1)
  [ "$shared_line" -lt "$context_line" ]
}

@test "selected LumvaleOS Workspace policy wins and records its hash" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude" "$BATS_TEST_TMPDIR/ws/.lumvaleos"
  echo "WRONG ANCESTOR POLICY" > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  echo "workspace: {id: ws-lumvale}" > "$BATS_TEST_TMPDIR/ws/workspace.yaml"
  cat > "$BATS_TEST_TMPDIR/ws/.lumvaleos/amir-loop-principles.md" <<'EOF'
<!-- lumvaleos-agent-policy: 1 workspace=ws-lumvale hash=sha256:abc123 -->
RIGHT WORKSPACE POLICY
Use product-specific capability fleet.await_run for compact immutable run evidence.
EOF
  use_fixture vscode-copilot.jsonl

  AMIR_LOOP_WORKSPACE_ROOT="$BATS_TEST_TMPDIR/ws" run run_hook

  [ "$status" -eq 0 ]
  grep -q 'RIGHT WORKSPACE POLICY' "$TEST_STATE"
  grep -q 'fleet.await_run' "$TEST_STATE"
  grep -q 'workspace=ws-lumvale hash=sha256:abc123' "$TEST_STATE"
  ! grep -q 'WRONG ANCESTOR POLICY' "$TEST_STATE"
}

@test "selected Workspace without a projection never inherits ancestor policy" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude" "$BATS_TEST_TMPDIR/ws"
  echo "WRONG ANCESTOR POLICY" > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  echo "workspace: {id: ws-home}" > "$BATS_TEST_TMPDIR/ws/workspace.yaml"
  use_fixture vscode-copilot.jsonl

  AMIR_LOOP_WORKSPACE_ROOT="$BATS_TEST_TMPDIR/ws" run run_hook

  [ "$status" -eq 0 ]
  grep -q '## Workspace policy status' "$TEST_STATE"
  grep -q 'no rendered Amir Loop policy' "$TEST_STATE"
  ! grep -q 'WRONG ANCESTOR POLICY' "$TEST_STATE"
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
  grep -q "## Standing-order applicability" "$state"
  grep -q "governance inputs, not" "$state"
  principles_line=$(grep -n "Pick the oldest board story" "$state" | cut -d: -f1)
  precedence_line=$(grep -n "## Goal precedence" "$state" | cut -d: -f1)
  [ "$precedence_line" -gt "$principles_line" ]
  grep -q "## Related-work reconciliation" "$state"
  grep -q "Never infer duplication from title similarity alone" "$state"
  grep -q "## Shared-worktree safety" "$state"
  grep -q "not proof that this session owns it exclusively" "$state"
  grep -q "stage only the exact paths" "$state"
  grep -q "inspect the staged diff and stat" "$state"
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

@test "a second session cannot arm in a worktree claimed by the first" {
  use_fixture vscode-copilot.jsonl
  run run_hook
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop.s1.local.md" ]

  run bash -c "jq -n --arg cwd '$BATS_TEST_TMPDIR' --arg tp '$TRANSCRIPT' '{cwd: \$cwd, session_id: \"s2\", transcript_path: \$tp}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/amir-loop.s2.local.md" ]
  grep -q 'session_id: "s1"' "$BATS_TEST_TMPDIR/.claude/amir-loop.s1.local.md"
  grep -q '^s1$' "$BATS_TEST_TMPDIR/.claude/.amir-loop-worktree-claim/owner"
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

@test "promise in the LAST message cannot finish without closeout evidence" {
  arm_state 1 10
  printf '%s\n' \
    '{"type":"assistant.message","data":{"content":"<promise>AMIR LOOP COMPLETE</promise>"},"id":1,"timestamp":1}' \
    > "$BATS_TEST_TMPDIR/t.jsonl"
  TRANSCRIPT="$BATS_TEST_TMPDIR/t.jsonl"
  run run_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  [ -f "$TEST_STATE" ]
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

@test "Codex bare completion promise reproducer is rejected without parsing a transcript" {
  arm_state 1 10
  CODEX_LAST_ASSISTANT="verified <promise>AMIR LOOP COMPLETE</promise>" run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  [ -f "$TEST_STATE" ]
  echo "$output" | jq -r '.reason' | grep -q 'promise token is not evidence'
}

@test "validated closeout requires a second nonce-bound confirmation" {
  arm_state 1 10
  closeout='<amir-loop-closeout>{"version":1,"direct_goal_exhausted":true,"continuation_escape":false,"actionable_items":[],"pending":{"pr":false,"test":false,"migration":false,"deployment":false,"cutover":false,"follow_up":false,"verification":false},"dependencies":[{"id":"lumvaleos","required":true,"status":"healthy","checked_at":"2026-08-31T00:00:00Z","evidence_id":"preflight:ok"}],"playbook":{"status":"none","dispatcher_terminal":true}}</amir-loop-closeout>'
  CODEX_LAST_ASSISTANT="$closeout" run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  nonce=$(jq -r '.nonce' "$BATS_TEST_TMPDIR/.claude/.amir-loop-closeout-s1.json")
  [ -n "$nonce" ]

  CODEX_LAST_ASSISTANT="<amir-loop-confirm>$nonce</amir-loop-confirm><promise>AMIR LOOP COMPLETE</promise>" run run_codex_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$TEST_STATE" ]
  [ "$(cat "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1")" = "turn:turn-1" ]
}

@test "Claude and VS Code transcript shapes use the same two-phase closeout" {
  closeout='<amir-loop-closeout>{"version":1,"direct_goal_exhausted":true,"continuation_escape":false,"actionable_items":[],"pending":{"pr":false,"test":false,"migration":false,"deployment":false,"cutover":false,"follow_up":false,"verification":false},"dependencies":[],"playbook":{"status":"none","dispatcher_terminal":true}}</amir-loop-closeout>'
  for shape in claude vscode; do
    rm -rf "$BATS_TEST_TMPDIR/.claude"
    arm_state 1 10
    if [ "$shape" = "claude" ]; then
      jq -nc --arg value "$closeout" '{message:{role:"assistant",content:[{type:"text",text:$value}]}}' > "$BATS_TEST_TMPDIR/t.jsonl"
    else
      jq -nc --arg value "$closeout" '{type:"assistant.message",data:{content:$value}}' > "$BATS_TEST_TMPDIR/t.jsonl"
    fi
    TRANSCRIPT="$BATS_TEST_TMPDIR/t.jsonl"
    run run_hook
    [ "$(echo "$output" | jq -r '.decision')" = "block" ]
    nonce=$(jq -r '.nonce' "$BATS_TEST_TMPDIR/.claude/.amir-loop-closeout-s1.json")
    confirmation="<amir-loop-confirm>$nonce</amir-loop-confirm><promise>AMIR LOOP COMPLETE</promise>"
    if [ "$shape" = "claude" ]; then
      jq -nc --arg value "$confirmation" '{message:{role:"assistant",content:[{type:"text",text:$value}]}}' > "$BATS_TEST_TMPDIR/t.jsonl"
    else
      jq -nc --arg value "$confirmation" '{type:"assistant.message",data:{content:$value}}' > "$BATS_TEST_TMPDIR/t.jsonl"
    fi
    run run_hook
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -f "$TEST_STATE" ]
  done
}

@test "closeout and promise in one escape response cannot skip phase two" {
  arm_state 1 10
  closeout='<amir-loop-closeout>{"version":1,"direct_goal_exhausted":true,"continuation_escape":false,"actionable_items":[],"pending":{"pr":false,"test":false,"migration":false,"deployment":false,"cutover":false,"follow_up":false,"verification":false},"dependencies":[],"playbook":{"status":"none","dispatcher_terminal":true}}</amir-loop-closeout>'
  CODEX_LAST_ASSISTANT="$closeout<promise>AMIR LOOP COMPLETE</promise>" run run_codex_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  [ -f "$TEST_STATE" ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-closeout-s1.json" ]
}

@test "closeout accepts id-keyed object dependencies in phase one" {
  arm_state 1 10
  closeout='<amir-loop-closeout>{"version":1,"direct_goal_exhausted":true,"continuation_escape":false,"actionable_items":[],"pending":{"pr":false,"test":false,"migration":false,"deployment":false,"cutover":false,"follow_up":false,"verification":false},"dependencies":{"lumvaleos":{"required":true,"status":"healthy","checked_at":"2026-08-31T00:00:00Z","evidence_id":"preflight:ok"}},"playbook":{"status":"none","dispatcher_terminal":true}}</amir-loop-closeout>'
  CODEX_LAST_ASSISTANT="$closeout" run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  nonce=$(jq -r '.nonce' "$BATS_TEST_TMPDIR/.claude/.amir-loop-closeout-s1.json")
  [ -n "$nonce" ]

  CODEX_LAST_ASSISTANT="<amir-loop-confirm>$nonce</amir-loop-confirm><promise>AMIR LOOP COMPLETE</promise>" run run_codex_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$TEST_STATE" ]
}

@test "closeout accepts governed business-workflow evidence without engineering pending keys" {
  arm_state 1 10
  closeout='<amir-loop-closeout>{"version":1,"direct_goal_exhausted":true,"continuation_escape":false,"actionable_items":[],"pending":{"source_review":false,"reconciliation":false,"approval":null,"follow_up":[]},"workflow":{"profile":"money-documents","status":"completed","evidence":["inventory:money-documents-v1","reconciliation:balanced"]},"dependencies":[],"playbook":{"status":"none","dispatcher_terminal":true}}</amir-loop-closeout>'
  CODEX_LAST_ASSISTANT="$closeout" run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  nonce=$(jq -r '.nonce' "$BATS_TEST_TMPDIR/.claude/.amir-loop-closeout-s1.json")
  [ -n "$nonce" ]
}

@test "completed business workflow requires evidence" {
  arm_state 1 10
  closeout='<amir-loop-closeout>{"version":1,"direct_goal_exhausted":true,"continuation_escape":false,"actionable_items":[],"pending":{"source_review":false},"workflow":{"profile":"money-documents","status":"completed","evidence":[]},"dependencies":[],"playbook":{"status":"none","dispatcher_terminal":true}}</amir-loop-closeout>'
  CODEX_LAST_ASSISTANT="$closeout" run run_codex_hook
  [ "$status" -eq 0 ]
  echo "$output" | jq -r '.reason' | grep -q 'status completed with non-empty evidence'
}

@test "closeout handles multiline JSON format across lines" {
  arm_state 1 10
  closeout=$(cat <<'EOF'
<amir-loop-closeout>
{
  "version": 1,
  "direct_goal_exhausted": true,
  "continuation_escape": false,
  "actionable_items": [],
  "pending": {
    "pr": false,
    "test": false,
    "migration": false,
    "deployment": false,
    "cutover": false,
    "follow_up": false,
    "verification": false
  },
  "dependencies": {
    "lumvaleos": {
      "required": true,
      "healthy": true,
      "checked_at": "2026-08-31T00:00:00Z",
      "evidence_id": "preflight:ok"
    }
  },
  "playbook": {
    "status": "none",
    "dispatcher_terminal": true
  }
}
</amir-loop-closeout>
EOF
)
  CODEX_LAST_ASSISTANT="$closeout" run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  nonce=$(jq -r '.nonce' "$BATS_TEST_TMPDIR/.claude/.amir-loop-closeout-s1.json")
  [ -n "$nonce" ]
}

@test "invalid closeout reports specific clause failure instead of silent fallthrough" {
  arm_state 1 10
  closeout='<amir-loop-closeout>{"version":1,"direct_goal_exhausted":false,"continuation_escape":false,"actionable_items":[],"pending":{"pr":false,"test":false,"migration":false,"deployment":false,"cutover":false,"follow_up":false,"verification":false},"dependencies":[],"playbook":{"status":"none","dispatcher_terminal":true}}</amir-loop-closeout>'
  CODEX_LAST_ASSISTANT="$closeout" run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  reason=$(echo "$output" | jq -r '.reason')
  echo "$reason" | grep -q "Closeout proposal rejected: direct_goal_exhausted must be true"
  ! echo "$reason" | grep -q "Continue the loop - iteration"
  [ ! -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-closeout-s1.json" ]
}


external_blocker_json() {
  jq -nc '{version:1,blocker_kind:"owner-only",blocker_id:"github-app-permission-50",exact_human_action:"Set the GitHub App Actions permission to Read and write and approve the installation update.",evidence_uri:"https://github.com/Lumvale/amir-loop/issues/50",resume_condition:"When the installation permission read-back reports Actions write access.",exhausted_agent_side_alternatives:["Verified the current permission through the GitHub API.","Confirmed the app owner must approve this permission change."],pending_ci:false,remaining_agent_actionable_work:false,actionable_items:[]}'
}

@test "valid external blocker suspends without completion and preserves resume" {
  arm_state 2 10
  marker="<amir-loop-external-blocker>$(external_blocker_json)</amir-loop-external-blocker>"
  CODEX_LAST_ASSISTANT="$marker" run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision // empty')" = "" ]
  [ "$(echo "$output" | jq -r '.systemMessage')" = "Amir Loop suspended | external blocker accepted: github-app-permission-50" ]
  [ -f "$TEST_STATE" ]
  grep -q '^iteration: 2$' "$TEST_STATE"
  blocker_file="$BATS_TEST_TMPDIR/.claude/.amir-loop-external-blocker-s1.json"
  [ "$(jq -r '.blocker_id' "$blocker_file")" = "github-app-permission-50" ]

  CODEX_TURN_ID="turn-1" CODEX_LAST_ASSISTANT="$marker" run run_codex_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]

  CODEX_TURN_ID="turn-2" CODEX_LAST_ASSISTANT="The owner action is now complete." run run_codex_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  grep -q '^iteration: 3$' "$TEST_STATE"
}

@test "external blocker rejects malformed JSON" {
  arm_state 1 10
  CODEX_LAST_ASSISTANT='<amir-loop-external-blocker>{bad json}</amir-loop-external-blocker>' run run_codex_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  echo "$output" | jq -r '.reason' | grep -q 'rejected: malformed JSON object'
  [ -f "$TEST_STATE" ]
}

@test "external blocker rejects missing durable evidence" {
  arm_state 1 10
  blocker=$(external_blocker_json | jq -c 'del(.evidence_uri)')
  CODEX_LAST_ASSISTANT="<amir-loop-external-blocker>$blocker</amir-loop-external-blocker>" run run_codex_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  echo "$output" | jq -r '.reason' | grep -q 'evidence_uri must be a durable https URI'
}

@test "external blocker rejects vague human action" {
  arm_state 1 10
  blocker=$(external_blocker_json | jq -c '.exact_human_action="Please help"')
  CODEX_LAST_ASSISTANT="<amir-loop-external-blocker>$blocker</amir-loop-external-blocker>" run run_codex_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  echo "$output" | jq -r '.reason' | grep -q 'exact_human_action is missing or vague'
}

@test "external blocker rejects pending CI" {
  arm_state 1 10
  blocker=$(external_blocker_json | jq -c '.pending_ci=true')
  CODEX_LAST_ASSISTANT="<amir-loop-external-blocker>$blocker</amir-loop-external-blocker>" run run_codex_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  echo "$output" | jq -r '.reason' | grep -q 'pending scheduled CI is asynchronous promotion evidence'
}

@test "external blocker rejects remaining agent actionable work" {
  arm_state 1 10
  blocker=$(external_blocker_json | jq -c '.remaining_agent_actionable_work=true | .actionable_items=["retry API read"]')
  CODEX_LAST_ASSISTANT="<amir-loop-external-blocker>$blocker</amir-loop-external-blocker>" run run_codex_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  echo "$output" | jq -r '.reason' | grep -q 'remaining agent-actionable work must be exhausted'
}

@test "manual and automatic briefs document the external blocker contract" {
  use_fixture vscode-copilot.jsonl
  run run_hook
  [ "$status" -eq 0 ]
  grep -q 'amir-loop-external-blocker' "$TEST_STATE"
  grep -q 'remaining_agent_actionable_work=false' "$TEST_STATE"

  rm -rf "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-setup.sh" "Wait for an owner-only action"
  [ "$status" -eq 0 ]
  grep -q 'amir-loop-external-blocker' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
  grep -q 'remaining_agent_actionable_work=false' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}

@test "explicit exact-output user contract bypasses closeout ceremony" {
  arm_state 1 10
  jq -n --arg cwd "$BATS_TEST_TMPDIR" --arg prompt "Reply with exactly PASS ONE. Do not use tools." \
    '{cwd:$cwd, session_id:"s1", turn_id:"turn-1", prompt:$prompt}' |
    bash "$HOOK" --observe=user-prompt
  CODEX_LAST_ASSISTANT="PASS ONE" run run_codex_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$TEST_STATE" ]
}

@test "successful LumvaleOS preflight emits environment reachable without prompt content" {
  jq -n --arg cwd "$BATS_TEST_TMPDIR" \
    '{cwd:$cwd,session_id:"s1",turn_id:"turn-1",tool_name:"mcp__lumvaleos__lumvaleos_preflight",tool_response:{overall_status:"ok",secret:"not-copied"}}' |
    bash "$HOOK" --observe=post-tool
  event=$(tail -n 1 "$BATS_TEST_TMPDIR/.lumvaleos/playbook-events.jsonl")
  [ "$(echo "$event" | jq -r '.type')" = "environment.reachable" ]
  [ "$(echo "$event" | jq -r '.data.secret // empty')" = "" ]
  receipt="$BATS_TEST_TMPDIR/.lumvaleos/amir-loop-lumvaleos-transport.json"
  [ "$(jq -r '.transport' "$receipt")" = native-mcp ]
  [ "$(jq -r '.degraded' "$receipt")" = false ]
}

@test "successful knowledge capture emits learning discovered" {
  jq -n --arg cwd "$BATS_TEST_TMPDIR" \
    '{cwd:$cwd,session_id:"s1",turn_id:"turn-1",tool_name:"mcp__lumvaleos__knowledge_capture",tool_response:{isError:false}}' |
    bash "$HOOK" --observe=post-tool
  [ "$(tail -n 1 "$BATS_TEST_TMPDIR/.lumvaleos/playbook-events.jsonl" | jq -r '.type')" = "learning.discovered" ]
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

@test "Bedrock transient errors use the bounded retry path" {
  for signal in ThrottlingException ServiceUnavailableException ModelStreamErrorException ModelTimeoutException "AWS default-chain credential resolve timed out"; do
    rm -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-retry-s1"
    arm_state 1 10
    CODEX_LAST_ASSISTANT="$signal" run run_codex_hook
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.decision')" = "block" ]
    grep -q '^iteration: 1$' "$TEST_STATE"
  done
}

@test "Bedrock retry behavior is identical for Claude and VS Code transcripts" {
  for shape in claude vscode; do
    rm -rf "$BATS_TEST_TMPDIR/.claude"
    arm_state 1 10
    if [ "$shape" = "claude" ]; then
      printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"ThrottlingException"}]}}' > "$BATS_TEST_TMPDIR/t.jsonl"
    else
      printf '%s\n' '{"type":"assistant.message","data":{"content":"ThrottlingException"}}' > "$BATS_TEST_TMPDIR/t.jsonl"
    fi
    TRANSCRIPT="$BATS_TEST_TMPDIR/t.jsonl"
    run run_hook
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.decision')" = "block" ]
    echo "$output" | jq -r '.reason' | grep -q 'transient provider or network error'
    grep -q '^iteration: 1$' "$TEST_STATE"
  done
}

@test "Bedrock authorization and validation errors fail open" {
  for signal in AccessDeniedException ValidationException ResourceNotFoundException; do
    rm -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-retry-s1"
    arm_state 1 10
    CODEX_LAST_ASSISTANT="$signal" run run_codex_hook
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.decision')" = "block" ]
    ! echo "$output" | jq -r '.reason' | grep -q 'transient provider or network error'
    grep -q '^iteration: 2$' "$TEST_STATE"
  done
}

@test "Bedrock runtime profile is included without secrets" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cat > "$BATS_TEST_TMPDIR/.claude/amir-loop-runtime.json" <<'EOF'
{"version":1,"provider":"bedrock","required":true,"region":"ap-southeast-2","model":"arn:aws:bedrock:ap-southeast-2:111122223333:application-inference-profile/example","credential_source":"workload-identity","preflight":"verify status","repair":"restart"}
EOF
  AMIR_LOOP_PROVIDER=bedrock CODEX_LAST_ASSISTANT="work remains" run run_codex_hook
  [ "$status" -eq 0 ]
  grep -q 'provider: bedrock' "$TEST_STATE"
  grep -q 'region: ap-southeast-2' "$TEST_STATE"
  grep -q 'credential source: workload-identity' "$TEST_STATE"
  grep -q 'observed provider activation: bedrock' "$TEST_STATE"
  ! grep -Eqi 'secret|access.key' "$TEST_STATE"
}

@test "required Bedrock runtime profile governs Claude and VS Code equally" {
  for shape in claude vscode; do
    rm -rf "$BATS_TEST_TMPDIR/.claude"
    mkdir -p "$BATS_TEST_TMPDIR/.claude"
    cp "$BATS_TEST_DIRNAME/../templates/runtime/bedrock.json" "$BATS_TEST_TMPDIR/.claude/amir-loop-runtime.json"
    if [ "$shape" = "claude" ]; then
      printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"work remains"}]}}' > "$BATS_TEST_TMPDIR/t.jsonl"
    else
      printf '%s\n' '{"type":"assistant.message","data":{"content":"work remains"}}' > "$BATS_TEST_TMPDIR/t.jsonl"
    fi
    TRANSCRIPT="$BATS_TEST_TMPDIR/t.jsonl"
    AMIR_LOOP_PROVIDER=bedrock run run_hook
    [ "$status" -eq 0 ]
    grep -q 'provider: bedrock' "$TEST_STATE"
    grep -q 'observed provider activation: bedrock' "$TEST_STATE"
    ! grep -Eqi 'AWS_SECRET_ACCESS_KEY[=:]|AWS_BEARER_TOKEN_BEDROCK[=:]|AKIA[0-9A-Z]{16}' "$TEST_STATE"
  done
}

@test "invalid Bedrock runtime profile fails closed in the brief" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '%s\n' '{"version":1,"provider":"bedrock","required":true}' > "$BATS_TEST_TMPDIR/.claude/amir-loop-runtime.json"
  CODEX_LAST_ASSISTANT="work remains" run run_codex_hook
  [ "$status" -eq 0 ]
  grep -q '<amir-loop-blocked>runtime-provider</amir-loop-blocked>' "$TEST_STATE"
}

@test "required Bedrock profile blocks a host-managed activation" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cp "$BATS_TEST_DIRNAME/../templates/runtime/bedrock.json" "$BATS_TEST_TMPDIR/.claude/amir-loop-runtime.json"
  CODEX_LAST_ASSISTANT="work remains" run run_codex_hook
  [ "$status" -eq 0 ]
  grep -q 'observed provider activation: host' "$TEST_STATE"
  grep -q '<amir-loop-blocked>runtime-provider</amir-loop-blocked>' "$TEST_STATE"
}

@test "continuation prompt restores the direct goal after compaction" {
  arm_state 2 10
  CODEX_LAST_ASSISTANT="work remains" run run_codex_hook
  [ "$status" -eq 0 ]
  reason=$(echo "$output" | jq -r '.reason')
  echo "$reason" | grep -qi 'compacted or summarised'
  echo "$reason" | grep -q "summary's suggested next step does not"
}

@test "continuation auto-merges reviewed heads and reserves scheduled CI for promotion evidence" {
  arm_state 2 10
  CODEX_LAST_ASSISTANT="work remains" run run_codex_hook
  [ "$status" -eq 0 ]
  reason=$(echo "$output" | jq -r '.reason')
  [[ "$reason" == *"Do not wait for runner-backed build or test CI"* ]]
  [[ "$reason" == *"local/static checks"* ]]
  [[ "$reason" == *"enable auto-merge"* ]]
  [[ "$reason" == *"Continue the next authorised actionable task"* ]]
  [[ "$reason" == *"reject stale evidence"* ]]
  [[ "$reason" == *"Never release, version or"*"stable successful scheduled build."* ]]
  [[ "$reason" == *"explicitly approved"*"pre-merge exception"* ]]
}

@test "continuation re-applies the standing-order relevance gate" {
  arm_state 2 10
  CODEX_LAST_ASSISTANT="work remains" run run_codex_hook
  [ "$status" -eq 0 ]
  reason=$(echo "$output" | jq -r '.reason')
  echo "$reason" | grep -q 'candidate policy, not automatic scope'
  echo "$reason" | grep -q 'workspace/domain, trigger, capability, non-expansion, safety'
  echo "$reason" | grep -q 'merely because the'
  echo "$reason" | grep -q 'primary goal is exhausted'
  echo "$reason" | grep -q 'otherwise proceed to closeout'
}

@test "durable brief governs learning promotion without self modification" {
  # The telemetry emitter stays in the portable hook; the INSTRUCTION to promote learnings
  # is domain policy and lives in the standing-orders template a project opts into.
  run grep -q 'learning.discovered' "$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/amir-loop-stop.sh"
  [ "$status" -eq 0 ]
  run grep -q 'does not alter priority or authorise self-modification' "$BATS_TEST_DIRNAME/../templates/principles/lumvale-fleet.md"
  [ "$status" -eq 0 ]

  run grep -q 'lumvale-os-workspaces/\*' "$BATS_TEST_DIRNAME/../templates/principles/lumvale-fleet.md"
  [ "$status" -eq 0 ]

  run grep -q "risk-triggered assurance ladder" "$BATS_TEST_DIRNAME/../templates/principles/lumvale-fleet.md"
  [ "$status" -eq 0 ]

  run grep -Fq "AST + call/import code-graph seam" "$BATS_TEST_DIRNAME/../templates/principles/lumvale-fleet.md"
  [ "$status" -eq 0 ]

  run grep -q "richer views are gaps until" "$BATS_TEST_DIRNAME/../templates/principles/lumvale-fleet.md"
  [ "$status" -eq 0 ]

  run grep -q "Formal evidence is bounded evidence" "$BATS_TEST_DIRNAME/../templates/principles/lumvale-fleet.md"
  [ "$status" -eq 0 ]

  run grep -q "BFS state reachability is not transition" "$BATS_TEST_DIRNAME/../templates/principles/lumvale-fleet.md"
  [ "$status" -eq 0 ]

  run grep -q "join SCIP/LSIF semantic indexes" "$BATS_TEST_DIRNAME/../templates/principles/lumvale-fleet.md"
  [ "$status" -eq 0 ]

  run grep -q "production or recurring chaos requires" "$BATS_TEST_DIRNAME/../templates/principles/lumvale-fleet.md"
  [ "$status" -eq 0 ]
}

@test "automatic and manual briefs enforce governed recursive improvement" {
  use_fixture vscode-copilot.jsonl
  run run_hook
  [ "$status" -eq 0 ]
  grep -q '## Governed recursive improvement' "$TEST_STATE"
  grep -q 'Never treat a permission bottleneck' "$TEST_STATE"
  grep -q 'select only declared routing fallbacks' "$TEST_STATE"

  rm -rf "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-setup.sh" "Repair the active integration"
  [ "$status" -eq 0 ]
  grep -q '## Governed recursive improvement' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
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
  # Fails open on purpose: the core arms itself in every session, so a non-zero exit here
  # would error on every turn of an unrelated project.
  local hooks="$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/hooks.json"
  local cmd
  cmd=$(jq -r '.hooks.Stop[0].hooks[0].command' "$hooks")
  run env CLAUDE_PLUGIN_ROOT= PLUGIN_ROOT= CODEX_PLUGIN_ROOT= bash -c "$cmd" </dev/null
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "generic hook command reads the plugin root at runtime on Windows" {
  local hooks="$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/hooks.json"
  local cmd
  cmd=$(jq -r '.hooks.Stop[0].hooks[0].command' "$hooks")

  # The braced form is substituted textually by the host, which would put raw Windows
  # backslashes back into the command. The root must be read from the environment.
  [[ "$cmd" != *'${CLAUDE_PLUGIN_ROOT}'* ]]

  mkdir -p "$BATS_TEST_TMPDIR/root/hooks"
  cat > "$BATS_TEST_TMPDIR/root/hooks/amir-loop-stop.sh" <<'EOF'
#!/usr/bin/env bash
echo REACHED
EOF

  local root="$BATS_TEST_TMPDIR/root"
  if command -v cygpath >/dev/null 2>&1; then
    root=$(cygpath -w "$BATS_TEST_TMPDIR/root")
  fi
  run env CLAUDE_PLUGIN_ROOT="$root" PLUGIN_ROOT= CODEX_PLUGIN_ROOT= bash -c "$cmd" </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "REACHED" ]
}

# --- Portability: the core arms itself in EVERY session, so it must not name a product ------
#
# The LumvaleOS dispatch stanza was hardcoded into both brief builders, so a loop armed in an
# unrelated project was told to call flow.next_due_playbook and pull that product's backlog.
# Standing orders are the opt-in, version-controlled place for anything that sharp; these
# tests keep it there.

@test "portable brief names no product-specific dispatcher or backlog" {
  use_fixture vscode-copilot.jsonl
  run run_hook
  [ "$status" -eq 0 ]
  ! grep -qi 'lumvaleos' "$TEST_STATE"
  ! grep -q 'next_due_playbook' "$TEST_STATE"

  rm -rf "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-setup.sh" "Ship the thing"
  [ "$status" -eq 0 ]
  ! grep -qi 'lumvaleos' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
  ! grep -q 'next_due_playbook' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
  grep -q 'without naming a product or tool' "$BATS_TEST_DIRNAME/../docs/workspace-policy-integration.md"
  grep -q 'without changing the portable Stop hook' "$BATS_TEST_DIRNAME/../docs/workspace-policy-integration.md"
}

@test "a project with no standing orders stays within the direct goal" {
  use_fixture vscode-copilot.jsonl
  run run_hook
  [ "$status" -eq 0 ]
  grep -q '## Goal-scoped continuation' "$TEST_STATE"
  grep -q 'collective of principals and domain experts' "$TEST_STATE"
  grep -q 'Do not invent or' "$TEST_STATE"
  grep -q 'select unrelated backlog work' "$TEST_STATE"
}

@test "standing orders replace goal-scoped continuation rather than stacking with it" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo "PROJECT BACKLOG SENTINEL" > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  use_fixture vscode-copilot.jsonl
  run run_hook
  [ "$status" -eq 0 ]
  grep -q 'PROJECT BACKLOG SENTINEL' "$TEST_STATE"
  ! grep -q '## Goal-scoped continuation' "$TEST_STATE"
}

@test "manual setup applies the same goal-scoped continuation as the auto-armed hook" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-setup.sh" "Ship the thing"
  [ "$status" -eq 0 ]
  grep -q '## Goal-scoped continuation' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"

  rm -rf "$BATS_TEST_TMPDIR/.claude"
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo "PROJECT BACKLOG SENTINEL" > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  run bash "$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-setup.sh" "Ship the thing"
  [ "$status" -eq 0 ]
  grep -q 'PROJECT BACKLOG SENTINEL' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
  ! grep -q '## Goal-scoped continuation' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}
