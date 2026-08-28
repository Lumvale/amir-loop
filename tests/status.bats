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
