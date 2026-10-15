param([string]$Output = 'artifacts/art/art08-performance')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $Output))
if (-not $outputPath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Output must stay inside the project.' }
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$env:APPDATA = Join-Path $projectRoot 'artifacts\qa-profile'
$env:LOCALAPPDATA = Join-Path $env:APPDATA 'local'
$engine = Join-Path $projectRoot 'Godot\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw 'Run Sample.cmd once to prepare the included engine.' }
$processIdPath = Join-Path $outputPath 'process-id.txt'
if (Test-Path -LiteralPath $processIdPath) { Remove-Item -LiteralPath $processIdPath }
$taskProcess = Start-Process -FilePath $engine -ArgumentList @('--path', $projectRoot, '--script', 'res://tests/art_expansion_benchmark.gd', '--', '--qa', ('--out=res://' + $Output.Replace('\', '/'))) -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $outputPath 'stdout.log') -RedirectStandardError (Join-Path $outputPath 'stderr.log') -PassThru
$taskHandle = $taskProcess.Handle
$samples = New-Object 'System.Collections.Generic.List[object]'
$deadline = [DateTime]::UtcNow.AddMinutes(10)
$rendererProcess = $null
while (-not $taskProcess.WaitForExit(500)) {
    if ($null -eq $rendererProcess -and (Test-Path -LiteralPath $processIdPath)) {
        $rendererIdText = (Get-Content -LiteralPath $processIdPath -Raw).Trim()
        if ($rendererIdText -match '^\d+$') { $rendererProcess = Get-Process -Id ([int]$rendererIdText) }
    }
    if ($null -ne $rendererProcess -and -not $rendererProcess.HasExited) {
        $rendererProcess.Refresh()
        $samples.Add([pscustomobject]@{process_id=$rendererProcess.Id; unix_seconds=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()/1000.0; working_set_mib=$rendererProcess.WorkingSet64/1MB; private_mib=$rendererProcess.PrivateMemorySize64/1MB; peak_working_set_mib=$rendererProcess.PeakWorkingSet64/1MB})
    }
    if ([DateTime]::UtcNow -gt $deadline) { $taskProcess.Kill(); throw 'Benchmark exceeded ten minutes; inspect diagnostics.' }
}
$taskProcess.WaitForExit()
if ($samples.Count -eq 0) { throw 'No renderer process memory samples were captured.' }
$samples | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputPath 'process-memory.json') -Encoding UTF8
$errors = @(Get-Content -LiteralPath (Join-Path $outputPath 'stderr.log') | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.' })
Get-Content -LiteralPath (Join-Path $outputPath 'stdout.log')
if ($taskProcess.ExitCode -ne 0 -or $errors.Count -gt 0) { throw ('Benchmark failed: ' + ($errors -join '; ')) }
Write-Host "Expansion benchmark passed: $outputPath"
