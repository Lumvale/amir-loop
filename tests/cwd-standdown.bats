load helper

# A hook that cannot tell which workspace it is in must not choose one.
#
# The hook used to fall back to `$PWD` when the payload carried no cwd, which ARMS A LOOP in
# whatever directory the hook process happened to be in. Measured 2026-09-03 on Windows, once
# the launcher fix in #24 made these hooks execute at all: an empty payload scattered
# `.claude/.amir-loop-campaign`, `amir-loop.nosession.local.md` and nested `.claude` and
# `.lumvaleos` directories into three unrelated git worktrees, purely because a shell had cd'd
# there. Nothing reported a fault - the litter was the only trace.

# Run the hook from inside a directory that is NOT a workspace, with the given stdin.
run_hook_from_stray_dir() {
  local payload="$1"
  mkdir -p "$BATS_TEST_TMPDIR/stray"
  ( cd "$BATS_TEST_TMPDIR/stray" && printf '%s' "$payload" | bash "$HOOK" "${@:2}" )
}

@test "an empty payload does not arm a loop in the current directory" {
  run run_hook_from_stray_dir ""
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/stray/.claude" ]
}

@test "a payload with no cwd does not arm a loop in the current directory" {
  run run_hook_from_stray_dir '{"session_id":"s1"}'
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/stray/.claude" ]
}

@test "an observe event does not arm a loop in the current directory either" {
  run run_hook_from_stray_dir "" --observe=post-tool
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/stray/.claude" ]
}

@test "standing down emits nothing, so the host is not told to continue" {
  run run_hook_from_stray_dir '{"session_id":"s1"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Without this the three tests above pass on a hook that never arms anything at all, which is a
# different bug wearing the same green.
@test "CONTROL a payload WITH a cwd still arms, so the tests above are not vacuous" {
  use_fixture claude-code.jsonl
  run run_hook
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop.s1.local.md" ]
}
