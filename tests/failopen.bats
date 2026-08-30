load helper

@test "vendored jq is executable and supports continuation" {
  use_fixture vscode-copilot.jsonl
  arm_state 1 10
  case "$(uname -s)" in
    Linux) vendor="$BATS_TEST_DIRNAME/../plugins/amir-loop/vendor/jq/jq-linux-amd64" ;;
    Darwin) vendor="$BATS_TEST_DIRNAME/../plugins/amir-loop/vendor/jq/jq-macos-$(uname -m | sed 's/x86_64/amd64/')" ;;
    MINGW*|MSYS*|CYGWIN*) vendor="$BATS_TEST_DIRNAME/../plugins/amir-loop/vendor/jq/jq-windows-amd64.exe" ;;
  esac
  run "$vendor" --version
  [ "$status" -eq 0 ]

  run run_hook
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
    > "$TEST_STATE"
  run run_hook
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ ! -f "$TEST_STATE" ]
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
  # Assert marker absence directly with a glob, rather than counting lines from `ls |
  # wc -l`: BSD `wc -l` (macOS) right-pads its count with leading whitespace
  # ("       0"), which fails a bare `[ "$output" = "0" ]` string comparison even
  # though the underlying behaviour - no marker written - is correct there too.
  shopt -s nullglob
  markers=("$BATS_TEST_TMPDIR"/.claude/.amir-loop-done-*)
  shopt -u nullglob
  [ "${#markers[@]}" -eq 0 ]
}

@test "malformed hook input fails open with exit code zero" {
  run bash -c "printf '%s' 'not-json' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}
