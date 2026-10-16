param([string]$Output, [string]$PackPath, [switch]$Baseline, [switch]$Headless)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($Baseline -and -not $PackPath) { throw 'Baseline mode requires the preceding release PCK.' }
if (-not $Output) { $Output = Join-Path $root ('artifacts/loading-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
if (-not [IO.Path]::IsPathRooted($Output)) { $Output = Join-Path $root $Output }
$Output = [IO.Path]::GetFullPath($Output)
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')) + [IO.Path]::DirectorySeparatorChar
if (-not $Output.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $Output)) { throw 'Use a fresh directory inside artifacts.' }
New-Item -ItemType Directory -Path $Output | Out-Null
$engine = Join-Path $root 'Godot/Godot_v4.7.2-stable_win64.exe'
$arguments = @('--script', ('"' + (Join-Path $root 'tests/test_loading.gd') + '"'))
if ($PackPath) {
    $PackPath = (Resolve-Path -LiteralPath $PackPath).Path
    $arguments = @('--main-pack', ('"' + $PackPath + '"')) + $arguments
} else { $arguments = @('--path', ('"' + $root + '"')) + $arguments }
if ($Headless) { $arguments = @('--headless') + $arguments }
$arguments += @('--', ('--loading-out="' + $Output + '"'))
if ($Baseline) { $arguments += '--baseline' }
$previousApp = $env:APPDATA
$previousLocal = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $Output 'profile'
    $env:LOCALAPPDATA = Join-Path $env:APPDATA 'local'
    $out = Join-Path $Output 'engine.log'
    $err = Join-Path $Output 'engine-errors.log'
    $process = Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $Output -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    $handle = $process.Handle
    $deadline = [DateTime]::UtcNow.AddMinutes(3)
    while (-not $process.WaitForExit(1000)) {
        if ([DateTime]::UtcNow -gt $deadline) { $process.Kill(); throw 'Loading harness exceeded three minutes.' }
    }
    $process.WaitForExit()
    $errors = @(Get-Content -LiteralPath $out,$err | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$' })
    if ($process.ExitCode -ne 0 -or $errors.Count) { throw "Loading harness failed: $($errors -join '; ')" }
    $report = Get-Content -LiteralPath (Join-Path $Output 'loading.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($report.failures -ne 0 -or $report.records.Count -lt 20) { throw 'Incomplete loading report.' }
    $source = (git -C $root rev-parse HEAD).Trim()
    $hash = if ($PackPath) { (Get-FileHash -LiteralPath $PackPath -Algorithm SHA256).Hash } else { $null }
    [ordered]@{ source_commit=$source; source_dirty=[bool](git -C $root status --porcelain); pack_path=$PackPath; pack_sha256=$hash; binary=$engine; baseline=[bool]$Baseline; headless=[bool]$Headless; report=$report } | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $Output 'measurement.json') -Encoding UTF8
    Write-Host "Loading verification passed: $($report.checks) checks; $Output"
} finally {
    $env:APPDATA = $previousApp
    $env:LOCALAPPDATA = $previousLocal
}
