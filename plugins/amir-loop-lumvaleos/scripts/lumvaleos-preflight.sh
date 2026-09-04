#!/bin/bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo 'usage: lumvaleos-preflight.sh NATIVE_STATUS WORKSPACE [LUMVALEOS_ROOT] [TIMEOUT_SECONDS] [RECEIPT_PATH]' >&2
  exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
NATIVE_STATUS=$1
WORKSPACE=$2
ROOT=${3:-}
TIMEOUT=${4:-30}
RECEIPT=${5:-}
PYTHON=${LUMVALEOS_PYTHON:-}
if [ -z "$PYTHON" ] && [ -n "$ROOT" ]; then
  for candidate in "$ROOT/venv/bin/python" "$ROOT/.venv/bin/python" "$ROOT/venv/Scripts/python.exe" "$ROOT/.venv/Scripts/python.exe"; do
    [ -f "$candidate" ] && PYTHON=$candidate && break
  done
fi
if [ -z "$PYTHON" ]; then
  PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)
fi
if [ -z "$PYTHON" ]; then
  echo 'No Python interpreter found; set LUMVALEOS_PYTHON.' >&2
  exit 1
fi

ARGS=("$SCRIPT_DIR/lumvaleos-preflight.py" --native-status "$NATIVE_STATUS" --workspace "$WORKSPACE" --timeout-seconds "$TIMEOUT")
[ -n "$ROOT" ] && ARGS+=(--lumvaleos-root "$ROOT")
[ -n "$RECEIPT" ] && ARGS+=(--receipt-path "$RECEIPT")
exec "$PYTHON" "${ARGS[@]}"
