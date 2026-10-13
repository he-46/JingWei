param([ValidateSet('Run', 'Editor', 'Test')][string]$Mode = 'Run')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localEngine = Join-Path $projectRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
$sharedEngine = Join-Path (Split-Path -Parent $projectRoot) 'RainyArrow\.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
$enginePath = $null
foreach ($candidate in @($localEngine, $sharedEngine, $env:GODOT_EXE)) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { $enginePath = $candidate; break }
}
if (-not $enginePath) {
    foreach ($command in @('godot', 'godot4')) {
        $found = Get-Command $command -ErrorAction SilentlyContinue
        if ($found) { $enginePath = $found.Source; break }
    }
}
if (-not $enginePath) {
    Write-Host 'Godot 4 is required. Set GODOT_EXE, or import project.godot with your Godot editor.'
    exit 1
}
if ($Mode -eq 'Test') {
    $env:APPDATA = Join-Path $projectRoot 'artifacts\qa-profile'
    & $enginePath --headless --path $projectRoot --editor --import --quit
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $enginePath --headless --path $projectRoot --script res://tests/test_runner.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $enginePath --headless --path $projectRoot --script res://tests/test_game.gd -- --qa
    exit $LASTEXITCODE
}
if ($Mode -eq 'Editor') { & $enginePath --path $projectRoot --editor }
else { & $enginePath --path $projectRoot }
exit $LASTEXITCODE
