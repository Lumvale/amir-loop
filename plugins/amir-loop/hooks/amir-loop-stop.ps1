# Windows launcher for the shared Bash hook.
#
# Codex executes commandWindows through the Windows command shell. A bare `bash` can
# resolve to WSL's C:\Windows\System32\bash.exe, which cannot consume the Windows plugin
# path. Locate the Git for Windows Bash beside the active git.exe instead. Any launcher
# failure is fail-open, matching the hook's safety contract.

function Write-AmirLoopDebug {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($env:AMIR_LOOP_DEBUG_LOG)) {
        return
    }

    try {
        Add-Content -LiteralPath $env:AMIR_LOOP_DEBUG_LOG -Value $Message -ErrorAction Stop
    }
    catch {
        # Diagnostics must never turn a Stop hook into a failure.
    }
}

$payload = [Console]::In.ReadToEnd()
$pluginRoot = $env:PLUGIN_ROOT
if ([string]::IsNullOrWhiteSpace($pluginRoot)) {
    $pluginRoot = $env:CLAUDE_PLUGIN_ROOT
}
if ([string]::IsNullOrWhiteSpace($pluginRoot)) {
    Write-AmirLoopDebug 'No PLUGIN_ROOT or CLAUDE_PLUGIN_ROOT was provided.'
    exit 0
}

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $gitCommand) {
    Write-AmirLoopDebug 'git.exe was not available on PATH.'
    exit 0
}

$gitRoot = Split-Path -Parent (Split-Path -Parent $gitCommand.Source)
$candidates = @(
    (Join-Path $gitRoot 'bin\bash.exe'),
    (Join-Path $gitRoot 'usr\bin\bash.exe')
)
$gitBash = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($gitBash)) {
    Write-AmirLoopDebug "Git Bash was not found below $gitRoot."
    exit 0
}

$hook = Join-Path $pluginRoot 'hooks\amir-loop-stop.sh'
if (-not (Test-Path -LiteralPath $hook)) {
    Write-AmirLoopDebug "The shared hook was not found at $hook."
    exit 0
}

Write-AmirLoopDebug "Launching $gitBash $hook with $($payload.Length) input characters."
try {
    $payload | & $gitBash $hook
    $hookExitCode = $LASTEXITCODE
}
catch {
    Write-AmirLoopDebug "Git Bash could not be launched: $($_.Exception.Message)"
    exit 0
}

if ($null -eq $hookExitCode) {
    $hookExitCode = 0
}
Write-AmirLoopDebug "The shared hook exited with code $hookExitCode."
if ($hookExitCode -ne 0) {
    [Console]::Error.WriteLine("Amir Loop shared hook exited with code $hookExitCode; allowing Codex to stop.")
}

# Fail open. A bridge or Bash failure must never trap the host in a session it cannot end.
exit 0
