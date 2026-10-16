param([Parameter(Mandatory=$true)][string]$Output, [string]$PackPath, [switch]$Baseline, [ValidateRange(3,60)][int]$CaseSeconds = 8)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not [IO.Path]::IsPathRooted($Output)) { $Output = Join-Path $root $Output }
$Output = [IO.Path]::GetFullPath($Output)
$allowed = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')) + [IO.Path]::DirectorySeparatorChar
if (-not $Output.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $Output)) { throw 'Use a fresh directory inside artifacts.' }
if ($Baseline -and -not $PackPath) { throw 'Baseline requires the FP-01 PCK.' }
New-Item -ItemType Directory -Path $Output | Out-Null
$engine = Join-Path $root 'Godot/Godot_v4.7.2-stable_win64.exe'
$arguments = @('--script', ('"' + (Join-Path $root 'tests/first_person_performance.gd') + '"'))
if ($PackPath) {
    $PackPath = (Resolve-Path -LiteralPath $PackPath).Path
    $arguments = @('--main-pack', ('"' + $PackPath + '"')) + $arguments
} else { $arguments = @('--path', ('"' + $root + '"')) + $arguments }
$arguments += @('--', ('--fp-out="' + $Output + '"'), "--case-seconds=$CaseSeconds")
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
    $samples = New-Object 'System.Collections.Generic.List[object]'
    $deadline = [DateTime]::UtcNow.AddSeconds($CaseSeconds * 8 + 180)
    while (-not $process.WaitForExit(1000)) {
        $process.Refresh()
        $samples.Add([ordered]@{unix_seconds=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()/1000.0; pid=$process.Id; working_set_mib=$process.WorkingSet64/1MB; private_mib=$process.PrivateMemorySize64/1MB})
        if ([DateTime]::UtcNow -gt $deadline) { $process.Kill(); throw 'First-person capture watchdog expired.' }
    }
    $process.WaitForExit()
    $diagnostics = @(Get-Content -LiteralPath $out,$err | Where-Object { ($_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$') -or $_ -match '^WARNING:.*(leaked|orphan)' })
    if ($process.ExitCode -ne 0 -or $diagnostics.Count) { throw "First-person capture failed: $($diagnostics -join '; ')" }
    $report = Get-Content -LiteralPath (Join-Path $Output 'performance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $identity = Get-Content -LiteralPath (Join-Path $Output 'process.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($report.failures -ne 0 -or $report.cases.Count -ne 8 -or $identity.pid -ne $process.Id -or $samples.Count -lt 8) { throw 'Incomplete real renderer capture.' }
    [ordered]@{source_commit=(git -C $root rev-parse HEAD).Trim(); source_dirty=[bool](git -C $root status --porcelain); pack_path=$PackPath; pack_sha256=$(if($PackPath){(Get-FileHash -LiteralPath $PackPath -Algorithm SHA256).Hash}else{$null}); binary=$engine; process_id=$process.Id; memory_samples=$samples; report=$report} | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $Output 'measurement.json') -Encoding UTF8
    Write-Host "First-person renderer capture passed: $Output"
} finally {
    $env:APPDATA = $previousApp
    $env:LOCALAPPDATA = $previousLocal
}
