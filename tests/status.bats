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
