[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Start')]
    [string]$Prompt,
    [Parameter(Mandatory, ParameterSetName = 'Cancel')]
    [switch]$Cancel
)

$ErrorActionPreference = 'Stop'
$setupScript = Join-Path $PSScriptRoot 'amir-loop-setup.sh'

# Resolve Bash from git.exe instead of PATH. On Windows, a bare `bash` commonly
# selects System32/WSL, which cannot consume the host's Windows plugin path.
$git = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $git) {
    throw 'Git for Windows was not found. Install it before starting or cancelling Amir Loop.'
}
$gitDirectory = Split-Path -Parent $git.Source
$gitParent = Split-Path -Parent $gitDirectory
$bashCandidates = @(
    (Join-Path $gitParent 'bin\bash.exe'),
    (Join-Path (Split-Path -Parent $gitParent) 'bin\bash.exe')
)
$gitBash = $bashCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $gitBash) {
    throw "Git for Windows Bash was not found from git.exe: $($git.Source)"
}

$convertedScript = & $gitBash -lc 'cygpath -u -- "$1"' -- $setupScript
$conversionExit = $LASTEXITCODE
$posixScript = if ($null -eq $convertedScript) { '' } else { ([string]$convertedScript).Trim() }
if ($conversionExit -ne 0 -or -not $posixScript) {
    throw "Git for Windows could not convert the setup entrypoint path: $setupScript"
}

$arguments = @()
if ($Cancel) {
    $arguments += '--cancel'
}
else {
    $arguments += $Prompt
}
& $gitBash $posixScript @arguments
exit $LASTEXITCODE
