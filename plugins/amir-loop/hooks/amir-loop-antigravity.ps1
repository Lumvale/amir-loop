# Google Antigravity adapter for the shared Amir Loop Bash hook.
#
# Antigravity uses camelCase input and expects {"decision":"continue"}; Claude,
# Copilot, and Codex use snake_case input and a block decision. Keep the loop logic in
# one Bash implementation and translate only the host contract here. Every adapter
# failure is fail-open and returns a non-continuation decision.

function Write-StopDecision {
    param([string]$Decision, [string]$Reason = '')

    $result = @{ decision = $Decision }
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        $result.reason = $Reason
    }
    $result | ConvertTo-Json -Compress
}

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop
    $workspace = @($payload.workspacePaths) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($workspace)) {
        Write-StopDecision 'stop'
        exit 0
    }

    $canonical = @{
        cwd = $workspace
        session_id = [string]$payload.conversationId
        transcript_path = [string]$payload.transcriptPath
        error = [string]$payload.error
        model = [string]$payload.modelName
        termination_reason = [string]$payload.terminationReason
    } | ConvertTo-Json -Compress

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $gitCommand) {
        Write-StopDecision 'stop'
        exit 0
    }
    $gitRoot = Split-Path -Parent (Split-Path -Parent $gitCommand.Source)
    $gitBash = @(
        (Join-Path $gitRoot 'bin\bash.exe'),
        (Join-Path $gitRoot 'usr\bin\bash.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $hook = Join-Path $PSScriptRoot 'amir-loop-stop.sh'
    if ([string]::IsNullOrWhiteSpace($gitBash) -or -not (Test-Path -LiteralPath $hook)) {
        Write-StopDecision 'stop'
        exit 0
    }

    $raw = $canonical | & $gitBash $hook | Out-String
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-StopDecision 'stop'
        exit 0
    }
    $shared = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($shared.decision -eq 'block' -and -not [string]::IsNullOrWhiteSpace($shared.reason)) {
        Write-StopDecision 'continue' ([string]$shared.reason)
    }
    else {
        Write-StopDecision 'stop'
    }
}
catch {
    Write-StopDecision 'stop'
}

exit 0
