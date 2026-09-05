STATUS="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-status.sh"

# Snapshot .claude/ as a listing + content checksum so we can prove status
# leaves it byte-identical - a "read-only" tool that quietly writes is the
# kind of defect nothing else in this suite would catch.
snapshot_claude() {
  if [ -d "$BATS_TEST_TMPDIR/.claude" ]; then
    ( cd "$BATS_TEST_TMPDIR" && find .claude -type f -exec sha256sum {} \; | sort )
  fi
}

@test "status reports idle with no loop armed" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^state: idle$'
}

@test "json status reports an explicit idle state" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$STATUS" --json
  [ "$status" -eq 0 ]
  jq -e '.schema_version == 1 and .state == "idle" and .session_count == 0 and .sessions == []' <<<"$output"
}

@test "json status returns deterministic per-session state" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\niteration: 2\nmax_iterations: 9\ncompletion_promise: "SECOND"\nstarted_at: "2026-09-05T02:00:00Z"\n---\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.z.local.md"
  printf -- '---\niteration: 1\nmax_iterations: 8\ncompletion_promise: "FIRST"\nstarted_at: "2026-09-05T01:00:00Z"\n---\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.a.local.md"
  cd "$BATS_TEST_TMPDIR"

  run bash "$STATUS" --json

  [ "$status" -eq 0 ]
  jq -e '.state == "armed" and .session_count == 2' <<<"$output"
  jq -e '.sessions[0].path | endswith("amir-loop.a.local.md")' <<<"$output"
  jq -e '.sessions[0] | .state == "armed" and .iteration == 1 and .max_iterations == 8 and .completion_promise == "FIRST" and .started_at == "2026-09-05T01:00:00Z"' <<<"$output"
  jq -e '.sessions[1].path | endswith("amir-loop.z.local.md")' <<<"$output"
}

@test "json status fails closed for malformed session counters" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\niteration: 4junk\nmax_iterations: 20\ncompletion_promise: "NOPE"\nstarted_at: "2026-09-05T01:00:00Z"\n---\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.bad.local.md"
  cd "$BATS_TEST_TMPDIR"

  run bash "$STATUS" --json

  [ "$status" -eq 0 ]
  jq -e '.state == "invalid" and .sessions[0].state == "invalid" and .sessions[0].iteration == null and .sessions[0].max_iterations == null' <<<"$output"
}

@test "json status represents a legacy single-state file" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\niteration: 4\nmax_iterations: 20\ncompletion_promise: "LEGACY"\nstarted_at: "2026-09-05T01:00:00Z"\n---\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
  cd "$BATS_TEST_TMPDIR"

  run bash "$STATUS" --json

  [ "$status" -eq 0 ]
  jq -e '.state == "armed" and .session_count == 1 and .sessions[0].completion_promise == "LEGACY"' <<<"$output"
}

@test "json status does not mutate .claude" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\niteration: 1\nmax_iterations: 2\ncompletion_promise: "SAFE"\nstarted_at: "2026-09-05T01:00:00Z"\n---\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.safe.local.md"
  cd "$BATS_TEST_TMPDIR"
  before="$(snapshot_claude)"

  run bash "$STATUS" --json

  [ "$status" -eq 0 ]
  after="$(snapshot_claude)"
  [ "$before" = "$after" ]
}

@test "status reports iteration and limit when armed" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\nactive: true\niteration: 4\nmax_iterations: 20\ncompletion_promise: "AMIR LOOP COMPLETE"\nstarted_at: "2026-08-28T00:00:00Z"\n---\n\nwork\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^state: armed$'
  echo "$output" | grep -q '^iteration: 4 of 20$'
  echo "$output" | grep -q '^promise: AMIR LOOP COMPLETE$'
}

@test "status reports the principles file actually in effect" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo "orders" > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^principles: $BATS_TEST_TMPDIR/.claude/amir-loop-principles.md$"
}

@test "status reports no principles found when none exist upward" {
  mkdir -p "$BATS_TEST_TMPDIR/project/.claude"
  cd "$BATS_TEST_TMPDIR/project"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^principles: none$'
}

@test "status reports the selected Workspace policy hash" {
  mkdir -p "$BATS_TEST_TMPDIR/ws/.lumvaleos"
  echo "workspace: {id: ws-people}" > "$BATS_TEST_TMPDIR/ws/workspace.yaml"
  echo '<!-- lumvaleos-agent-policy: 1 workspace=ws-people hash=sha256:people -->' \
    > "$BATS_TEST_TMPDIR/ws/.lumvaleos/amir-loop-principles.md"

  AMIR_LOOP_WORKSPACE_ROOT="$BATS_TEST_TMPDIR/ws" run bash "$STATUS"

  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'workspace=ws-people hash=sha256:people'
}

@test "status does not mutate .claude/ - idle case" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo "orders" > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  cd "$BATS_TEST_TMPDIR"
  before="$(snapshot_claude)"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  after="$(snapshot_claude)"
  [ "$before" = "$after" ]
}

@test "status does not mutate .claude/ - armed case" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\nactive: true\niteration: 4\nmax_iterations: 20\ncompletion_promise: "AMIR LOOP COMPLETE"\nstarted_at: "2026-08-28T00:00:00Z"\n---\n\nwork\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
  echo "orders" > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  cd "$BATS_TEST_TMPDIR"
  before="$(snapshot_claude)"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  after="$(snapshot_claude)"
  [ "$before" = "$after" ]
}

# --- malformed state files -------------------------------------------------
# The hook (plugins/amir-loop/hooks/amir-loop-stop.sh:236-239) deletes the
# state file and allows the stop the moment iteration or max_iterations fails
# the `''|*[!0-9]*` test. status must never report `armed` (or a digits-only
# number quietly salvaged from junk) for a state the hook has already
# discarded - that would be a diagnostic that lies in exactly the situation
# someone reaches for it.

@test "status reports invalid, not armed, when iteration contains junk" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\nactive: true\niteration: 4abc\nmax_iterations: 20\ncompletion_promise: "AMIR LOOP COMPLETE"\nstarted_at: "2026-08-28T00:00:00Z"\n---\n\nwork\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^state: invalid$'
  ! echo "$output" | grep -q '^state: armed$'
  ! echo "$output" | grep -qE '^iteration: [0-9]+ of'
}

@test "status reports invalid when max_iterations contains junk" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\nactive: true\niteration: 4\nmax_iterations: 20x\ncompletion_promise: "AMIR LOOP COMPLETE"\nstarted_at: "2026-08-28T00:00:00Z"\n---\n\nwork\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^state: invalid$'
  ! echo "$output" | grep -q '^state: armed$'
}

@test "status reports invalid when max_iterations is missing entirely" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\nactive: true\niteration: 4\ncompletion_promise: "AMIR LOOP COMPLETE"\nstarted_at: "2026-08-28T00:00:00Z"\n---\n\nwork\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^state: invalid$'
  ! echo "$output" | grep -q '^state: armed$'
  ! echo "$output" | grep -q '^iteration: 4 of $'
}

@test "status reports invalid for a completely empty state file" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  : > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^state: invalid$'
  ! echo "$output" | grep -q '^state: armed$'
}

@test "status reports invalid for a state file with no --- frontmatter delimiters" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf 'iteration: 4\nmax_iterations: 20\nno frontmatter here\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^state: invalid$'
  ! echo "$output" | grep -q '^state: armed$'
}

@test "status preserves a colon and embedded quotes in completion_promise" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf -- '---\nactive: true\niteration: 4\nmax_iterations: 20\ncompletion_promise: "Ship it: really "done" now"\nstarted_at: "2026-08-28T00:00:00Z"\n---\n\nwork\n' > "$BATS_TEST_TMPDIR/.claude/amir-loop.local.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$STATUS"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^state: armed$'
  echo "$output" | grep -q '^promise: Ship it: really "done" now$'
}
