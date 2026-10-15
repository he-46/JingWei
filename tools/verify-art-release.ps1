$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $projectRoot 'artifacts\art\art09-review'
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
try {
$env:APPDATA = Join-Path $projectRoot 'artifacts\qa-profile'
$env:LOCALAPPDATA = Join-Path $env:APPDATA 'local'
$engine = Join-Path $projectRoot 'Godot\Godot_v4.7.2-stable_win64_console.exe'
foreach ($name in @('test_release_assets', 'test_release', 'test_player_locator', 'test_vertical_slice')) {
    $arguments = @('--path', ('"' + $projectRoot + '"'))
    if ($name -eq 'test_vertical_slice') { $arguments += @('--fixed-fps', '60') }
    $arguments += @('--script', "res://tests/$name.gd", '--')
    if ($name -eq 'test_release') { $arguments += '--review-out=res://artifacts/art/art09-review' }
    if ($name -eq 'test_player_locator') { $arguments += @('--qa', '--review-out=res://artifacts/art/art09-views') }
    if ($name -eq 'test_vertical_slice') { $arguments += @('--qa', '--capture-output=res://artifacts/art/art09-walk') }
    $taskProcess = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $outputPath "$name.log") -RedirectStandardError (Join-Path $outputPath "$name-errors.log") -PassThru
    $taskHandle = $taskProcess.Handle
    $deadline = [DateTime]::UtcNow.AddMinutes(6)
    while (-not $taskProcess.WaitForExit(1000)) {
        if ([DateTime]::UtcNow -gt $deadline) { $taskProcess.Kill(); throw "$name exceeded six minutes." }
    }
    $taskProcess.WaitForExit()
    $errors = @(Get-Content -LiteralPath (Join-Path $outputPath "$name-errors.log") | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.' })
    Get-Content -LiteralPath (Join-Path $outputPath "$name.log") | Select-Object -Last 2
    if ($taskProcess.ExitCode -ne 0 -or $errors.Count -gt 0) { throw ("${name} failed: " + ($errors -join '; ')) }
}
Write-Host 'ART-09 real renderer checks and walkthrough capture passed.'
} finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
}
