[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('transport_closed', 'transport_unavailable')]
    [string]$NativeStatus,
    [Parameter(Mandatory = $true)][string]$Workspace,
    [string]$LumvaleOSRoot,
    [double]$TimeoutSeconds = 30,
    [string]$ReceiptPath
)

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'lumvaleos-preflight.py'
$python = if ($env:LUMVALEOS_PYTHON) { $env:LUMVALEOS_PYTHON } else { $null }
if (-not $python -and $LumvaleOSRoot) {
    foreach ($relative in @('venv\Scripts\python.exe', '.venv\Scripts\python.exe')) {
        $candidate = Join-Path $LumvaleOSRoot $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $python = $candidate; break }
    }
}
if (-not $python) {
    $resolved = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($resolved) { $python = $resolved.Source }
}
if (-not $python) {
    [Console]::Error.WriteLine('No Python interpreter found; set LUMVALEOS_PYTHON.')
    exit 1
}

$arguments = @($script, '--native-status', $NativeStatus, '--workspace', $Workspace, '--timeout-seconds', $TimeoutSeconds)
if ($LumvaleOSRoot) { $arguments += @('--lumvaleos-root', $LumvaleOSRoot) }
if ($ReceiptPath) { $arguments += @('--receipt-path', $ReceiptPath) }
& $python @arguments
exit $LASTEXITCODE
