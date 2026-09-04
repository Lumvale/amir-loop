load helper
DOCTOR="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.sh"

run_observer() {
  local phase="$1"
  local host="$2"
  local model="$3"
  local command="$4"
  jq -n --arg cwd "$BATS_TEST_TMPDIR" --arg session "session-1" \
    --arg turn "turn-7" --arg host "$host" --arg model "$model" \
    --arg command "$command" \
    '{cwd:$cwd, session_id:$session, turn_id:$turn, host:$host, model:$model,
      tool_name:"Bash", tool_input:{command:$command}}' |
    bash "$HOOK" "--observe=$phase"
}

@test "pre-tool observation records host model identity and only a command hash" {
  run run_observer pre-tool codex gpt-5.6-sol 'mkdir C:/safe/place'
  [ "$status" -eq 0 ]

  ledger="$BATS_TEST_TMPDIR/.lumvaleos/agent-actions.jsonl"
  [ -f "$ledger" ]
  [ "$(jq -r '.host_surface' "$ledger")" = "codex" ]
  [ "$(jq -r '.model' "$ledger")" = "gpt-5.6-sol" ]
  [ "$(jq -r '.session_id' "$ledger")" = "session-1" ]
  [ "$(jq -r '.turn_id' "$ledger")" = "turn-7" ]
  [ "$(jq -r '.phase' "$ledger")" = "pre" ]
  [ "$(jq -r '.guard_decision' "$ledger")" = "not-exposed" ]
  [ "$(jq -r '.command_sha256' "$ledger")" != "unknown" ]
  ! grep -q 'mkdir C:/safe/place' "$ledger"
}

@test "Codex is identified from its stable turn and final-message fields" {
  jq -n --arg cwd "$BATS_TEST_TMPDIR" \
    '{cwd:$cwd, session_id:"codex-session", turn_id:"turn-1",
      last_assistant_message:"work remains", model:"gpt-5.6-sol",
      tool_name:"exec_command", tool_input:{cmd:"pwd"}}' |
    bash "$HOOK" '--observe=pre-tool'

  ledger="$BATS_TEST_TMPDIR/.lumvaleos/agent-actions.jsonl"
  [ "$(jq -r '.host_surface' "$ledger")" = "codex" ]
  [ "$(jq -r '.model' "$ledger")" = "gpt-5.6-sol" ]
}

@test "VS Code is identified from the Copilot transcript path without inventing a model" {
  mkdir -p "$BATS_TEST_TMPDIR/GitHub.copilot-chat"
  jq -n --arg cwd "$BATS_TEST_TMPDIR" \
    --arg transcript "$BATS_TEST_TMPDIR/GitHub.copilot-chat/transcript.jsonl" \
    '{cwd:$cwd, session_id:"copilot-session", transcript_path:$transcript,
      tool_name:"Bash", tool_input:{command:"pwd"}}' |
    bash "$HOOK" '--observe=pre-tool'

  ledger="$BATS_TEST_TMPDIR/.lumvaleos/agent-actions.jsonl"
  [ "$(jq -r '.host_surface' "$ledger")" = "vscode-copilot" ]
  [ "$(jq -r '.model' "$ledger")" = "unknown" ]
}

@test "MSYS no-conversion records the declared and materialized drive paths" {
  run run_observer pre-tool vscode-copilot unknown \
    'export MSYS_NO_PATHCONV=1; git worktree add /c/lumvale/worktrees/repo/task branch'
  [ "$status" -eq 0 ]

  ledger="$BATS_TEST_TMPDIR/.lumvaleos/agent-actions.jsonl"
  jq -e '.path_semantics == "msys-no-path-conversion"' "$ledger"
  jq -e '.declared_targets | index("/c/lumvale/worktrees/repo/task") != null' "$ledger"
  jq -e '.materialized_targets | index("C:/c/lumvale/worktrees/repo/task") != null' "$ledger"
  jq -e '.risk == "drive-root-path-materialization"' "$ledger"
}

@test "host and model remain unknown when the host does not expose them" {
  run run_observer pre-tool '' '' 'pwd'
  [ "$status" -eq 0 ]

  ledger="$BATS_TEST_TMPDIR/.lumvaleos/agent-actions.jsonl"
  [ "$(jq -r '.host_surface' "$ledger")" = "unknown" ]
  [ "$(jq -r '.model' "$ledger")" = "unknown" ]
  [ "$(jq -r '.attribution_quality' "$ledger")" = "partial" ]
}

@test "doctor summarizes action provenance without guessing missing model identity" {
  mkdir -p "$BATS_TEST_TMPDIR/.lumvaleos"
  printf '%s\n' \
    '{"schema_version":1,"observed_at":"2026-09-04T00:00:00Z","phase":"pre","host_surface":"codex","model":"gpt-5.6-sol","session_id":"s1","turn_id":"t1","tool_name":"Bash","command_sha256":"sha256:a","declared_targets":[],"materialized_targets":[],"path_semantics":"native","risk":"none","guard_decision":"not-exposed","attribution_quality":"host-and-model"}' \
    '{"schema_version":1,"observed_at":"2026-09-04T00:01:00Z","phase":"pre","host_surface":"vscode-copilot","model":"unknown","session_id":"s2","turn_id":"t2","tool_name":"Bash","command_sha256":"sha256:b","declared_targets":["/c/tmp/x"],"materialized_targets":["C:/c/tmp/x"],"path_semantics":"msys-no-path-conversion","risk":"drive-root-path-materialization","guard_decision":"not-exposed","attribution_quality":"partial"}' \
    > "$BATS_TEST_TMPDIR/.lumvaleos/agent-actions.jsonl"

  cd "$BATS_TEST_TMPDIR"
  run env AMIR_LOOP_PROVENANCE_ROOT="$BATS_TEST_TMPDIR" bash "$DOCTOR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'action provenance: 2 event(s)'
  echo "$output" | grep -q 'host=codex model=gpt-5.6-sol count=1'
  echo "$output" | grep -q 'host=vscode-copilot model=unknown count=1'
  echo "$output" | grep -q 'drive-root-path-materialization.*C:/c/tmp/x'
  echo "$output" | grep -q 'model identity unavailable for 1 event(s); reported as unknown'
}
