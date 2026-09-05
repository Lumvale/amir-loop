@test "native adapter unit contract passes on this host" {
  run python "$BATS_TEST_DIRNAME/test_lumvaleos_reconcile.py"
  [ "$status" -eq 0 ]
}

@test "companion plugin wakes on session and prompt activation, never on a timer" {
  hooks="$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/hooks.json"
  jq -e '.hooks.SessionStart and .hooks.UserPromptSubmit' "$hooks"
  ! grep -Eqi 'cron|schedule|Task Scheduler' "$hooks"
}
