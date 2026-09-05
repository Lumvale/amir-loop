SCRIPT="$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/scripts/lumvaleos-reconcile.py"

@test "activation delegates reconciliation to LumvaleOS and waits only in the test seam" {
  root="$BATS_TEST_TMPDIR/lumvale-os"
  mkdir -p "$root"
  cat > "$root/lumvaleos.py" <<'PY'
import os
from pathlib import Path
import sys
Path(os.environ["RECONCILE_CAPTURE"]).write_text(" ".join(sys.argv[1:]), encoding="utf-8")
PY
  capture="$BATS_TEST_TMPDIR/capture"
  runtime_root="$root"
  runtime_capture="$capture"
  if [[ "${OSTYPE:-}" == msys* ]]; then
    # Environment values are not argv and MSYS does not translate them for native Python.
    runtime_root=$(cygpath -w "$root")
    runtime_capture=$(cygpath -w "$capture")
  fi
  LUMVALEOS_ROOT="$runtime_root" LUMVALEOS_PYTHON="$(command -v python)" \
    RECONCILE_CAPTURE="$runtime_capture" AMIR_LOOP_RECONCILE_FOREGROUND=1 run python "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(cat "$capture")" = "scheduler run --json" ]
}

@test "missing LumvaleOS is a quiet fail-open no-op" {
  LUMVALEOS_ROOT="$BATS_TEST_TMPDIR/missing" run python "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Codex MCP configuration locates LumvaleOS outside the current repository" {
  root="$BATS_TEST_TMPDIR/configured-lumvale-os"
  mkdir -p "$root"
  touch "$root/lumvaleos.py"
  config="$BATS_TEST_TMPDIR/config.toml"
  runtime_root="$root"
  runtime_script="$SCRIPT"
  if [[ "${OSTYPE:-}" == msys* ]]; then
    runtime_root=$(cygpath -m "$root")
    runtime_script=$(cygpath -w "$SCRIPT")
  fi
  printf '[mcp_servers.lumvaleos]\ncommand = "%s/lumvaleos.py"\n' "$runtime_root" > "$config"
  AMIR_LOOP_CODEX_CONFIG="$config" LUMVALEOS_ROOT= run python -c \
    "import importlib.util; s=importlib.util.spec_from_file_location('r', r'$runtime_script'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print(m.lumvaleos_root())"
  [ "$status" -eq 0 ]
  [[ "$output" == *configured-lumvale-os* ]]
}

@test "companion plugin wakes on session and prompt activation, never on a timer" {
  hooks="$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/hooks.json"
  jq -e '.hooks.SessionStart and .hooks.UserPromptSubmit' "$hooks"
  ! grep -Eqi 'cron|schedule|Task Scheduler' "$hooks"
}
