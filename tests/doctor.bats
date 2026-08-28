DOCTOR="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.sh"

# Isolate HOME so these tests are not at the mercy of the developer's real
# ~/.claude/settings.json - a machine that happens to have ralph-loop (or any other
# Stop-hook plugin) genuinely enabled would otherwise make "doctor reports ok" flaky
# for a reason that has nothing to do with the code under test.
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "doctor reports jq and bash resolution" {
  run bash "$DOCTOR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^ok: +jq'
  echo "$output" | grep -qE '^ok: +bash'
}

@test "doctor names the principles file in effect" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo "orders" > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$DOCTOR"
  echo "$output" | grep -q "amir-loop-principles.md"
}

@test "doctor FAILs when a conflicting ralph-loop stop hook is enabled" {
  run env AMIR_LOOP_FAKE_ENABLED_PLUGINS="ralph-loop@claude-plugins-official" bash "$DOCTOR"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'FAIL:.*ralph-loop'
}
