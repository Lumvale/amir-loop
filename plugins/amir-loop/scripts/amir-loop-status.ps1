[CmdletBinding()]
param(
    [switch]$Json,
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Session
)

$ErrorActionPreference = 'Stop'
$statusScript = Join-Path $PSScriptRoot 'amir-loop-status.sh'
$candidates = @(
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
    $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe' }),
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
$pathCandidates = @(Get-Command bash.exe -All -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Source |
    Where-Object {
        $_ -and
        $_ -notlike "$env:SystemRoot\System32\*" -and
        $_ -notlike "$env:LOCALAPPDATA\Microsoft\WindowsApps\*" -and
        (Test-Path -LiteralPath $_ -PathType Leaf)
    })
$allCandidates = @()
$allCandidates += $candidates
$allCandidates += $pathCandidates
$gitBash = $allCandidates | Select-Object -Unique | Select-Object -First 1
if (-not $gitBash) {
    Write-Error 'Git for Windows Bash was not found. Install Git for Windows or use the POSIX status entrypoint with a known non-WSL Bash.'
    exit 1
}

$arguments = @($statusScript.Replace('\', '/'))
if ($Json) { $arguments += '--json' }
if ($Session) { $arguments += @('--session', $Session) }
& $gitBash @arguments
exit $LASTEXITCODE
