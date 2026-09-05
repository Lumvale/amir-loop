@test "native adapter unit contract passes on this host" {
  python_cmd=python3
  command -v "$python_cmd" >/dev/null 2>&1 || python_cmd=python
  run "$python_cmd" "$BATS_TEST_DIRNAME/test_lumvaleos_reconcile.py"
  [ "$status" -eq 0 ]
}

@test "companion plugin wakes on session and prompt activation, never on a timer" {
  hooks="$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/hooks.json"
  jq -e '.hooks.SessionStart and .hooks.UserPromptSubmit' "$hooks"
  ! grep -Eqi 'cron|schedule|Task Scheduler' "$hooks"
}
