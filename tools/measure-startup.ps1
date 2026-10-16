param([string]$Output, [string]$PackPath, [switch]$Baseline, [switch]$Headless)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($Baseline -and -not $PackPath) { throw 'Baseline requires the QA-03 shipping PCK.' }
if (-not $Output) { $Output = Join-Path $root ('artifacts/startup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
if (-not [IO.Path]::IsPathRooted($Output)) { $Output = Join-Path $root $Output }
$Output = [IO.Path]::GetFullPath($Output)
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')) + [IO.Path]::DirectorySeparatorChar
if (-not $Output.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $Output)) { throw 'Use a fresh output directory inside artifacts.' }
New-Item -ItemType Directory -Path $Output | Out-Null
$engine = Join-Path $root 'Godot/Godot_v4.7.2-stable_win64.exe'
if ($PackPath) { $PackPath = (Resolve-Path -LiteralPath $PackPath).Path }
$previousApp = $env:APPDATA
$previousLocal = $env:LOCALAPPDATA
$results = New-Object 'System.Collections.Generic.List[object]'
try {
    $env:APPDATA = Join-Path $Output 'profile'
    $env:LOCALAPPDATA = Join-Path $env:APPDATA 'local'
    $save = Join-Path $env:APPDATA 'AzVGames/Jingwei/coast_journey.json'
    foreach ($pass in @('first','repeat')) {
        $folder = Join-Path $Output $pass
        New-Item -ItemType Directory -Path $folder | Out-Null
        $cacheRoot = Join-Path $env:APPDATA 'AzVGames/Jingwei/shader_cache'
        $cacheBefore = @(Get-ChildItem -LiteralPath $cacheRoot -Recurse -File -ErrorAction SilentlyContinue)
        $arguments = @('--script',('"' + (Join-Path $root 'tests/test_startup.gd') + '"'))
        if ($PackPath) { $arguments = @('--main-pack',('"' + $PackPath + '"')) + $arguments }
        else { $arguments = @('--path',('"' + $root + '"')) + $arguments }
        if ($Headless) { $arguments = @('--headless') + $arguments }
        $arguments += @('--',('--startup-out="' + $folder + '"'),('--save-path="' + $save + '"'))
        if ($Baseline) { $arguments += '--baseline' }
        if ($pass -eq 'repeat') { $arguments += '--repeat' }
        $out = Join-Path $folder 'engine.log'
        $err = Join-Path $folder 'engine-errors.log'
        $process = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $folder -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
        $handle = $process.Handle
        $deadline = [DateTime]::UtcNow.AddMinutes(3)
        while (-not $process.WaitForExit(1000)) {
            if ([DateTime]::UtcNow -gt $deadline) { $process.Kill(); throw "Startup $pass exceeded three minutes." }
        }
        $process.WaitForExit()
        $errors = @(Get-Content -LiteralPath $out,$err | Where-Object { ($_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$') -or $_ -match '^WARNING:.*(leaked|orphan)' })
        if ($process.ExitCode -ne 0 -or $errors.Count) { throw "Startup $pass failed: $($errors -join '; ')" }
        $report = Get-Content -LiteralPath (Join-Path $folder 'startup.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($report.failures -ne 0 -or $report.records.Count -lt 5) { throw 'Incomplete startup report.' }
        $cacheAfter = @(Get-ChildItem -LiteralPath $cacheRoot -Recurse -File -ErrorAction SilentlyContinue)
        $results.Add([ordered]@{pass=$pass; cache_files_before=$cacheBefore.Count; cache_files_after=$cacheAfter.Count; report=$report})
    }
    $hash = if ($PackPath) { (Get-FileHash -LiteralPath $PackPath -Algorithm SHA256).Hash } else { $null }
    [ordered]@{source_commit=(git -C $root rev-parse HEAD).Trim(); source_dirty=[bool](git -C $root status --porcelain); pack_sha256=$hash; baseline=[bool]$Baseline; headless=[bool]$Headless; binary=$engine; passes=$results} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Output 'measurement.json') -Encoding UTF8
    Write-Host "First/repeated startup verification passed: $Output"
} finally {
    $env:APPDATA = $previousApp
    $env:LOCALAPPDATA = $previousLocal
}
