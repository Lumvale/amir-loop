load helper

CLAIM="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-worktree-claim.sh"

@test "two simultaneous campaign sessions cannot both claim one worktree" {
  mkdir -p "$BATS_TEST_TMPDIR/work"
  run bash -c '
    root="$1" claim="$2"
    AMIR_LOOP_CLAIM_NOW=100 bash "$claim" acquire "$root" session-one >/dev/null 2>&1 & p1=$!
    AMIR_LOOP_CLAIM_NOW=100 bash "$claim" acquire "$root" session-two >/dev/null 2>&1 & p2=$!
    wait "$p1"; s1=$?
    wait "$p2"; s2=$?
    test $((s1 + s2)) -eq 73
  ' _ "$BATS_TEST_TMPDIR/work" "$CLAIM"
  [ "$status" -eq 0 ]
  owner=$(cat "$BATS_TEST_TMPDIR/work/.claude/.amir-loop-worktree-claim/owner")
  case "$owner" in session-one|session-two) ;; *) false ;; esac
}

@test "a fresh foreign claim denies a second session before state is written" {
  use_fixture vscode-copilot.jsonl
  AMIR_LOOP_CLAIM_NOW=100 run run_hook
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/.claude/amir-loop.s1.local.md" ]

  run bash -c "jq -n --arg cwd '$BATS_TEST_TMPDIR' --arg tp '$TRANSCRIPT' '{cwd:\$cwd,session_id:\"s2\",transcript_path:\$tp}' | AMIR_LOOP_CLAIM_NOW=101 bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/.claude/amir-loop.s2.local.md" ]
  grep -q '^s1$' "$BATS_TEST_TMPDIR/.claude/.amir-loop-worktree-claim/owner"
}

@test "nested source folders with distinct selected Workspaces do not share a claim" {
  parent="$BATS_TEST_TMPDIR/source"
  child="$parent/Money"
  parent_ws="$BATS_TEST_TMPDIR/ws-parent"
  child_ws="$BATS_TEST_TMPDIR/ws-money"
  mkdir -p "$child" "$parent_ws" "$child_ws"
  printf 'workspace: {id: ws-parent}\n' > "$parent_ws/workspace.yaml"
  printf 'workspace: {id: ws-money}\n' > "$child_ws/workspace.yaml"

  run bash -c "jq -n --arg cwd '$parent' --arg tp '$TRANSCRIPT' '{cwd:\$cwd,session_id:\"parent-session\",transcript_path:\$tp}' | AMIR_LOOP_WORKSPACE_ROOT='$parent_ws' AMIR_LOOP_CLAIM_NOW=100 bash '$HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "jq -n --arg cwd '$child' --arg tp '$TRANSCRIPT' '{cwd:\$cwd,session_id:\"money-session\",transcript_path:\$tp}' | AMIR_LOOP_WORKSPACE_ROOT='$child_ws' AMIR_LOOP_CLAIM_NOW=100 bash '$HOOK'"
  [ "$status" -eq 0 ]

  grep -q '^parent-session$' "$parent_ws/.claude/.amir-loop-worktree-claim/owner"
  grep -q '^money-session$' "$child_ws/.claude/.amir-loop-worktree-claim/owner"
  [ ! -e "$parent/.claude/.amir-loop-worktree-claim" ]
  [ ! -e "$child/.claude/.amir-loop-worktree-claim" ]
}

@test "different source folders selecting the same Workspace still collide" {
  first="$BATS_TEST_TMPDIR/source-one"
  second="$BATS_TEST_TMPDIR/source-two"
  workspace="$BATS_TEST_TMPDIR/ws-shared"
  mkdir -p "$first" "$second" "$workspace"
  printf 'workspace: {id: ws-shared}\n' > "$workspace/workspace.yaml"

  run bash -c "jq -n --arg cwd '$first' --arg tp '$TRANSCRIPT' '{cwd:\$cwd,session_id:\"first-session\",transcript_path:\$tp}' | AMIR_LOOP_WORKSPACE_ROOT='$workspace' AMIR_LOOP_CLAIM_NOW=100 bash '$HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "jq -n --arg cwd '$second' '{cwd:\$cwd,session_id:\"second-session\",tool_name:\"Bash\"}' | AMIR_LOOP_WORKSPACE_ROOT='$workspace' AMIR_LOOP_CLAIM_NOW=101 bash '$HOOK' --observe=pre-tool"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
  grep -q '^first-session$' "$workspace/.claude/.amir-loop-worktree-claim/owner"
}

@test "pre-tool collision is denied fail closed" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude/.amir-loop-worktree-claim"
  printf 's1\n' > "$BATS_TEST_TMPDIR/.claude/.amir-loop-worktree-claim/owner"
  printf '100\n' > "$BATS_TEST_TMPDIR/.claude/.amir-loop-worktree-claim/heartbeat"
  run bash -c "jq -n --arg cwd '$BATS_TEST_TMPDIR' '{cwd:\$cwd,session_id:\"s2\",tool_name:\"Bash\"}' | AMIR_LOOP_CLAIM_NOW=101 bash '$HOOK' --observe=pre-tool"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
  echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'claimed by s1'
}

@test "an expired well-formed claim can be reclaimed" {
  mkdir -p "$BATS_TEST_TMPDIR/work/.claude/.amir-loop-worktree-claim"
  printf 'old-session\n' > "$BATS_TEST_TMPDIR/work/.claude/.amir-loop-worktree-claim/owner"
  printf '100\n' > "$BATS_TEST_TMPDIR/work/.claude/.amir-loop-worktree-claim/heartbeat"
  AMIR_LOOP_CLAIM_NOW=111 AMIR_LOOP_CLAIM_STALE_SECONDS=10 run bash "$CLAIM" acquire "$BATS_TEST_TMPDIR/work" new-session
  [ "$status" -eq 0 ]
  grep -q '^new-session$' "$BATS_TEST_TMPDIR/work/.claude/.amir-loop-worktree-claim/owner"
}

@test "a malformed claim is never treated as stale" {
  mkdir -p "$BATS_TEST_TMPDIR/work/.claude/.amir-loop-worktree-claim"
  printf 'old-session\n' > "$BATS_TEST_TMPDIR/work/.claude/.amir-loop-worktree-claim/owner"
  printf 'corrupt\n' > "$BATS_TEST_TMPDIR/work/.claude/.amir-loop-worktree-claim/heartbeat"
  AMIR_LOOP_CLAIM_NOW=999 AMIR_LOOP_CLAIM_STALE_SECONDS=1 run bash "$CLAIM" acquire "$BATS_TEST_TMPDIR/work" new-session
  [ "$status" -eq 73 ]
  grep -q '^old-session$' "$BATS_TEST_TMPDIR/work/.claude/.amir-loop-worktree-claim/owner"
}
