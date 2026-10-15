param([string]$Output = 'artifacts/art/art08-review')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $Output))
if (-not $outputPath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Output must stay inside the project.' }
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$env:APPDATA = Join-Path $projectRoot 'artifacts\qa-profile'
$env:LOCALAPPDATA = Join-Path $env:APPDATA 'local'
$engine = Join-Path $projectRoot 'Godot\Godot_v4.7.2-stable_win64_console.exe'
foreach ($name in @('test_mountain', 'test_environment', 'test_feedback', 'test_expansion', 'test_player_locator', 'capture_expansion')) {
    $arguments = @('--path', $projectRoot, '--script', "res://tests/$name.gd", '--', '--qa')
    if ($name -eq 'test_player_locator') { $arguments += '--review-out=res://' + $Output.Replace('\', '/') }
    $taskProcess = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $outputPath "$name.log") -RedirectStandardError (Join-Path $outputPath "$name-errors.log") -PassThru
    $taskHandle = $taskProcess.Handle
    $deadline = [DateTime]::UtcNow.AddMinutes(3)
    while (-not $taskProcess.WaitForExit(1000)) {
        if ([DateTime]::UtcNow -gt $deadline) { $taskProcess.Kill(); throw "$name exceeded three minutes." }
    }
    $taskProcess.WaitForExit()
    $errors = @(Get-Content -LiteralPath (Join-Path $outputPath "$name-errors.log") | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.' })
    Get-Content -LiteralPath (Join-Path $outputPath "$name.log") | Select-Object -Last 2
    if ($taskProcess.ExitCode -ne 0 -or $errors.Count -gt 0) { throw ("${name} failed: " + ($errors -join '; ')) }
}
Write-Host "Expansion graphics checks passed: $outputPath"
