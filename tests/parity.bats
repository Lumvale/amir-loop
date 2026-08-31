load helper

DOCTOR="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.sh"
SETUP="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-setup.sh"

# The principles-climb loop is duplicated in four places (hook, doctor, status, setup)
# and the jq platform mapping in three (hook, doctor, CI) deliberately - the hook must
# not `source` a file it has to locate at runtime. Nothing else catches drift between
# the copies, so this file plants one principles fixture and asserts every copy
# resolves it to the exact same path, and that doctor and the hook agree on which jq
# they will use.

@test "parity: hook, doctor and setup all resolve the same principles path" {
  mkdir -p "$BATS_TEST_TMPDIR/fleet/.claude" "$BATS_TEST_TMPDIR/fleet/repo/sub/.claude"
  echo "PARITY SENTINEL" > "$BATS_TEST_TMPDIR/fleet/.claude/amir-loop-principles.md"
  local expected="$BATS_TEST_TMPDIR/fleet/.claude/amir-loop-principles.md"

  # hook: arm from the sub dir and confirm the sentinel text made it into the state file
  cp "$FIXTURES/vscode-copilot.jsonl" "$BATS_TEST_TMPDIR/t.jsonl"
  run bash -c "printf '{\"cwd\":\"$BATS_TEST_TMPDIR/fleet/repo/sub\",\"session_id\":\"s1\",\"transcript_path\":\"$BATS_TEST_TMPDIR/t.jsonl\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  grep -q "PARITY SENTINEL" "$BATS_TEST_TMPDIR/fleet/repo/sub/.claude/amir-loop.s1.local.md"
  rm -f "$BATS_TEST_TMPDIR/fleet/repo/sub/.claude/amir-loop.s1.local.md"

  # doctor: run from the same sub dir, expect it to name the exact same path
  run bash -c "cd '$BATS_TEST_TMPDIR/fleet/repo/sub' && bash '$DOCTOR'"
  echo "$output" | grep -qF "$expected"

  # setup: run from the same sub dir with a hand-started prompt, expect the sentinel
  # text to be appended to the state file it writes
  run bash -c "cd '$BATS_TEST_TMPDIR/fleet/repo/sub' && bash '$SETUP' do the thing"
  [ "$status" -eq 0 ]
  grep -q "PARITY SENTINEL" "$BATS_TEST_TMPDIR/fleet/repo/sub/.claude/amir-loop.pending.local.md"
}

@test "parity: doctor and the hook select the same jq" {
  # Neither script's platform mapping is reimplemented here - that would just be a
  # fourth copy, unable to detect drift between the other three. Instead each script
  # is asked to report its own answer (doctor via --print-jq, the hook via the
  # AMIR_LOOP_JQ_DEBUG test-only escape hatch) and the two answers are compared
  # directly. If either script's mapping is edited to point somewhere else, the two
  # answers stop matching and this goes red - see the mutation demonstration in the
  # PR description for proof.
  run bash "$DOCTOR" --print-jq
  doctor_status="$status"
  doctor_jq="$output"

  run bash -c "echo '{}' | AMIR_LOOP_JQ_DEBUG=1 bash '$HOOK'"
  hook_status="$status"
  hook_jq="$output"

  [ "$hook_status" -eq 0 ]
  [ "$doctor_jq" = "$hook_jq" ]

  # Both scripts must actually have resolved *something* runnable, not merely agree
  # on being empty - an agreed-empty answer would still pass the equality check above
  # while the loop silently allows every stop.
  [ -n "$hook_jq" ]
  [ "$doctor_status" -eq 0 ]
  "$hook_jq" --version >/dev/null 2>&1 || command -v "$hook_jq" >/dev/null 2>&1

  # hook: arm a fresh session and confirm it did NOT allow-stop-on-no-jq (i.e. it
  # actually produced JSON output), which only happens if its resolution picked a jq
  # that runs - matching doctor's verdict above.
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  run run_hook
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  echo "$output" | jq -e '.decision == "block"' >/dev/null
}
