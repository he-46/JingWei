param([string]$Output = 'artifacts/qa02-soak', [ValidateRange(2,600)][int]$CaseSeconds = 90, [string]$PackPath = 'builds/Jingwei-QA-01-Windows-x64/Jingwei.pck')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($Output)) { $Output = Join-Path $root $Output }
$Output = [IO.Path]::GetFullPath($Output)
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')) + [IO.Path]::DirectorySeparatorChar
if (-not $Output.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Soak output must stay within artifacts.' }
if (Test-Path -LiteralPath $Output) { throw 'Choose a fresh output folder.' }
if (-not [IO.Path]::IsPathRooted($PackPath)) { $PackPath = Join-Path $root $PackPath }
$PackPath = (Resolve-Path -LiteralPath $PackPath).Path
$engine = Join-Path $root 'Godot\Godot_v4.7.2-stable_win64.exe'
$scriptPath = Join-Path $root 'tests\stability_soak.gd'
$previousApp = $env:APPDATA
$previousLocal = $env:LOCALAPPDATA
New-Item -ItemType Directory -Path $Output | Out-Null
$samples = New-Object 'System.Collections.Generic.List[object]'
$memoryPath = Join-Path $Output 'process-memory.jsonl'
$writer = New-Object IO.StreamWriter($memoryPath, $false, (New-Object Text.UTF8Encoding($false)))
$taskProcess = $null
try {
    $env:APPDATA = Join-Path $Output 'isolated-profile'
    $env:LOCALAPPDATA = Join-Path $env:APPDATA 'local'
    $out = Join-Path $Output 'stdout.log'
    $err = Join-Path $Output 'stderr.log'
    $arguments = @('--main-pack',('"' + $PackPath + '"'),'--script',('"' + $scriptPath + '"'),'--',('--out="' + $Output.Replace('\','/') + '"'),"--case-seconds=$CaseSeconds")
    $taskProcess = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent $PackPath) -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    $handle = $taskProcess.Handle
    $started = [DateTime]::UtcNow
    $deadline = $started.AddSeconds(8 * $CaseSeconds + 180)
    $renderer = $null
    $lastCase = ''
    while (-not $taskProcess.WaitForExit(1000)) {
        $pidPath = Join-Path $Output 'process-id.txt'
        if ($null -eq $renderer -and (Test-Path -LiteralPath $pidPath)) {
            $pidText = (Get-Content -LiteralPath $pidPath -Raw).Trim()
            if ($pidText -match '^\d+$') {
                if ([int]$pidText -ne $taskProcess.Id) { throw 'Expected direct GUI engine PID, not a console launcher.' }
                $renderer = Get-Process -Id ([int]$pidText)
            }
        }
        if ($null -ne $renderer -and -not $renderer.HasExited) {
            $renderer.Refresh()
            $beat = $null
            $beatPath = Join-Path $Output 'heartbeat.json'
            if (Test-Path -LiteralPath $beatPath) {
                try { $beat = Get-Content -LiteralPath $beatPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $beat = $null }
            }
            $sample = [pscustomobject]@{unix_seconds=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()/1000.0; process_id=$renderer.Id; working_set_mib=$renderer.WorkingSet64/1MB; private_mib=$renderer.PrivateMemorySize64/1MB; peak_working_set_mib=$renderer.PeakWorkingSet64/1MB; target=$(if($beat){$beat.target}else{0}); quality=$(if($beat){$beat.quality}else{'warmup'})}
            $samples.Add($sample)
            $writer.WriteLine(($sample | ConvertTo-Json -Compress))
            $writer.Flush()
            if ($beat) {
                $caseKey = "$($beat.target)/$($beat.quality)"
                if ($caseKey -ne $lastCase) { Write-Host "Soak case: $caseKey; checks=$($beat.checks); failures=$($beat.failures)"; $lastCase=$caseKey }
            }
        }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Soak watchdog expired; inspect partial results.' }
        $diagnostics = @(Get-Content -LiteralPath $err | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$' })
        if ($diagnostics.Count) { throw ('Soak diagnostic failure: ' + ($diagnostics -join '; ')) }
    }
    $taskProcess.WaitForExit()
    $writer.Dispose()
    $writer = $null
    $lines = @(Get-Content -LiteralPath $out,$err | ForEach-Object { $_.ToString() })
    $diagnostics = @($lines | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$' })
    if ($taskProcess.ExitCode -ne 0 -or $diagnostics.Count -or -not ($lines -match 'STABILITY SOAK TESTS: \d+ checks, 0 failures')) { throw ('Soak failed: ' + ($diagnostics -join '; ')) }
    if ($samples.Count -eq 0) { throw 'No actual process memory samples were captured.' }
    $results = Get-Content -LiteralPath (Join-Path $Output 'results.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $memory = @()
    foreach ($case in $results.cases) {
        $selected = @($samples | Where-Object { $_.unix_seconds -ge $case.unix_start -and $_.unix_seconds -le $case.unix_end })
        $memory += [ordered]@{target=$case.target; quality=$case.quality; samples=$selected.Count; working_peak_mib=($selected | Measure-Object working_set_mib -Maximum).Maximum; private_peak_mib=($selected | Measure-Object private_mib -Maximum).Maximum}
    }
    [ordered]@{pack_sha256=(Get-FileHash -LiteralPath $PackPath -Algorithm SHA256).Hash; pack_path=$PackPath; host_wall_seconds=([DateTime]::UtcNow-$started).TotalSeconds; game_process_id=$taskProcess.Id; memory_samples=$samples.Count; memory_peak_mib=($samples | Measure-Object working_set_mib -Maximum).Maximum; cumulative_peak_mib=($samples | Measure-Object peak_working_set_mib -Maximum).Maximum; cases=$memory; diagnostics_clean=$true; results_file='results.json'; raw_memory_file='process-memory.jsonl'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Output 'host-summary.json') -Encoding UTF8
    Write-Host "Stability soak passed: $Output"
    Write-Host ($lines | Where-Object { $_ -match 'STABILITY SOAK TESTS:' })
} finally {
    if ($taskProcess -and -not $taskProcess.HasExited) { $taskProcess.Kill() }
    if ($writer) { $writer.Dispose() }
    $env:APPDATA = $previousApp
    $env:LOCALAPPDATA = $previousLocal
}
