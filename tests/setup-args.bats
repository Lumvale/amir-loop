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

@test "setup: project cancellation preserves live session state" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf 'live session work\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.live.local.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" --cancel
  [ "$status" -eq 0 ]
  grep -q 'live session work' "$BATS_TEST_TMPDIR/.claude/amir-loop.live.local.md"
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop-off" ]
}

@test "setup: project cancellation releases the current worktree claim" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude/.amir-loop-worktree-claim"
  printf 'session-one\n' > "$BATS_TEST_TMPDIR/.claude/.amir-loop-worktree-claim/owner"
  printf '100\n' > "$BATS_TEST_TMPDIR/.claude/.amir-loop-worktree-claim/heartbeat"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" --cancel
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop-off" ]
  [ ! -e "$BATS_TEST_TMPDIR/.claude/.amir-loop-worktree-claim" ]
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

# /amir-loop now passes "$ARGUMENTS" QUOTED, so this script receives the whole prompt as ONE
# argument and re-splits it itself (#21). Unquoted, the shell tokenized the prompt first:
#
#   `Work on findings #3639, #3641 --max-iterations 25` -> ARGC=3: "Work" "on" "findings"
#
# Everything from `#` was a comment, so the prompt was truncated AND --max-iterations was silently
# discarded - a requested cap of 25 became the default 1000, a 40x widening of the loop's primary
# safety bound. Worse, `$(...)` in a prompt was EXECUTED by the shell before this script ran.
#
# These tests use the single-argument form because that is what the command now sends.

@test "setup: a # in the prompt neither truncates it nor swallows the flags after it" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" 'Work on findings #3639, #3641, #3642 --max-iterations 25'
  [ "$status" -eq 0 ]
  grep -q -- "#3639, #3641, #3642" "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
  grep -q "^max_iterations: 25$" "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}

@test "setup: a command substitution in the prompt is text, not code" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" 'Fix the $(echo INJECTED) bug'
  [ "$status" -eq 0 ]
  grep -q 'echo INJECTED' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
  ! grep -q '^INJECTED$' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}

@test "setup: shell metacharacters in the prompt survive as written" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" 'Investigate a; b | c && d > e'
  [ "$status" -eq 0 ]
  grep -q -- 'a; b | c && d > e' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}

@test "setup: a quoted multi-word completion promise is still grouped" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" "Fix auth --completion-promise 'ALL TESTS PASS'"
  [ "$status" -eq 0 ]
  grep -q '^completion_promise: "ALL TESTS PASS"$' "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}

@test "setup: an apostrophe in ordinary prose still arms the loop" {
  # Refusing to start work over English punctuation would be a worse failure than the one #21
  # fixed. Grouping is lost, the text is not, and the fallback says so on stderr.
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" "Fix the O'Brien bug"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md" ]
  grep -q "O'Brien" "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}

@test "setup: the single-argument form honours an explicit iteration cap" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" 'Do the thing --max-iterations 7'
  [ "$status" -eq 0 ]
  grep -q "^max_iterations: 7$" "$BATS_TEST_TMPDIR/.claude/amir-loop.pending.local.md"
}

@test "setup: --cancel alone still cancels through the single-argument path" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cd "$BATS_TEST_TMPDIR"
  run bash "$SETUP" '--cancel'
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop-off" ]
}

@test "setup: the command passes ARGUMENTS quoted" {
  # The whole fix depends on this one character. Unquoted, the shell tokenizes the prompt before
  # the parser above ever runs, and every test in this block passes while the product is broken.
  grep -q 'amir-loop-setup.sh" "\$ARGUMENTS"' "$BATS_TEST_DIRNAME/../plugins/amir-loop/commands/amir-loop.md"
}
