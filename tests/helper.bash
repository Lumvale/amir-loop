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
  jq -n --arg cwd "$BATS_TEST_TMPDIR" --arg session "s1" --arg tp "${TRANSCRIPT:-}" \
    '{cwd: $cwd, session_id: $session, transcript_path: $tp}' | bash "$HOOK" "$@"
}

# Codex exposes the final message and turn identity directly. Its transcript is an
# explicitly unstable convenience surface, so parity tests must not depend on its shape.
run_codex_hook() {
  jq -n --arg cwd "$BATS_TEST_TMPDIR" --arg session "s1" \
    --arg turn "${CODEX_TURN_ID:-turn-1}" \
    --arg last "${CODEX_LAST_ASSISTANT:-work remains}" \
    --arg error "${CODEX_ERROR:-}" \
    '{cwd: $cwd, session_id: $session, transcript_path: null, turn_id: $turn,
      last_assistant_message: $last, error: $error, stop_hook_active: false, model: "gpt-5.6-sol"}' |
    bash "$HOOK" "$@"
}
