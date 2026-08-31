# Google Antigravity adapter for the shared Amir Loop Bash hook.
#
# Antigravity uses camelCase input and host-specific lifecycle output; Claude, Copilot,
# and Codex use snake_case input. Keep loop and event logic in one Bash implementation
# and translate only the host contract here. Every adapter failure is fail-open.

param(
    [ValidateSet('Stop', 'PreInvocation', 'SourceChanged', 'CommandCompleted', 'EnvironmentReachable', 'LearningDiscovered')]
    [string]$Event = 'Stop'
)

function Write-StopDecision {
    param([string]$Decision, [string]$Reason = '')

    $result = @{ decision = $Decision }
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        $result.reason = $Reason
    }
    $result | ConvertTo-Json -Compress
}

function Write-FailOpen {
    if ($Event -eq 'Stop') {
        Write-StopDecision 'stop'
    }
    else {
        '{}'
    }
}

try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop
    $workspace = @($payload.workspacePaths) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($workspace)) {
        Write-FailOpen
        exit 0
    }

    $canonicalPayload = @{
        cwd = $workspace
        session_id = [string]$payload.conversationId
        transcript_path = [string]$payload.transcriptPath
        error = [string]$payload.error
        model = [string]$payload.modelName
        termination_reason = [string]$payload.terminationReason
    }

    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $gitCommand) {
        Write-FailOpen
        exit 0
    }
    $gitRoot = Split-Path -Parent (Split-Path -Parent $gitCommand.Source)
    $gitRootParent = Split-Path -Parent $gitRoot
    $gitBash = @(
        (Join-Path $gitRoot 'bin\bash.exe'),
        (Join-Path $gitRoot 'usr\bin\bash.exe'),
        (Join-Path $gitRootParent 'bin\bash.exe'),
        (Join-Path $gitRootParent 'usr\bin\bash.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $hook = Join-Path $PSScriptRoot 'amir-loop-stop.sh'
    if ([string]::IsNullOrWhiteSpace($gitBash) -or -not (Test-Path -LiteralPath $hook)) {
        Write-FailOpen
        exit 0
    }

    if ($Event -eq 'PreInvocation') {
        # Antigravity has no UserPromptSubmit hook. Its documented PreInvocation payload
        # carries transcriptPath, so the shared observer derives the latest user prompt
        # from that transcript for exact-output contracts and also emits the idempotent
        # session.started/sparse-heartbeat pair. Both calls are best-effort and emit no
        # host instructions.
        $canonical = $canonicalPayload | ConvertTo-Json -Compress
        $null = $canonical | & $gitBash $hook '--observe=user-prompt' | Out-String
        $null = $canonical | & $gitBash $hook '--observe=session.started' | Out-String
        '{}'
        exit 0
    }

    if ($Event -eq 'SourceChanged') {
        $canonicalPayload.turn_id = [string]$payload.stepIdx
        $canonical = $canonicalPayload | ConvertTo-Json -Compress
        $null = $canonical | & $gitBash $hook '--observe=source.changed' | Out-String
        '{}'
        exit 0
    }

    if ($Event -eq 'CommandCompleted') {
        if (-not [string]::IsNullOrWhiteSpace([string]$payload.error)) {
            $canonicalPayload.turn_id = [string]$payload.stepIdx
            $canonicalPayload.tool_name = 'Bash'
            $canonicalPayload.tool_input = @{ command = [string]$payload.error }
            $canonicalPayload.tool_response = @{ exit_code = 1 }
            $canonical = $canonicalPayload | ConvertTo-Json -Compress -Depth 4
            $null = $canonical | & $gitBash $hook '--observe=post-tool' | Out-String
        }
        '{}'
        exit 0
    }

    if ($Event -eq 'EnvironmentReachable' -or $Event -eq 'LearningDiscovered') {
        if ([string]::IsNullOrWhiteSpace([string]$payload.error)) {
            $canonicalPayload.turn_id = [string]$payload.stepIdx
            $observed = if ($Event -eq 'EnvironmentReachable') { 'environment.reachable' } else { 'learning.discovered' }
            $canonical = $canonicalPayload | ConvertTo-Json -Compress
            $null = $canonical | & $gitBash $hook "--observe=$observed" | Out-String
        }
        '{}'
        exit 0
    }

    $canonical = $canonicalPayload | ConvertTo-Json -Compress
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
    Write-FailOpen
}

exit 0
