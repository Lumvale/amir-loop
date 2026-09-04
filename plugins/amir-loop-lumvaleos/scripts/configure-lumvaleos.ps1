[CmdletBinding()]
param(
    [ValidateSet('required', 'preferred', 'off')]
    [string]$Mode = 'required'
)

$ErrorActionPreference = 'Stop'
$selectedRoot = if ($env:AMIR_LOOP_WORKSPACE_ROOT) {
    $env:AMIR_LOOP_WORKSPACE_ROOT
}
elseif ($env:WORKSPACE_ROOT) {
    $env:WORKSPACE_ROOT
}
else {
    (Get-Location).Path
}
$explicitSelection = [bool]($env:AMIR_LOOP_WORKSPACE_ROOT -or $env:WORKSPACE_ROOT)
$selectedRoot = [System.IO.Path]::GetFullPath($selectedRoot)
if ($explicitSelection -and -not (Test-Path -LiteralPath (Join-Path $selectedRoot 'workspace.yaml') -PathType Leaf)) {
    [Console]::Error.WriteLine("selected Workspace root has no workspace.yaml: $selectedRoot")
    exit 2
}
$target = Join-Path $selectedRoot '.claude\amir-loop-dependencies.json'
if (Test-Path -LiteralPath $target) {
    [Console]::Error.WriteLine("$target already exists; edit its lumvaleos policy explicitly")
    exit 1
}

$pluginRoot = Split-Path -Parent $PSScriptRoot
$template = Join-Path $pluginRoot 'templates\lumvaleos-required.json'
$policy = Get-Content -LiteralPath $template -Raw | ConvertFrom-Json
$dependency = @($policy.dependencies | Where-Object id -eq 'lumvaleos')
if ($dependency.Count -ne 1) {
    throw "Template must contain exactly one lumvaleos dependency: $template"
}
$dependency[0].policy = $Mode

$parent = Split-Path -Parent $target
[System.IO.Directory]::CreateDirectory($parent) | Out-Null
$json = $policy | ConvertTo-Json -Depth 10
$stream = $null
$writer = $null
try {
    $stream = [System.IO.File]::Open(
        $target,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    $writer = [System.IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
    $writer.Write($json + [Environment]::NewLine)
}
finally {
    if ($writer) { $writer.Dispose() }
    elseif ($stream) { $stream.Dispose() }
}
Write-Output "Configured LumvaleOS as $Mode in $target. Validate and render this Workspace's agent policy, then start a new agent session so host tools and hooks reload. The declared CLI MCP bridge is bounded continuity only; native MCP remains primary."
