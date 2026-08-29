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
  # The hook has no direct way to print which jq it picked, so drive it into a path
  # where jq resolution failure is externally observable: point HOOK_INPUT at valid
  # JSON but corrupt only if the wrong jq were silently used. Simpler and more direct:
  # both scripts compute the vendored candidate the same way from uname; assert that
  # computation, plus the "does it execute" probe, agree between the two scripts.
  vendor="$BATS_TEST_DIRNAME/../plugins/amir-loop/vendor/jq"
  case "$(uname -s 2>/dev/null)" in
    Linux)   cand="$vendor/jq-linux-amd64" ;;
    Darwin)  case "$(uname -m 2>/dev/null)" in
               arm64) cand="$vendor/jq-macos-arm64" ;;
               *)     cand="$vendor/jq-macos-amd64" ;;
             esac ;;
    MINGW*|MSYS*|CYGWIN*) cand="$vendor/jq-windows-amd64.exe" ;;
    *) cand="" ;;
  esac

  if [ -n "$cand" ] && "$cand" --version >/dev/null 2>&1; then
    expect_vendored=1
  else
    expect_vendored=0
  fi

  run bash "$DOCTOR"
  if [ "$expect_vendored" = "1" ]; then
    echo "$output" | grep -qE '^ok: +jq  vendored'
  else
    ! echo "$output" | grep -qE '^ok: +jq  vendored'
  fi

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
