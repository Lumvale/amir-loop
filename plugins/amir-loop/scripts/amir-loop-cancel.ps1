[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if ($args.Count -ne 0) {
    throw 'amir-loop-cancel does not accept arguments.'
}

$setup = Join-Path $PSScriptRoot 'amir-loop-setup.ps1'
if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
    throw "The native Amir Loop setup entrypoint is missing: $setup"
}

# Keep interpreter discovery and cross-host cancellation semantics in one owner. The fixed
# -Cancel switch cannot be influenced by user input and setup.ps1 forwards only `--cancel`.
& $setup -Cancel
exit $LASTEXITCODE
