#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/test.yml"
}

@test "hosted tests run automatically only on main and cancel superseded refs" {
  run grep -F "branches: [main]" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F 'group: tests-${{ github.ref }}' "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "cancel-in-progress: true" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "on: [push" "$WORKFLOW"
  [ "$status" -ne 0 ]
}

@test "cache-version policy is reachable without a pull-request event" {
  run grep -F "github.event_name == 'pull_request'" "$WORKFLOW"
  [ "$status" -ne 0 ]

  run grep -F "PUSH_BASE_SHA: \${{ github.event.before }}" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F 'scripts/check-codex-plugin-version-bump.sh "$BASE_SHA"' "$WORKFLOW"
  [ "$status" -eq 0 ]
}
