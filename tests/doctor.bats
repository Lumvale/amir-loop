DOCTOR="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/amir-loop-doctor.sh"

# Isolate HOME so these tests are not at the mercy of the developer's real
# ~/.claude/settings.json - a machine that happens to have ralph-loop (or any other
# Stop-hook plugin) genuinely enabled would otherwise make "doctor reports ok" flaky
# for a reason that has nothing to do with the code under test.
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "doctor reports jq and bash resolution" {
  run bash "$DOCTOR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^ok: +jq'
  echo "$output" | grep -qE '^ok: +bash'
}

@test "doctor flags the WSL risk on Windows and never reports a false all-clear" {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) : ;;
    *) skip "the bare-bash WSL risk is Windows-only" ;;
  esac

  run bash "$DOCTOR"
  [ "$status" -eq 0 ]

  # An earlier version of this check walked $PATH from inside Git Bash, where /usr/bin
  # comes first, and so reported "not WSL" on a machine whose host demonstrably launched
  # WSL. The property under test is that a present System32\bash.exe is never described
  # as safe -- a false green here is worse than no check at all.
  if [ -e "/c/Windows/System32/bash.exe" ]; then
    echo "$output" | grep -qE '^warn: +host bash: .*WSL'
    ! echo "$output" | grep -qE '^ok: +host bash: .*cannot resolve to WSL'
  else
    echo "$output" | grep -qE '^ok: +host bash:'
  fi
}

@test "doctor warns when another host has a different hook copy" {
  copy="$HOME/.gemini/config/plugins/amir-loop/hooks/amir-loop-stop.sh"
  mkdir -p "$(dirname "$copy")"
  printf '%s\n' '# stale Antigravity copy' > "$copy"
  run bash "$DOCTOR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'warn:.*cross-host copy differs.*\.gemini'
}

@test "doctor reports matching cross-host hook copies" {
  copy="$HOME/.vscode/agent-plugins/github.com/Lumvale/amir-loop/plugins/amir-loop/hooks/amir-loop-stop.sh"
  mkdir -p "$(dirname "$copy")"
  cp "$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/amir-loop-stop.sh" "$copy"
  run bash "$DOCTOR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ok:.*cross-host copy matches.*vscode'
  echo "$output" | grep -q 'ok:.*cross-host parity: all discovered copies match'
}

@test "doctor names the principles file in effect" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo "orders" > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$DOCTOR"
  echo "$output" | grep -q "amir-loop-principles.md"
}

@test "doctor reports portable dependency default when no policy exists" {
  cd "$BATS_TEST_TMPDIR"
  run bash "$DOCTOR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'dependencies: no policy found (portable default: off)'
}

@test "doctor reports a declared governed fallback as non-native transport" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cp "$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/templates/lumvaleos-required.json" \
    "$BATS_TEST_TMPDIR/.claude/amir-loop-dependencies.json"
  cd "$BATS_TEST_TMPDIR"
  run bash "$DOCTOR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'fallback transport: governed-cli-mcp-bridge'
  echo "$output" | grep -q 'native transport remains primary'
}

@test "doctor rejects an unapproved fallback tuple" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '%s\n' '{"version":1,"dependencies":[{"id":"lumvaleos","policy":"required","fallback":{"kind":"shell","entrypoint":"write-anything","scope":"write","attempts":999}}]}' > "$BATS_TEST_TMPDIR/.claude/amir-loop-dependencies.json"
  cd "$BATS_TEST_TMPDIR"
  run bash "$DOCTOR"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'dependencies: invalid policy'
}

@test "doctor reports the transport that actually served preflight" {
  mkdir -p "$BATS_TEST_TMPDIR/.lumvaleos"
  printf '%s\n' '{"version":1,"transport":"cli-mcp-bridge","degraded":true,"checked_at":"2026-09-05T00:00:00Z","expires_at_epoch":4102444800,"workspace":"ws-test","evidence":{"attempts":1}}' > "$BATS_TEST_TMPDIR/.lumvaleos/amir-loop-lumvaleos-transport.json"
  cd "$BATS_TEST_TMPDIR"
  AMIR_LOOP_LUMVALEOS_TRANSPORT_RECEIPT="$BATS_TEST_TMPDIR/.lumvaleos/amir-loop-lumvaleos-transport.json" run bash "$DOCTOR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'serving transport: cli-mcp-bridge degraded=true'
  echo "$output" | grep -q 'native MCP is not restored'
}

@test "doctor validates a Bedrock runtime profile without exposing credentials" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  cp "$BATS_TEST_DIRNAME/../templates/runtime/bedrock.json" "$BATS_TEST_TMPDIR/.claude/amir-loop-runtime.json"
  cd "$BATS_TEST_TMPDIR"
  run env CLAUDE_CODE_USE_BEDROCK=1 bash "$DOCTOR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'runtime provider: valid bedrock profile'
  echo "$output" | grep -q 'Bedrock activation signal present'
  ! echo "$output" | grep -Eqi 'AWS_SECRET_ACCESS_KEY|AWS_BEARER_TOKEN_BEDROCK='
}

@test "doctor rejects an incomplete Bedrock runtime profile" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  printf '%s\n' '{"version":1,"provider":"bedrock"}' > "$BATS_TEST_TMPDIR/.claude/amir-loop-runtime.json"
  cd "$BATS_TEST_TMPDIR"
  run bash "$DOCTOR"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'FAIL:.*runtime provider: invalid profile'
}

@test "doctor FAILs when a conflicting ralph-loop stop hook is enabled" {
  run env AMIR_LOOP_FAKE_ENABLED_PLUGINS="ralph-loop@claude-plugins-official" bash "$DOCTOR"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'FAIL:.*ralph-loop'
}

# The three tests below exercise the REAL ~/.claude/settings.json parser - the
# grep/sed extraction that replaced the brief's tr -d approach - with
# AMIR_LOOP_FAKE_ENABLED_PLUGINS deliberately left unset. That env var exists solely to
# make the downstream case-match testable; without a test that goes through the real
# settings.json branch, a regression in the parser itself (e.g. reintroducing
# `tr -d '":true'`) would go undetected by every other test in this file.

write_realistic_settings() {
  # Realistic shape: nested objects, other top-level keys, mixed whitespace, several
  # enabled plugins, and a decoy key ("trueplugin@x") designed to trip a naive matcher
  # that greps for the literal text "ralph-loop" or "true" rather than parsing the
  # actual key/value pairs.
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" <<EOF
{
  "model": "claude-opus-5",
  "statusLine": {
    "type":   "command",
    "command": "some-statusline.sh"
  },
  "enabledPlugins": {
      "superpowers@claude-plugins-official"   :true,
    "trueplugin@x": false,
    "$1": $2,
    "code-review@claude-plugins-official":true
  }
}
EOF
}

@test "doctor FAILs on a real settings.json with ralph-loop enabled (positive, real parser path)" {
  write_realistic_settings "ralph-loop@claude-plugins-official" "true"
  run bash "$DOCTOR"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'FAIL:.*ralph-loop'
}

@test "doctor does not FAIL when ralph-loop is present but disabled (negative, real parser path)" {
  write_realistic_settings "ralph-loop@claude-plugins-official" "false"
  run bash "$DOCTOR"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'FAIL:.*ralph-loop'
}

@test "doctor is not fooled by a decoy key containing t/r/u/e mapped to false" {
  # trueplugin@x:false is present in every realistic-settings fixture already; this test
  # pins that its presence alone (without ralph-loop anywhere in the file) never trips
  # the ralph-loop FAIL.
  write_realistic_settings "some-other-plugin@x" "true"
  run bash "$DOCTOR"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'FAIL:.*ralph-loop'
}

@test "doctor warns about a configured Codex notify hook without changing it" {
  config="$BATS_TEST_TMPDIR/codex-config.toml"
  printf 'notify = ["codex-computer-use.exe", "turn-ended"]\nmodel = "gpt-5.6-sol"\n' > "$config"
  export AMIR_LOOP_CODEX_CONFIG="$config"
  run bash "$DOCTOR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'warn:.*Codex notify hook configured'
  grep -q '^notify = ' "$config"
}

@test "doctor disable backs up and removes a single-line Codex notify hook" {
  config="$BATS_TEST_TMPDIR/codex-config.toml"
  printf 'notify = ["codex-computer-use.exe", "turn-ended"]\nmodel = "gpt-5.6-sol"\n' > "$config"
  export AMIR_LOOP_CODEX_CONFIG="$config"
  run bash "$DOCTOR" --disable-codex-notify
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'ok:.*disabled Codex notify hook'
  ! grep -q '^notify = ' "$config"
  backup_count=$(find "$BATS_TEST_TMPDIR" -name 'codex-config.toml.backup-amir-loop-*' | wc -l)
  [ "$backup_count" -eq 1 ]
  grep -q '^notify = ' "$BATS_TEST_TMPDIR"/codex-config.toml.backup-amir-loop-*
}
