param([string]$Ref = 'HEAD', [string]$Destination)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Destination) { $Destination = Join-Path $projectRoot ('artifacts\art\release-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
if (-not [IO.Path]::IsPathRooted($Destination)) { $Destination = Join-Path $projectRoot $Destination }
$Destination = [IO.Path]::GetFullPath($Destination)
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'artifacts')) + [IO.Path]::DirectorySeparatorChar
if (-not $Destination.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Release verification output must stay in the project artifacts folder.' }
if (Test-Path -LiteralPath $Destination) { throw 'Choose a fresh destination; existing files are never overwritten.' }
$snapshotZip = $Destination + '.zip'
if (Test-Path -LiteralPath $snapshotZip) { throw 'The adjacent snapshot ZIP already exists.' }
$previousPath = $env:PATH
$previousPythonPath = $env:PYTHONPATH
$previousGodot = $env:GODOT_EXE
$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
Push-Location $projectRoot
try {
    $revision = (git rev-parse --verify "$Ref^{commit}").Trim()
    if ($LASTEXITCODE -ne 0) { throw 'The requested Git commit does not exist.' }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    git archive --format=zip --output=$snapshotZip $revision
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the committed source ZIP.' }
    Expand-Archive -LiteralPath $snapshotZip -DestinationPath $Destination
    foreach ($excluded in @('.git', '.godot', '.tools', 'Godot\Godot_v4.7.2-stable_win64.exe', 'Godot\Godot_v4.7.2-stable_win64_console.exe')) {
        if (Test-Path -LiteralPath (Join-Path $Destination $excluded)) { throw "Unexpected local dependency in Git ZIP: $excluded" }
    }
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
    $env:PYTHONPATH = ''
    $env:GODOT_EXE = ''
    Push-Location $Destination
    try {
        # Exercise the actual download entry points, starting with no imported cache.
        & "$env:SystemRoot\System32\cmd.exe" /d /c 'Play.cmd -Check -NonInteractive'
        if ($LASTEXITCODE -ne 0) { throw 'Clean Git ZIP Play.cmd failed.' }
        & "$env:SystemRoot\System32\cmd.exe" /d /c 'Test.cmd -NonInteractive'
        if ($LASTEXITCODE -ne 0) { throw 'Clean Git ZIP Test.cmd failed.' }
        & "$env:SystemRoot\System32\cmd.exe" /d /c 'Sample.cmd -Check -NonInteractive'
        if ($LASTEXITCODE -ne 0) { throw 'Clean Git ZIP Sample.cmd failed.' }
        $env:APPDATA = Join-Path $Destination 'artifacts\qa-profile'
        $env:LOCALAPPDATA = Join-Path $env:APPDATA 'local'
        $engine = Join-Path $Destination 'Godot\Godot_v4.7.2-stable_win64_console.exe'
        $taskProcess = Start-Process -FilePath $engine -ArgumentList @('--path', ('"' + $Destination + '"'), '--quit-after', '45', '--', '--qa') -WindowStyle Hidden -RedirectStandardOutput 'artifacts\release-graphics-boot.log' -RedirectStandardError 'artifacts\release-graphics-boot-errors.log' -PassThru
        $taskHandle = $taskProcess.Handle
        $deadline = [DateTime]::UtcNow.AddMinutes(2)
        while (-not $taskProcess.WaitForExit(1000)) {
            if ([DateTime]::UtcNow -gt $deadline) { $taskProcess.Kill(); throw 'Clean graphical boot exceeded two minutes.' }
        }
        $taskProcess.WaitForExit()
        $errors = @(Get-Content -LiteralPath 'artifacts\release-graphics-boot-errors.log' | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.' })
        if ($taskProcess.ExitCode -ne 0 -or $errors.Count -gt 0) { throw ('Clean graphical boot failed: ' + ($errors -join '; ')) }
    } finally { Pop-Location }
    $testChecks = 0
    $testGroups = 0
    foreach ($log in Get-ChildItem -LiteralPath (Join-Path $Destination 'artifacts') -Filter '*-tests.log' -File) {
        foreach ($line in Get-Content -LiteralPath $log.FullName) {
            if ($line -match 'TESTS: (\d+) checks, (\d+) failures') {
                if ([int]$Matches[2] -ne 0) { throw 'A committed-source test reported failures.' }
                $testChecks += [int]$Matches[1]
                $testGroups += 1
            }
        }
    }
    if ($testGroups -eq 0) { throw 'No committed-source test summaries were found.' }
    $report = [ordered]@{commit=$revision; source_zip_bytes=(Get-Item -LiteralPath $snapshotZip).Length; source_zip_sha256=(Get-FileHash -LiteralPath $snapshotZip -Algorithm SHA256).Hash; test_checks=$testChecks; test_groups=$testGroups; windows_entry_points=@('Play.cmd -Check -NonInteractive','Test.cmd -NonInteractive','Sample.cmd -Check -NonInteractive','real Compatibility renderer boot'); bundled_engine_only=$true; artist_runtime_on_path=$false; destination=$Destination}
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath ($Destination + '-verification.json') -Encoding UTF8
    Write-Host "Committed source ZIP verification passed: $revision"
    Write-Host ("Source ZIP: {0:N2} MiB" -f ($report.source_zip_bytes / 1MB))
} finally {
    $env:PATH = $previousPath
    $env:PYTHONPATH = $previousPythonPath
    $env:GODOT_EXE = $previousGodot
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalAppData
    Pop-Location
}
