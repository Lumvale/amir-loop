PLUGIN="$BATS_TEST_DIRNAME/../plugins/amir-loop"

require_windows_adapter() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) ;; *) skip "Windows Antigravity adapter" ;; esac
  command -v powershell.exe >/dev/null 2>&1 || skip "PowerShell is unavailable"
  command -v cygpath >/dev/null 2>&1 || skip "cygpath is unavailable"
  ADAPTER=$(cygpath -w "$PLUGIN/hooks/amir-loop-antigravity.ps1")
  case "$BATS_TEST_TMPDIR" in
    [A-Za-z]:/*) WORKSPACE="$BATS_TEST_TMPDIR" ;;
    *) WORKSPACE=$(cygpath -w "$BATS_TEST_TMPDIR") ;;
  esac
}

windows_path() {
  case "$1" in
    [A-Za-z]:/*) printf '%s\n' "$1" ;;
    *) cygpath -w "$1" ;;
  esac
}

run_adapter() {
  local event="$1"
  local payload="$2"
  run bash -c 'printf "%s" "$1" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$2" -Event "$3"' \
    _ "$payload" "$ADAPTER" "$event"
}

arm_antigravity() {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cat > "$BATS_TEST_TMPDIR/.claude/amir-loop.s1.local.md" <<'EOF'
---
active: true
session_id: "s1"
iteration: 1
max_iterations: 10
completion_promise: "AMIR LOOP COMPLETE"
started_at: "2026-08-31T00:00:00Z"
---

Do the work.
EOF
}

@test "Antigravity plugin exposes its native Stop hook shape" {
  run jq -e '.["amir-loop"].Stop[0]
    | select(.type == "command")
    | select(.command | contains("amir-loop-antigravity.ps1"))' "$PLUGIN/hooks.json"
  [ "$status" -eq 0 ]
}

@test "Antigravity plugin exposes native startup and governed post-tool hooks" {
  run jq -e '.["amir-loop"]
    | select(.PreInvocation[0].command | contains("-Event PreInvocation"))
    | select(.PostToolUse | length == 4)
    | select([.PostToolUse[].hooks[0].command] | any(contains("-Event SourceChanged")))
    | select([.PostToolUse[].hooks[0].command] | any(contains("-Event CommandCompleted")))
    | select([.PostToolUse[].hooks[0].command] | any(contains("-Event EnvironmentReachable")))
    | select([.PostToolUse[].hooks[0].command] | any(contains("-Event LearningDiscovered")))' "$PLUGIN/hooks.json"
  [ "$status" -eq 0 ]
}

@test "Antigravity plugin has a root manifest" {
  run jq -r '.name' "$PLUGIN/plugin.json"
  [ "$status" -eq 0 ]
  [ "$output" = "amir-loop" ]
}

@test "Antigravity adapter maps block to continue and fails open" {
  grep -q "Write-StopDecision 'continue'" "$PLUGIN/hooks/amir-loop-antigravity.ps1"
  grep -q "Write-StopDecision 'stop'" "$PLUGIN/hooks/amir-loop-antigravity.ps1"
  grep -q 'workspacePaths' "$PLUGIN/hooks/amir-loop-antigravity.ps1"
  grep -q 'conversationId' "$PLUGIN/hooks/amir-loop-antigravity.ps1"
}

@test "Antigravity PreInvocation preserves exact-output and startup reconciliation" {
  require_windows_adapter
  arm_antigravity
  transcript="$BATS_TEST_TMPDIR/antigravity.jsonl"
  printf '%s\n%s\n' \
    '{"type":"user.message","data":{"content":"Reply with exactly PASS ONE. Do not use tools."}}' \
    '{"type":"assistant.message","data":{"content":"PASS ONE"}}' > "$transcript"
  transcript_win=$(windows_path "$transcript")
  payload=$(jq -nc --arg ws "$WORKSPACE" --arg tp "$transcript_win" \
    '{workspacePaths:[$ws],conversationId:"s1",transcriptPath:$tp,invocationNum:1,modelName:"bedrock"}')

  run_adapter PreInvocation "$payload"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tr -d '\r')" = '{}' ]
  [ -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-exact-output-s1" ]
  [ "$(grep -c '"type":"session.started"' "$BATS_TEST_TMPDIR/.lumvaleos/playbook-events.jsonl")" -eq 1 ]
  [ "$(grep -c '"type":"heartbeat.reconcile"' "$BATS_TEST_TMPDIR/.lumvaleos/playbook-events.jsonl")" -eq 1 ]

  stop_payload=$(jq -nc --arg ws "$WORKSPACE" --arg tp "$transcript_win" \
    '{workspacePaths:[$ws],conversationId:"s1",transcriptPath:$tp,terminationReason:"model_stop",modelName:"bedrock"}')
  run_adapter Stop "$stop_payload"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tr -d '\r' | jq -r '.decision')" = 'stop' ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/amir-loop.s1.local.md" ]
}

@test "Antigravity post-tool adapters emit redacted parity events" {
  require_windows_adapter
  payload=$(jq -nc --arg ws "$WORKSPACE" \
    '{workspacePaths:[$ws],conversationId:"s1",transcriptPath:"",stepIdx:7,modelName:"bedrock"}')
  run_adapter SourceChanged "$payload"
  [ "$status" -eq 0 ]
  failed=$(jq -nc --arg ws "$WORKSPACE" \
    '{workspacePaths:[$ws],conversationId:"s1",transcriptPath:"",stepIdx:8,error:"pytest suite failed; token=must-not-copy",modelName:"bedrock"}')
  run_adapter CommandCompleted "$failed"
  [ "$status" -eq 0 ]
  ok=$(jq -nc --arg ws "$WORKSPACE" \
    '{workspacePaths:[$ws],conversationId:"s1",transcriptPath:"",stepIdx:9,error:"",modelName:"bedrock"}')
  run_adapter EnvironmentReachable "$ok"
  [ "$status" -eq 0 ]
  run_adapter LearningDiscovered "$ok"
  [ "$status" -eq 0 ]

  events="$BATS_TEST_TMPDIR/.lumvaleos/playbook-events.jsonl"
  [ "$(jq -rs '[.[].type] | sort | join(",")' "$events")" = 'environment.reachable,learning.discovered,source.changed,test.failed' ]
  ! grep -q 'must-not-copy' "$events"
}

@test "Antigravity Stop uses Bedrock retries and the two-phase closeout" {
  require_windows_adapter
  arm_antigravity
  payload=$(jq -nc --arg ws "$WORKSPACE" \
    '{workspacePaths:[$ws],conversationId:"s1",transcriptPath:"",error:"ThrottlingException",terminationReason:"error",modelName:"bedrock"}')
  run_adapter Stop "$payload"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | tr -d '\r' | jq -r '.decision')" = 'continue' ]
  grep -q '^iteration: 1$' "$BATS_TEST_TMPDIR/.claude/amir-loop.s1.local.md"

  rm -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-retry-s1"
  transcript="$BATS_TEST_TMPDIR/closeout.jsonl"
  closeout='<amir-loop-closeout>{"version":1,"direct_goal_exhausted":true,"continuation_escape":false,"actionable_items":[],"pending":{"pr":false,"test":false,"migration":false,"deployment":false,"cutover":false,"follow_up":false,"verification":false},"dependencies":[],"playbook":{"status":"none","dispatcher_terminal":true}}</amir-loop-closeout>'
  jq -nc --arg value "$closeout" '{type:"assistant.message",data:{content:$value}}' > "$transcript"
  transcript_win=$(windows_path "$transcript")
  payload=$(jq -nc --arg ws "$WORKSPACE" --arg tp "$transcript_win" \
    '{workspacePaths:[$ws],conversationId:"s1",transcriptPath:$tp,error:"",terminationReason:"model_stop",modelName:"bedrock"}')
  run_adapter Stop "$payload"
  [ "$(printf '%s' "$output" | tr -d '\r' | jq -r '.decision')" = 'continue' ]
  nonce=$(jq -r '.nonce' "$BATS_TEST_TMPDIR/.claude/.amir-loop-closeout-s1.json")
  jq -nc --arg value "<amir-loop-confirm>$nonce</amir-loop-confirm><promise>AMIR LOOP COMPLETE</promise>" \
    '{type:"assistant.message",data:{content:$value}}' > "$transcript"
  run_adapter Stop "$payload"
  [ "$(printf '%s' "$output" | tr -d '\r' | jq -r '.decision')" = 'stop' ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/amir-loop.s1.local.md" ]
}
