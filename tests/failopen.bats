load helper

@test "loop still continues when jq is absent from PATH (vendored fallback)" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10

  # run_hook builds its payload with `jq -n --arg` in helper.bash, so blanking PATH
  # for the whole call would break the test harness, not just the hook under test.
  # Build the payload first, using the real PATH, before narrowing it below.
  PAYLOAD=$(jq -n --arg cwd "$BATS_TEST_TMPDIR" --arg session "s1" --arg tp "${TRANSCRIPT:-}" \
    '{cwd: $cwd, session_id: $session, transcript_path: $tp}')

  # Mirror every command the hook and its shell might need (bash, cat, dirname,
  # uname, sed, awk, date, mkdir, rm, grep, tr, cp, ...) EXCEPT jq, by symlinking
  # everything on the real PATH into a scratch dir and deleting any `jq` that
  # landed in it. This starves the hook's OWN `command -v jq` specifically,
  # without also breaking the shell plumbing the way a bash-only PATH would.
  NOJQ="$BATS_TEST_TMPDIR/nojq"
  mkdir -p "$NOJQ"
  IFS=':' read -ra _dirs <<< "$PATH"
  for d in "${_dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -e "$f" ] || continue
      base=$(basename "$f")
      [ "$base" = "jq" ] && continue
      [ -e "$NOJQ/$base" ] || ln -s "$f" "$NOJQ/$base" 2>/dev/null
    done
  done
  rm -f "$NOJQ/jq"

  run env PATH="$NOJQ" PAYLOAD="$PAYLOAD" HOOK="$HOOK" \
    bash -c 'printf "%s" "$PAYLOAD" | bash "$HOOK"'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
}

# The brief's original form for the tests below was `run env VAR=x run_hook`. `env`
# execs an external program and cannot invoke `run_hook`, which is a bash FUNCTION
# from helper.bash - that form dies with "env: 'run_hook': No such file or directory"
# before the hook is ever reached. `VAR=x run run_hook` is the correct bash form: the
# env-prefix assignment applies to the function call that `run` (a bats function)
# wraps.

@test "AMIR_LOOP_OFF=1 allows the stop" {
  use_fixture vscode-copilot.jsonl; arm_state 1 10
  AMIR_LOOP_OFF=1 run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "kill-switch file allows the stop" {
  use_fixture vscode-copilot.jsonl; arm_state 1 10
  : > "$BATS_TEST_TMPDIR/.claude/amir-loop-off"
  run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "junk iteration allows the stop and clears state" {
  use_fixture vscode-copilot.jsonl
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\niteration: banana\nmax_iterations: 10\n---\n\nwork\n' \
    > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
  run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md" ]
}

@test "invalid AMIR_LOOP_DAYS allows the stop" {
  use_fixture vscode-copilot.jsonl; arm_state 1 10
  AMIR_LOOP_DAYS=banana run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "unparseable AMIR_LOOP_UNTIL is treated as expired" {
  use_fixture vscode-copilot.jsonl; arm_state 1 10
  AMIR_LOOP_UNTIL=not-a-date run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "unreadable transcript allows the stop WITHOUT writing a marker" {
  arm_state 1 10
  TRANSCRIPT="$BATS_TEST_TMPDIR/does-not-exist.jsonl"
  run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "ls $BATS_TEST_TMPDIR/.claude/.amir-loop-done-* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}
