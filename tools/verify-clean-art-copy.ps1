param([string]$Destination)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Destination) { $Destination = Join-Path $projectRoot ('artifacts\art\clean-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$Destination = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $Destination) { throw 'Choose a new destination: this check never overwrites an existing folder.' }
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
Push-Location $projectRoot
try {
    $files = @(git -c core.quotepath=false ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate distributable source files.' }
    foreach ($relative in $files) {
        $source = Join-Path $projectRoot $relative
        $target = Join-Path $Destination $relative
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target
        }
    }
    foreach ($excluded in @('.godot', '.tools', 'Godot\Godot_v4.7.2-stable_win64_console.exe')) {
        if (Test-Path -LiteralPath (Join-Path $Destination $excluded)) { throw "Unexpected local dependency copied: $excluded" }
    }
    $previousPath = $env:PATH
    $previousPythonPath = $env:PYTHONPATH
    try {
        # Make artist runtimes unavailable. Player setup must use only bundled Godot.
        $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
        $env:PYTHONPATH = ''
        & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Destination 'tools\run.ps1') -Mode Test -NonInteractive
        if ($LASTEXITCODE -ne 0) { throw 'Clean source import/game tests failed.' }
        & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Destination 'tools\run.ps1') -Mode Sample -Check -NonInteractive
        if ($LASTEXITCODE -ne 0) { throw 'Clean source sample launcher check failed.' }
    } finally {
        $env:PATH = $previousPath
        $env:PYTHONPATH = $previousPythonPath
    }
    Write-Host "Clean source verification passed: $Destination"
} finally { Pop-Location }
