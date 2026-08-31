load helper

SETUP="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-setup.sh"

# /amir-loop forwards $ARGUMENTS to amir-loop-setup.sh verbatim (no `--` terminator,
# since one would break the documented `PROMPT --max-iterations N` flag usage). A user
# prompt that happens to start with "-h" or "--cancel" must still arm a loop with that
# text, not be swallowed as a flag - --cancel has its own dedicated /amir-loop-cancel
# command, and -h/--help only makes sense for a human invoking this script directly.

@test "setup: a prompt beginning with -h is armed as text, not treated as --help" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" -h do the thing
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md" ]
  grep -q -- "-h do the thing" "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}

@test "setup: a prompt beginning with --cancel is armed as text, not treated as cancel" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" --cancel this task
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/amir-loop-off" ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md" ]
  grep -q -- "--cancel this task" "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}

@test "setup: --cancel alone still cancels (the /amir-loop-cancel path)" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" --cancel
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop-off" ]
}

@test "setup: -h alone still prints help" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" -h
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "amir loop"
}

@test "setup: --max-iterations still works alongside a prompt (regression)" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" Build the parser --max-iterations 20
  [ "$status" -eq 0 ]
  grep -q "max_iterations: 20" "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}

@test "setup: Bedrock runtime profile is rendered for a manually armed loop" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cp "$BATS_TEST_DIRNAME/../templates/runtime/bedrock.json" "$BATS_TEST_TMPDIR/.claude/amir-loop-runtime.json"
  cd "$BATS_TEST_TMPDIR"
  run env AMIR_LOOP_PROVIDER=bedrock bash "$SETUP" Run the governed suite
  [ "$status" -eq 0 ]
  grep -q 'provider: bedrock' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
  grep -q 'observed provider activation: bedrock' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}
