load helper

@test "turn cap reached finishes the loop and writes a marker" {
  use_fixture vscode-copilot.jsonl
  arm_state 10 10
  run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md" ]
  [ -f "$BATS_TEST_TMPDIR/.claude/.amir-loop-done-s1" ]
}

@test "iteration increments on continue" {
  use_fixture vscode-copilot.jsonl
  arm_state 3 10
  run run_hook
  grep -q '^iteration: 4$' "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
}

@test "AMIR_LOOP_MAX of 0 or junk clamps to the 1000 default" {
  for v in 0 banana; do
    use_fixture vscode-copilot.jsonl
    AMIR_LOOP_MAX="$v" run run_hook
    grep -q '^max_iterations: 1000$' "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
    rm -rf "$BATS_TEST_TMPDIR/.claude"
  done
}

@test "expired calendar window allows the stop" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo 0 > "$BATS_TEST_TMPDIR/.claude/.amir-loop-campaign"
  AMIR_LOOP_DAYS=1 run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "AMIR_LOOP_DAYS=0 means no deadline" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo 0 > "$BATS_TEST_TMPDIR/.claude/.amir-loop-campaign"
  AMIR_LOOP_DAYS=0 run run_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
}

@test "AMIR_LOOP_UNTIL far in the future permits continuation" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  AMIR_LOOP_UNTIL=2099-01-01 run run_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
}

@test "AMIR_LOOP_UNTIL in the past allows the stop" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  AMIR_LOOP_UNTIL=2000-01-01 run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "AMIR_LOOP_UNTIL: BSD-style date without -d still parses (regression for macOS)" {
  # "far in the future permits continuation" above only checks the outcome, which is
  # exactly why it passed on Linux and failed silently on macOS: GNU `date -d` doesn't
  # exist there, DEADLINE falls through to "invalid", and invalid is treated as
  # expired -> allow_stop, which LOOKS like a legitimate pass/fail depending on what
  # you compare it to. This test forces that failure mode by stubbing `date` to
  # reject `-d` the way BSD/macOS date does, so the only way to reach "block" is
  # through the hook's `-j -f` fallback branch actually converting the date.
  #
  # This only makes sense where GNU date exists to be stubbed out: on real BSD/macOS
  # there is no GNU date underneath for the stub to fall back on, and the test above
  # ("far in the future permits continuation") already exercises the native `-j -f`
  # fallback directly on that platform. So skip here rather than fake a GNU binary.
  if ! date -d 2099-01-01 +%s >/dev/null 2>&1; then
    skip "no GNU 'date -d' on this platform to stub out; the native -j -f fallback is already exercised by 'AMIR_LOOP_UNTIL far in the future permits continuation'"
  fi
  REAL_DATE=$(command -v date)

  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  STUBDIR="$BATS_TEST_TMPDIR/stubdate"
  mkdir -p "$STUBDIR"
  cat > "$STUBDIR/date" <<EOF
#!/bin/bash
# Reject -d like BSD/macOS date, forcing the hook onto its \`-j -f\` fallback.
# This box has GNU date (checked above), so emulate the BSD fallback's
# semantics using the real GNU date underneath - found by PATH lookup at test
# setup, not a hardcoded location - purely to prove the fallback branch, not
# "invalid -> expired", is what produced the result.
REAL_DATE="$REAL_DATE"
if [ "\$1" = "-d" ]; then
  echo "stub-date: -d rejected (simulating BSD/macOS)" >&2
  exit 1
fi
if [ "\$1" = "-j" ] && [ "\$2" = "-f" ]; then
  fmt="\$3"; val="\$4"; outfmt="\$5"
  case "\$fmt" in
    "%Y-%m-%d %H:%M:%S") exec "\$REAL_DATE" -d "\$val" "\$outfmt" ;;
    *) echo "stub-date: unexpected -j -f format: \$fmt" >&2; exit 1 ;;
  esac
fi
exec "\$REAL_DATE" "\$@"
EOF
  chmod +x "$STUBDIR/date"

  PATH="$STUBDIR:$PATH" AMIR_LOOP_UNTIL=2099-01-01 run run_hook
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
}
