HOOK="$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/amir-loop-stop.sh"
FIXTURES="$BATS_TEST_DIRNAME/fixtures"

# Copy a fixture into the temp dir so tests never share transcript state.
use_fixture() {
  cp "$FIXTURES/$1" "$BATS_TEST_TMPDIR/transcript.jsonl"
  TRANSCRIPT="$BATS_TEST_TMPDIR/transcript.jsonl"
}

# Rewrite a fixture's transcript path so VS Code detection can be exercised.
use_fixture_as_copilot() {
  mkdir -p "$BATS_TEST_TMPDIR/GitHub.copilot-chat"
  cp "$FIXTURES/$1" "$BATS_TEST_TMPDIR/GitHub.copilot-chat/transcript.jsonl"
  TRANSCRIPT="$BATS_TEST_TMPDIR/GitHub.copilot-chat/transcript.jsonl"
}

# Pre-arm a loop at a given iteration so continuation paths can be tested.
arm_state() {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cat > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md" <<EOF
---
active: true
iteration: $1
max_iterations: $2
completion_promise: "AMIR LOOP COMPLETE"
started_at: "2026-08-28T00:00:00Z"
---

Do the work.
EOF
}

run_hook() {
  printf '{"cwd":"%s","session_id":"s1","transcript_path":"%s"}' \
    "$BATS_TEST_TMPDIR" "${TRANSCRIPT:-}" | bash "$HOOK" "$@"
}
