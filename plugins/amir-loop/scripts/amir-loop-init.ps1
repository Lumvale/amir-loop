[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path -Parent $PSScriptRoot
$template = Join-Path $pluginRoot 'templates\principles\lumvale-fleet.md'
$project = [System.IO.Path]::GetFullPath($ProjectRoot)
$targetDirectory = Join-Path $project '.claude'
$target = Join-Path $targetDirectory 'amir-loop-principles.md'

if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
    throw "The packaged Amir Loop principles template is missing: $template"
}
if (-not (Test-Path -LiteralPath $project -PathType Container)) {
    throw "The project root does not exist or is not a directory: $project"
}
if (Test-Path -LiteralPath $target) {
    Get-Content -LiteralPath $target -Raw
    Write-Warning "Existing principles were preserved without modification: $target"
    exit 0
}

New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
Copy-Item -LiteralPath $template -Destination $target
Write-Output "Created: $target"
Write-Output 'Next: fill the Backlog, Merge authority, Definition of done, and Never placeholders.'
