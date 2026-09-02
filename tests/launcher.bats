load helper

HOOKS_JSON="$BATS_TEST_DIRNAME/../plugins/amir-loop/hooks/hooks.json"

# Every host-facing launcher command in hooks.json, one per line.
launcher_commands() {
  jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$HOOKS_JSON"
}

# A stand-in plugin root whose hook script only reports that it was reached, so these
# tests measure the launcher's path resolution and nothing about the real hook.
fake_root() {
  mkdir -p "$BATS_TEST_TMPDIR/root/hooks"
  printf '%s\n' '#!/usr/bin/env bash' 'echo LAUNCHER_REACHED_SCRIPT' \
    > "$BATS_TEST_TMPDIR/root/hooks/amir-loop-stop.sh"
}

# The defect this file exists for: the launcher used to pipe the plugin root through
# `xargs`, which treats a backslash in its input as an escape. A Windows
# CLAUDE_PLUGIN_ROOT therefore arrived with every separator stripped
# (C:\Users\... -> C:Users...), the script was never found, and the Stop hook became a
# silent no-op on which no loop could ever arm.
@test "no launcher pipes the plugin root through xargs" {
  run launcher_commands
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'xargs'
}

@test "launchers resolve a POSIX plugin root" {
  fake_root
  while IFS= read -r cmd; do
    out=$(CLAUDE_PLUGIN_ROOT="$BATS_TEST_TMPDIR/root" PLUGIN_ROOT= CODEX_PLUGIN_ROOT= \
      bash -c "$cmd" </dev/null 2>/dev/null)
    [ "$out" = "LAUNCHER_REACHED_SCRIPT" ] || { echo "unreached: $cmd"; return 1; }
  done < <(launcher_commands)
}

@test "launchers resolve a Windows plugin root with backslash separators" {
  command -v cygpath >/dev/null 2>&1 || skip "cygpath is Windows-only"
  fake_root
  win_root=$(cygpath -w "$BATS_TEST_TMPDIR/root")
  while IFS= read -r cmd; do
    out=$(CLAUDE_PLUGIN_ROOT="$win_root" PLUGIN_ROOT= CODEX_PLUGIN_ROOT= \
      bash -c "$cmd" </dev/null 2>/dev/null)
    [ "$out" = "LAUNCHER_REACHED_SCRIPT" ] || { echo "unreached: $cmd"; return 1; }
  done < <(launcher_commands)
}

@test "a launcher with no plugin root in the environment fails open" {
  while IFS= read -r cmd; do
    CLAUDE_PLUGIN_ROOT= PLUGIN_ROOT= CODEX_PLUGIN_ROOT= \
      bash -c "$cmd" </dev/null >/dev/null 2>&1 || { echo "not fail-open: $cmd"; return 1; }
  done < <(launcher_commands)
}
