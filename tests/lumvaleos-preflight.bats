SCRIPT="$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/scripts/lumvaleos-preflight.py"

setup() {
  PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)
  ROOT="$BATS_TEST_TMPDIR/lumvaleos"
  mkdir -p "$ROOT"
  cat > "$ROOT/lumvaleos.py" <<'PY'
import json, os, sys, time
mode = os.environ.get("FAKE_MODE", "healthy")
if mode == "timeout": time.sleep(2)
if mode == "malformed": print("not-json"); raise SystemExit(0)
if "lumvaleos_preflight" not in sys.argv: print("wrong-tool"); raise SystemExit(2)
statuses = {name: {"status": "ok"} for name in (
    "workspace", "engine", "graph", "capability_router", "engineering_board",
    "interpreter", "dependencies")}
if mode == "unhealthy": statuses["graph"]["status"] = "unavailable"
if mode == "degraded": statuses["graph"]["status"] = "degraded"
if mode == "status_secret": statuses["graph"]["status"] = "unavailable: token=must-not-escape"
if mode == "secret": print("AWS_SECRET_ACCESS_KEY=must-not-escape")
print("[lumvaleos] diagnostic banner")
print(json.dumps({"ok": True, "result": {"isError": False, "content": [
    {"type": "text", "text": json.dumps(statuses)}]}}))
PY
}

run_bridge() {
  run "$PYTHON" "$SCRIPT" --native-status "${1:-transport_closed}" \
    --workspace ws-test --lumvaleos-root "$ROOT" "${@:2}"
}

@test "healthy governed bridge emits compact degraded evidence" {
  run_bridge
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.ok')" = true ]
  [ "$(echo "$output" | jq -r '.transport')" = cli-mcp-bridge ]
  [ "$(echo "$output" | jq -r '.degraded')" = true ]
  [ "$(echo "$output" | jq -r '.evidence.attempts')" -eq 1 ]
}

@test "fallback is refused for a non-transport capability error" {
  run "$PYTHON" "$SCRIPT" --native-status capability_failed --workspace ws-test
  [ "$status" -eq 2 ]
}


@test "degraded is usable and arbitrary child status text is normalized" {
  FAKE_MODE=degraded run_bridge
  [ "$status" -eq 0 ]
  FAKE_MODE=status_secret run_bridge
  [ "$status" -eq 1 ]
  [[ "$output" != *must-not-escape* ]]
  [ "$(echo "$output" | jq -r '.required_subsystems.graph')" = unknown ]
}

@test "unhealthy authoritative subsystem fails closed" {
  FAKE_MODE=unhealthy run_bridge
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.code')" = preflight-unhealthy ]
  [ "$(echo "$output" | jq -r '.unhealthy[0]')" = graph ]
}

@test "missing checkout and malformed response fail closed" {
  run "$PYTHON" "$SCRIPT" --native-status transport_closed --workspace ws-test \
    --lumvaleos-root "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.code')" = lumvaleos-not-found ]

  FAKE_MODE=malformed run_bridge
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.code')" = bridge-invalid-response ]
}

@test "configured Python command arguments discover the LumvaleOS root" {
  config="$BATS_TEST_TMPDIR/config.toml"
  configured_root="$ROOT"
  if command -v cygpath >/dev/null 2>&1; then
    configured_root=$(cygpath -m "$ROOT")
  fi
  printf '[mcp_servers.lumvaleos]\ncommand = "%s"\nargs = ["%s"]\n' "$PYTHON" "$configured_root/lumvaleos.py" > "$config"
  AMIR_LOOP_CODEX_CONFIG="$config" run "$PYTHON" "$SCRIPT" --native-status transport_unavailable --workspace ws-test
  [ "$status" -eq 0 ]
}

@test "Python 3.9 fallback reads configured command arguments without tomllib" {
  run "$PYTHON" "$BATS_TEST_DIRNAME/test_lumvaleos_preflight.py"
  [ "$status" -eq 0 ]
}

@test "explicit missing interpreter fails closed" {
  LUMVALEOS_PYTHON="$BATS_TEST_TMPDIR/no-python" run_bridge
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.code')" = interpreter-not-found ]
}

@test "timeout is bounded and output never relays child secrets" {
  FAKE_MODE=timeout run_bridge transport_closed --timeout-seconds 0.1
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | jq -r '.code')" = bridge-timeout ]

  FAKE_MODE=secret run_bridge
  [ "$status" -eq 0 ]
  [[ "$output" != *AWS_SECRET_ACCESS_KEY* ]]
  [[ "$output" != *must-not-escape* ]]
}

@test "POSIX wrapper preserves typed status and workspace" {
  run bash "$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/scripts/lumvaleos-preflight.sh" transport_closed ws-test "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.workspace')" = ws-test ]
}

@test "PowerShell wrapper preserves typed status on Windows" {
  case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) : ;; *) skip "PowerShell wrapper is Windows-only" ;; esac
  ps=$(command -v powershell.exe 2>/dev/null || true)
  [ -n "$ps" ] || skip "Windows PowerShell is unavailable"
  run "$ps" -NoProfile -File "$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/scripts/lumvaleos-preflight.ps1" -NativeStatus transport_closed -Workspace ws-test -LumvaleOSRoot "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.transport')" = cli-mcp-bridge ]
}

@test "dependency template declares the governed bridge without calling it native MCP" {
  template="$BATS_TEST_DIRNAME/../plugins/amir-loop-lumvaleos/templates/lumvaleos-required.json"
  [ "$(jq -r '.dependencies[0].fallback.kind' "$template")" = governed-cli-mcp-bridge ]
  jq -e '.dependencies[0].preflight | contains("never record it as native MCP success")' "$template"
}

@test "fallback receipt is scoped and expires" {
  receipt="$BATS_TEST_TMPDIR/transport.json"
  run "$PYTHON" "$SCRIPT" --native-status transport_closed --workspace ws-test \
    --lumvaleos-root "$ROOT" --receipt-path "$receipt"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.workspace' "$receipt")" = ws-test ]
  [ "$(jq -r '.transport' "$receipt")" = cli-mcp-bridge ]
  [ "$(jq -r '.expires_at_epoch > 0' "$receipt")" = true ]
}
