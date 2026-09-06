[CmdletBinding()]
param(
    [ValidateSet('status', 'doctor')]
    [string]$Command = 'status',
    [string]$CacheRoot,
    [string]$InstalledRoot,
    [switch]$Json,
    [switch]$DisableCodexNotify,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArguments
)

$ErrorActionPreference = 'Stop'

$forwardedArguments = if ($null -eq $CommandArguments) { @() } else { @($CommandArguments) }
if ($DisableCodexNotify) {
    if ($Command -ne 'doctor') {
        throw '-DisableCodexNotify is valid only with the doctor command.'
    }
}

function Test-AmirLoopRoot {
    param([Parameter(Mandatory)][string]$Root)

    $manifest = Join-Path $Root '.claude-plugin\plugin.json'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        return $false
    }

    try {
        $metadata = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    }
    catch {
        return $false
    }

    if ($metadata.name -ne 'amir-loop') {
        return $false
    }

    $scriptBase = Join-Path $Root "scripts\amir-loop-$Command"
    return (Test-Path -LiteralPath "$scriptBase.ps1" -PathType Leaf) -or
        (Test-Path -LiteralPath "$scriptBase.sh" -PathType Leaf)
}

if ($InstalledRoot) {
    $resolvedRoot = [System.IO.Path]::GetFullPath($InstalledRoot)
    if (-not (Test-AmirLoopRoot -Root $resolvedRoot)) {
        throw "The explicit Amir Loop root is invalid or lacks the '$Command' entrypoint: $resolvedRoot"
    }
}
else {
    if (-not $CacheRoot) {
        $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
        $CacheRoot = Join-Path $codexHome 'plugins\cache\lumvale\amir-loop'
    }

    if (-not (Test-Path -LiteralPath $CacheRoot -PathType Container)) {
        throw "Amir Loop's Codex cache directory does not exist: $CacheRoot"
    }

    # Cache directory names contain a semantic version plus an optional monotonically
    # increasing Codex build suffix. Parse both components: lexical sorting would
    # incorrectly rank 1.9 above 1.10, while filesystem timestamps are mutable.
    $validRoots = @(
        Get-ChildItem -LiteralPath $CacheRoot -Directory |
            ForEach-Object {
                if ($_.Name -match '^(?<version>\d+\.\d+\.\d+)(?:[^+]*)?(?:\+codex\.(?<build>\d+))?$' -and
                    (Test-AmirLoopRoot -Root $_.FullName)) {
                    [pscustomobject]@{
                        Directory = $_
                        Version = [version]$Matches.version
                        Build = if ($Matches.build) { [decimal]$Matches.build } else { [decimal]0 }
                    }
                }
            } |
            Sort-Object -Property @{ Expression = 'Version'; Descending = $true },
                @{ Expression = 'Build'; Descending = $true },
                @{ Expression = { $_.Directory.Name }; Descending = $true }
    )
    if ($validRoots.Count -eq 0) {
        throw "No valid Amir Loop installation with a '$Command' entrypoint exists under: $CacheRoot"
    }
    $resolvedRoot = $validRoots[0].Directory.FullName
}

$nativeScript = Join-Path $resolvedRoot "scripts\amir-loop-$Command.ps1"
if (Test-Path -LiteralPath $nativeScript -PathType Leaf) {
    $nativeArguments = @($forwardedArguments)
    if ($Json) { $nativeArguments += '-Json' }
    if ($DisableCodexNotify) { $nativeArguments += '-DisableCodexNotify' }
    $powerShellHost = (Get-Process -Id $PID).Path
    & $powerShellHost -NoProfile -ExecutionPolicy Bypass -File $nativeScript @nativeArguments
    exit $LASTEXITCODE
}

$shellScript = Join-Path $resolvedRoot "scripts/amir-loop-$Command.sh"
$git = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $git) {
    throw "The '$Command' entrypoint requires Git for Windows Bash, but git.exe was not found."
}
$gitDirectory = Split-Path -Parent $git.Source
$gitParent = Split-Path -Parent $gitDirectory
$bashCandidates = @(
    (Join-Path $gitParent 'bin\bash.exe'),
    (Join-Path (Split-Path -Parent $gitParent) 'bin\bash.exe')
)
$bash = $bashCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $bash) {
    throw "Git for Windows Bash was not found from git.exe: $($git.Source)"
}
$convertedScript = & $bash -lc 'cygpath -u -- "$1"' -- $shellScript
$conversionExit = $LASTEXITCODE
$posixScript = if ($null -eq $convertedScript) { '' } else { ([string]$convertedScript).Trim() }
if ($conversionExit -ne 0 -or -not $posixScript) {
    throw "Git for Windows could not convert the '$Command' entrypoint path: $shellScript"
}
$shellArguments = @($forwardedArguments)
if ($Json) { $shellArguments += '--json' }
if ($DisableCodexNotify) { $shellArguments += '--disable-codex-notify' }
& $bash $posixScript @shellArguments
exit $LASTEXITCODE
