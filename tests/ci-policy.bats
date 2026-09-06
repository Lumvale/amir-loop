#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/test.yml"
  CODEQL_WORKFLOW="$REPO_ROOT/.github/workflows/codeql.yml"
  PLAYBOOK_EVENTS_WORKFLOW="$REPO_ROOT/.github/workflows/playbook-events.yml"
}

@test "CodeQL is post-merge security evidence and never a PR runner" {
  run grep -F "branches: [main]" "$CODEQL_WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "pull_request" "$CODEQL_WORKFLOW"
  [ "$status" -ne 0 ]

  run grep -F "security-events: write" "$CODEQL_WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "allows_public_repositories=false" "$CODEQL_WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "language: [actions, python]" "$CODEQL_WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "runs-on: ubuntu-latest" "$CODEQL_WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "runs-on: ubuntu-latest" "$PLAYBOOK_EVENTS_WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F 'runs-on: ${{ vars.RUNNER_LABEL }}' "$CODEQL_WORKFLOW" "$PLAYBOOK_EVENTS_WORKFLOW"
  [ "$status" -ne 0 ]
}

@test "hosted tests run automatically only on main and cancel superseded refs" {
  run grep -F "branches: [main]" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F 'group: tests-${{ github.ref }}' "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "cancel-in-progress: true" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "contents: read" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F "on: [push" "$WORKFLOW"
  [ "$status" -ne 0 ]
}

@test "hosted workflow is only the OS-specific binary and shell lane" {
  run grep -F "github.event_name == 'pull_request'" "$WORKFLOW"
  [ "$status" -ne 0 ]

  run grep -F "fetch-depth: 2" "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F 'os: [macos-latest, windows-latest]' "$WORKFLOW"
  [ "$status" -eq 0 ]

  run grep -F 'ubuntu-latest' "$WORKFLOW"
  [ "$status" -ne 0 ]

  run grep -F 'scripts/check-codex-plugin-version-bump.sh' "$WORKFLOW"
  [ "$status" -ne 0 ]
}
