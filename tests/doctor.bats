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

@test "doctor names the principles file in effect" {
  mkdir -p "$BATS_TEST_TMPDIR/.claude"
  echo "orders" > "$BATS_TEST_TMPDIR/.claude/amir-loop-principles.md"
  cd "$BATS_TEST_TMPDIR"
  run bash "$DOCTOR"
  echo "$output" | grep -q "amir-loop-principles.md"
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
