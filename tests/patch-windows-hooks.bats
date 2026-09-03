load helper

# scripts/patch-windows-hooks.sh points a hooks.json's launchers at an explicit interpreter,
# because on a Windows host `bash` resolves to WSL, which strips variable references from a
# `-c` string before bash parses it. See docs/windows-wsl-hooks.md and issue #30.
#
# These tests pass `--bash` explicitly with a stand-in executable, so they measure the rewrite
# and never depend on Git Bash actually being installed. That keeps them meaningful on the
# ubuntu and macos runners too, where the real probe would find nothing.

SCRIPT="$BATS_TEST_DIRNAME/../plugins/amir-loop/scripts/patch-windows-hooks.sh"
SHIPPED="$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/hooks.json"

# A plugin root laid out the way the script expects: <root>/hooks/hooks.json.
setup_target() {
  mkdir -p "$BATS_TEST_TMPDIR/root/hooks"
  cp "$SHIPPED" "$BATS_TEST_TMPDIR/root/hooks/hooks.json"
  TARGET="$BATS_TEST_TMPDIR/root/hooks/hooks.json"
  FAKE_BASH="$BATS_TEST_TMPDIR/fake-bash.exe"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_BASH"
  chmod +x "$FAKE_BASH"
}

commands_of() {
  jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$1"
}

@test "patch-windows-hooks.sh is executable and has a usage message" {
  [ -f "$SCRIPT" ]
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: patch-windows-hooks.sh"* ]]
}

@test "--check reports the shipped launchers as unpinned, without calling them broken" {
  setup_target
  run bash "$SCRIPT" --check --bash "$FAKE_BASH" "$TARGET"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not pinned to an explicit interpreter"* ]]

  # The shipped launcher is correct on any host that resolves `bash` to Git Bash, so this
  # must not read as a fault -- pinning a working host is pointless churn. It should say
  # how to tell the difference instead.
  [[ "$output" != *"broken"* ]]
  [[ "$output" == *"Get-Command bash"* ]]
}

@test "patching rewrites every launcher to the named interpreter" {
  setup_target
  run bash "$SCRIPT" --bash "$FAKE_BASH" "$TARGET"
  [ "$status" -eq 0 ]

  # Assert the intent, not a literal path: the rendering is platform-dependent (cygpath
  # produces a drive-letter path on Windows, and shortens to 8.3 when a component contains
  # a space), so pinning the exact string would pass on ubuntu/macos and fail on windows --
  # green on two platforms for the wrong reason.
  while IFS= read -r cmd; do
    first=${cmd%% *}
    [[ "$cmd" != *"bash -lc"* ]]      || { echo "still shell-wrapped: $cmd"; return 1; }
    [[ "$cmd" != *'$'* ]]             || { echo "still has a variable: $cmd"; return 1; }
    [[ "$cmd" == *"/hooks/amir-loop-stop.sh"* ]] || { echo "no script: $cmd"; return 1; }
    # The interpreter must be named by an absolute path, POSIX or drive-letter.
    [[ "$first" == /* || "$first" =~ ^[A-Za-z]:/ ]] || { echo "not absolute: $cmd"; return 1; }
    # And no spaces before the script argument, or a PowerShell host cannot parse it.
    [[ "$first" != *" "* ]]           || { echo "interpreter has a space: $cmd"; return 1; }
  done < <(commands_of "$TARGET")
}

@test "an interpreter path containing a space is rendered without one" {
  setup_target
  spaced="$BATS_TEST_TMPDIR/fake bash.exe"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$spaced"
  chmod +x "$spaced"

  run bash "$SCRIPT" --bash "$spaced" "$TARGET"
  if [ "$status" -eq 3 ]; then
    # No cygpath (a non-Windows host): refusing is the documented behaviour, because a
    # leading quoted path is a PowerShell parser error and there is no other safe form.
    [[ "$output" == *"contains a space"* ]]
    return 0
  fi
  [ "$status" -eq 0 ]

  # On Windows the space must be gone, or a PowerShell host cannot parse the command.
  while IFS= read -r cmd; do
    first=${cmd%% *}
    [[ "$first" != *" "* ]] || { echo "space survived: $cmd"; return 1; }
    [[ "$first" == *.[Ee][Xx][Ee] ]] || { echo "not the interpreter: $first"; return 1; }
  done < <(commands_of "$TARGET")
}

@test "patching preserves each hook's own --observe event" {
  setup_target
  before=$(commands_of "$TARGET" | grep -o -- '--observe=[A-Za-z.-]*' | sort)
  run bash "$SCRIPT" --bash "$FAKE_BASH" "$TARGET"
  [ "$status" -eq 0 ]
  after=$(commands_of "$TARGET" | grep -o -- '--observe=[A-Za-z.-]*' | sort)
  [ "$before" = "$after" ]
}

@test "patching is idempotent and --check then passes" {
  setup_target
  run bash "$SCRIPT" --bash "$FAKE_BASH" "$TARGET"
  [ "$status" -eq 0 ]
  first=$(cat "$TARGET")

  run bash "$SCRIPT" --bash "$FAKE_BASH" "$TARGET"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no change needed"* ]]
  [ "$first" = "$(cat "$TARGET")" ]

  run bash "$SCRIPT" --check --bash "$FAKE_BASH" "$TARGET"
  [ "$status" -eq 0 ]
}

@test "patching writes a backup beside the target" {
  setup_target
  run bash "$SCRIPT" --bash "$FAKE_BASH" "$TARGET"
  [ "$status" -eq 0 ]
  ls "$BATS_TEST_TMPDIR/root/hooks/"hooks.json.bak-windows-hooks-* >/dev/null
}

@test "a missing target and an unknown option are refused, not silently ignored" {
  setup_target
  run bash "$SCRIPT" --bash "$FAKE_BASH" "$BATS_TEST_TMPDIR/nope.json"
  [ "$status" -eq 2 ]

  run bash "$SCRIPT" --nonsense "$TARGET"
  [ "$status" -eq 2 ]

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
}

@test "a manifest of the wrong shape is refused by name, not by a jq error" {
  setup_target
  # The plugin ships TWO files called hooks.json: hooks/hooks.json (a top-level .hooks map)
  # and hooks.json (Antigravity-native, keyed by plugin name). Aiming at the wrong one is a
  # foreseeable mistake, and it used to surface as jq's "null (null) has no keys".
  wrong="$BATS_TEST_TMPDIR/root/hooks/antigravity.json"
  cp "$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks.json" "$wrong"
  original=$(cat "$wrong")

  run bash "$SCRIPT" --bash "$FAKE_BASH" "$wrong"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a Claude/Copilot hooks manifest"* ]]
  [[ "$output" != *"has no keys"* ]]
  [ "$original" = "$(cat "$wrong")" ]
}

@test "an unusable interpreter is refused rather than written into the file" {
  setup_target
  original=$(cat "$TARGET")
  run bash "$SCRIPT" --bash "$BATS_TEST_TMPDIR/does-not-exist.exe" "$TARGET"
  [ "$status" -eq 3 ]
  [ "$original" = "$(cat "$TARGET")" ]
}
