#!/bin/bash
# Portable, fail-open activation adapter. LumvaleOS owns all scheduling decisions.
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 0
PYTHON=${LUMVALEOS_PYTHON:-}
if [ -z "$PYTHON" ]; then
  PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)
fi
[ -n "$PYTHON" ] || exit 0
"$PYTHON" "$SCRIPT_DIR/lumvaleos-reconcile.py" >/dev/null 2>&1 || true
exit 0
