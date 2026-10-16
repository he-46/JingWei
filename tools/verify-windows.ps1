param([Parameter(Mandatory=$true)][string]$ZipPath, [string]$Destination)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Destination) { $Destination = Join-Path $root ('artifacts\Windows 试玩验证 ' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
if (-not [IO.Path]::IsPathRooted($Destination)) { $Destination = Join-Path $root $Destination }
$Destination = [IO.Path]::GetFullPath($Destination)
$artifactRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')) + [IO.Path]::DirectorySeparatorChar
if (-not $Destination.StartsWith($artifactRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Verification output must stay inside artifacts.' }
if (Test-Path -LiteralPath $Destination) { throw 'Choose a fresh verification folder.' }
$ZipPath = (Resolve-Path -LiteralPath $ZipPath).Path
$package = Join-Path $Destination '独立游戏'
$qa = Join-Path $Destination 'qa'
Expand-Archive -LiteralPath $ZipPath -DestinationPath $package
New-Item -ItemType Directory -Path $qa -Force | Out-Null
$info = Get-Content -LiteralPath (Join-Path $package 'build-info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedFiles = @('Jingwei.exe','Jingwei.pck','开始游戏.txt','build-info.json','licenses/Godot-LICENSE.txt','licenses/Godot-COPYRIGHT.txt')
$actualFiles = @(Get-ChildItem -LiteralPath $package -Recurse -File | ForEach-Object { $_.FullName.Substring($package.Length + 1).Replace('\','/') })
if (@(Compare-Object $expectedFiles $actualFiles).Count) { throw 'ZIP must contain only the executable, PCK, player guide, build record and two license files.' }
$version = (Get-Item -LiteralPath (Join-Path $package 'Jingwei.exe')).VersionInfo
if ($version.FileVersion -ne '0.1.0.0' -or $version.ProductName -ne '精卫填海 · 衔石成洲') { throw 'Missing executable version or product metadata.' }
foreach ($file in $info.files) {
    $path = Join-Path $package $file.path
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) { throw "ZIP content hash mismatch: $($file.path)" }
}
# Release templates deliberately omit --script. Mount the exact shipping PCK in
# the editor harness for deep regression; boot the actual release EXE separately.
# No test scripts, fixtures or editor are included in the playable ZIP/PCK.
Copy-Item -LiteralPath (Join-Path $root 'tests\test_windows_pack.gd') -Destination (Join-Path $qa 'pack.gd')
Copy-Item -LiteralPath (Join-Path $root 'tests\fixtures\coast_v2.json') -Destination (Join-Path $qa 'coast_v2.json')
$fixture = (Join-Path $qa 'coast_v2.json').Replace('\','/')
$regression = [IO.File]::ReadAllText((Join-Path $root 'tests\test_release.gd'), [Text.Encoding]::UTF8)
$regression = $regression.Replace('res://artifacts/', 'user://qa/').Replace('res://tests/fixtures/coast_v2.json', $fixture)
[IO.File]::WriteAllText((Join-Path $qa 'regression.gd'), $regression, (New-Object Text.UTF8Encoding($false)))
$previousPath = $env:PATH
$previousPython = $env:PYTHONPATH
$previousGodot = $env:GODOT_EXE
$previousApp = $env:APPDATA
$previousLocal = $env:LOCALAPPDATA
$records = New-Object 'System.Collections.Generic.List[object]'
$exe = Join-Path $package 'Jingwei.exe'
$editor = Join-Path $root 'Godot\Godot_v4.7.2-stable_win64.exe'
function Invoke-Preview([string[]]$PreviewArguments, [string]$Name, [switch]$Harness) {
    $out = Join-Path $qa ($Name + '.log')
    $err = Join-Path $qa ($Name + '-errors.log')
    $binary = if ($Harness) { $editor } else { $exe }
    $process = Start-Process -FilePath $binary -ArgumentList $PreviewArguments -WorkingDirectory $package -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    $handle = $process.Handle
    $deadline = [DateTime]::UtcNow.AddMinutes(4)
    while (-not $process.WaitForExit(1000)) {
        if ([DateTime]::UtcNow -gt $deadline) { $process.Kill(); throw "$Name exceeded four minutes. See $qa" }
    }
    $process.WaitForExit()
    $lines = @(Get-Content -LiteralPath $out,$err)
    $diagnostics = @($lines | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$' })
    if ($process.ExitCode -ne 0 -or $diagnostics.Count) { throw "$Name failed: $($diagnostics -join '; ')" }
    if ($Harness -and -not ($lines -match 'TESTS: \d+ checks, 0 failures')) { throw "$Name produced no successful test summary." }
    $records.Add([ordered]@{name=$Name; binary=$(if ($Harness) {'editor harness + shipping PCK'} else {'shipping release EXE'}); exit_code=$process.ExitCode; summaries=@($lines | Where-Object { $_ -match 'TESTS:|CAPTURE_RESULT|OpenGL API' })})
}
try {
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
    $env:PYTHONPATH = ''
    $env:GODOT_EXE = ''
    $env:APPDATA = Join-Path $qa 'profile'
    $env:LOCALAPPDATA = Join-Path $env:APPDATA 'local'
    $packArgs = @('--main-pack',('"' + (Join-Path $package 'Jingwei.pck') + '"'))
    Invoke-Preview ($packArgs + @('--headless','--script',('"' + (Join-Path $qa 'pack.gd') + '"'))) 'pack' -Harness
    Invoke-Preview ($packArgs + @('--headless','--script',('"' + (Join-Path $qa 'regression.gd') + '"'))) 'regression' -Harness
    foreach ($target in @(100000,1000000,10000000,100000000)) {
        $capture = Join-Path $qa ("map-$target.png")
        Invoke-Preview @('--','--qa',"--target=$target",'--showcase',('--capture="' + $capture + '"')) "graphics-$target"
        if (-not (Test-Path -LiteralPath $capture)) { throw "Missing actual release screenshot for $target" }
    }
    # Real graphical save/load regression uses isolated user:// files, not --qa.
    $review = (Join-Path $qa 'review').Replace('\','/')
    Invoke-Preview ($packArgs + @('--script',('"' + (Join-Path $qa 'regression.gd') + '"'),'--',('--review-out="' + $review + '"'))) 'graphics-regression' -Harness
    # Ordinary release boot: new selector and actual v2 continuation, no --qa or
    # --capture (both suppress normal loading). APPDATA remains fully isolated.
    Invoke-Preview @('--quit-after','45') 'release-new-selector'
    $saveFolder = Join-Path $env:APPDATA 'AzVGames\Jingwei'
    New-Item -ItemType Directory -Path $saveFolder -Force | Out-Null
    $savePath = Join-Path $saveFolder 'coast_journey.json'
    Copy-Item -LiteralPath (Join-Path $qa 'coast_v2.json') -Destination $savePath
    $legacyHash = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    Invoke-Preview @('--quit-after','45') 'release-legacy-continue'
    if ((Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash -ne $legacyHash) { throw 'Short ordinary legacy boot unexpectedly modified the original save.' }
    [ordered]@{package='BUILD-01'; source_commit=$info.source_commit; source_dirty=$info.source_dirty; zip_bytes=(Get-Item -LiteralPath $ZipPath).Length; zip_sha256=(Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash; no_editor_on_path=$true; deep_regression='editor harness explicitly mounts shipping PCK'; release_checks='four real captures, ordinary selector, v2 continuation'; save_isolated=$true; records=$records; destination=$Destination} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Destination 'verification.json') -Encoding UTF8
    Write-Host "Standalone ZIP verification passed: $Destination"
} finally {
    $env:PATH = $previousPath
    $env:PYTHONPATH = $previousPython
    $env:GODOT_EXE = $previousGodot
    $env:APPDATA = $previousApp
    $env:LOCALAPPDATA = $previousLocal
}
