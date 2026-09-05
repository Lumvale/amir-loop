# Cross-platform policy, Windows launcher only. This is an activation hook, not a scheduled task.
$script = Join-Path $PSScriptRoot 'lumvaleos-reconcile.py'
$python = if ($env:LUMVALEOS_PYTHON) { $env:LUMVALEOS_PYTHON } else { $null }
if (-not $python) {
    $resolved = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($resolved) { $python = $resolved.Source }
}
if (-not $python) { exit 0 }
try { & $python $script } catch { exit 0 }
exit 0
