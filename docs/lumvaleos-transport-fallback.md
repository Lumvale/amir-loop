# Governed LumvaleOS transport fallback

Native MCP remains the primary LumvaleOS transport. If the host returns a typed transport failure,
the `amir-loop-lumvaleos` companion can verify the read-only CLI-to-MCP bridge once:

```powershell
./plugins/amir-loop-lumvaleos/scripts/lumvaleos-preflight.ps1 `
  -NativeStatus transport_closed -Workspace workspace-name `
  -ReceiptPath (Join-Path $env:WORKSPACE_ROOT '.lumvaleos/amir-loop-lumvaleos-transport.json')
```

```bash
plugins/amir-loop-lumvaleos/scripts/lumvaleos-preflight.sh \
  transport_closed workspace-name '' 30 \
  "$WORKSPACE_ROOT/.lumvaleos/amir-loop-lumvaleos-transport.json"
```

The adapter accepts only typed transport statuses, discovers the configured LumvaleOS checkout,
invokes only `lumvaleos_preflight`, and accepts the bridge only when every governance-critical
subsystem is usable. Its single-line JSON
result names `transport=cli-mcp-bridge` and `degraded=true`; it never calls the original capability,
replays a write, puts raw host errors in process arguments, emits raw stderr, or claims native MCP
recovered. Native transport receipts are written only by Amir Loop's successful MCP post-tool
observer. Both native and fallback receipts expire after 15 minutes, so doctor output cannot treat
old evidence as the currently serving transport.

This is continuity, not reconnection. [LumvaleOS #3468](https://github.com/Lumvale/lumvale-os/issues/3468)
owns app-host process reconnection when the host exposes a restartable boundary. Amir Loop
[issue #45](https://github.com/Lumvale/amir-loop/issues/45) owns this governed fallback.
