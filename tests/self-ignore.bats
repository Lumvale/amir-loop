load helper

# The loop drops seven files into `$CWD/.claude/` in whatever repository it was run from. None is
# repository content, and each one showed in `git status` until somebody added an ignore rule by
# hand — per repo, forever, one artefact at a time as each was discovered.
#
# Measured 2026-09-03 in `lumvale-os`: rules existed for two of them, and FOUR were uncovered.
# `amir-loop.*.local.md` had itself only been added AFTER one was committed to `main`. Two stray
# `-done-` markers made `git_provenance` report `dirty: True` on the checkout the LumvaleOS MCP
# server SERVES, so that engine's staleness warning fired permanently over ten bytes of scratch.
#
# These pin the fix so the eighth artefact is covered before it is discovered, not after.

@test "the loop ignores its own litter in the directory it already owns" {
  use_fixture claude-code.jsonl
  arm_state 1 10
  run run_hook
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/.gitignore" ]
  grep -qxF '/.amir-loop-*' "$BATS_TEST_TMPDIR/.claude/.gitignore"
  grep -qxF '/amir-loop.*.local.md' "$BATS_TEST_TMPDIR/.claude/.gitignore"
}

@test "the ignore file lists itself, so the fix is not the next stray file" {
  use_fixture claude-code.jsonl
  arm_state 1 10
  run run_hook
  [ "$status" -eq 0 ]
  grep -qxF '/.gitignore' "$BATS_TEST_TMPDIR/.claude/.gitignore"
}

@test "the loop ignores its litter in .lumvaleos too, not only .claude" {
  # The hook's own `mkdir -p` creates BOTH. `.lumvaleos/` receives `playbook-events.jsonl` (an
  # outbox) and `.playbook-heartbeat`. Found the way the first four were: `git add -A` in this
  # very change swept `.lumvaleos/playbook-events.jsonl` into the commit that was fixing the
  # problem, and it had to be taken back out.
  #
  # `.lumvaleos/` is created by the OBSERVE path, not by a plain Stop, so it is pre-created here:
  # the helper's contract is "tidy a directory that exists", and creating one just to drop an
  # ignore file into it would be a worse change than the litter it prevents. This is the realistic
  # state — any repo the loop has emitted an event from already has the directory.
  mkdir -p "$BATS_TEST_TMPDIR/.lumvaleos"
  use_fixture claude-code.jsonl
  arm_state 1 10
  run run_hook
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.lumvaleos/.gitignore" ]
  grep -qxF '/playbook-events.jsonl' "$BATS_TEST_TMPDIR/.lumvaleos/.gitignore"
  grep -qxF '/agent-actions.jsonl' "$BATS_TEST_TMPDIR/.lumvaleos/.gitignore"
  grep -qxF '/.playbook-heartbeat' "$BATS_TEST_TMPDIR/.lumvaleos/.gitignore"
  grep -qxF '/.gitignore' "$BATS_TEST_TMPDIR/.lumvaleos/.gitignore"
}

@test "the prefix rule covers every artefact the hook writes" {
  # Derived from the hook's own assignments rather than a hand-kept list: a rule checked against a
  # copy of the list it is supposed to cover proves only that I typed it twice. This scan is what
  # found `amir-loop-off` and, once widened to `.lumvaleos/`, the two playbook files.
  use_fixture claude-code.jsonl
  arm_state 1 10
  run run_hook
  [ "$status" -eq 0 ]
  paths=$(grep -oE '"\$CWD/\.(claude|lumvaleos)/[^"]+"' "$HOOK" \
    | tr -d '"' | sed -E 's#^\$CWD/\.(claude|lumvaleos)/##' | sort -u)
  [ -n "$paths" ]
  for p in $paths; do
    case "$p" in
      .amir-loop-*|amir-loop.*.local.md|'$STATE_NAME') ;;
      playbook-events.jsonl|agent-actions.jsonl|.playbook-heartbeat) ;;
      # `amir-loop-off` is a KILL SWITCH, not litter: a file the USER creates to stop the loop
      # (see the hook's header). Ignoring it would be wrong in both directions — it is deliberate
      # intent, and a team may well want it committed to disable the loop for everyone. This scan
      # found it precisely because it derives from the hook instead of restating a list, so the
      # exclusion is written here with its reason rather than silently widening the rules.
      amir-loop-off) ;;
      *) echo "unignored artefact: $p"; return 1 ;;
    esac
  done
}

@test "an existing .claude/.gitignore is merged, never clobbered" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '%s\n' '/somebody-elses-rule' > "$BATS_TEST_TMPDIR/.claude/.gitignore"
  use_fixture claude-code.jsonl
  arm_state 1 10
  run run_hook
  [ "$status" -eq 0 ]
  grep -qxF '/somebody-elses-rule' "$BATS_TEST_TMPDIR/.claude/.gitignore"
  grep -qxF '/.amir-loop-*' "$BATS_TEST_TMPDIR/.claude/.gitignore"
}

@test "rules are not duplicated when the hook runs repeatedly" {
  # The hook runs on every Stop. Appending unconditionally would grow the file without bound.
  use_fixture claude-code.jsonl
  arm_state 1 10
  run run_hook
  [ "$status" -eq 0 ]
  arm_state 2 10
  run run_hook
  [ "$status" -eq 0 ]
  [ "$(grep -cxF '/.amir-loop-*' "$BATS_TEST_TMPDIR/.claude/.gitignore")" -eq 1 ]
}

@test "an unwritable ignore file costs the tidiness, never the Stop hook" {
  # A Stop hook that fails a session over housekeeping is a worse defect than the litter it was
  # tidying. Simulated by making the path a DIRECTORY, so every write to it fails on any platform
  # — chmod is unreliable on Windows, where this fleet develops.
  mkdir -p "$BATS_TEST_TMPDIR/.claude/.gitignore"
  use_fixture claude-code.jsonl
  arm_state 1 10
  run run_hook
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$(echo "$output" | jq -r '.decision')" = "block" ]
}
