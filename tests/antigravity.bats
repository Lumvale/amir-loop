PLUGIN="$BATS_TEST_DIRNAME/../plugins/amir-loop"

@test "Antigravity plugin exposes its native Stop hook shape" {
  run jq -e '.["amir-loop"].Stop[0]
    | select(.type == "command")
    | select(.command | contains("amir-loop-antigravity.ps1"))' "$PLUGIN/hooks.json"
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
