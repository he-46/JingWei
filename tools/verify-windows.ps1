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
if ($version.FileVersion -ne $info.product_version -or $version.ProductName -ne '精卫填海 · 衔石成洲') { throw 'Missing executable version or product metadata.' }
foreach ($file in $info.files) {
    $path = Join-Path $package $file.path
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) { throw "ZIP content hash mismatch: $($file.path)" }
}
# Release templates deliberately omit --script. Mount the exact shipping PCK in
# the editor harness for deep regression; boot the actual release EXE separately.
# No test scripts, fixtures or editor are included in the playable ZIP/PCK.
Copy-Item -LiteralPath (Join-Path $root 'tests\test_windows_pack.gd') -Destination (Join-Path $qa 'pack.gd')
Copy-Item -LiteralPath (Join-Path $root 'tests\test_preferences.gd') -Destination (Join-Path $qa 'preferences.gd')
Copy-Item -LiteralPath (Join-Path $root 'tests\test_first_person.gd') -Destination (Join-Path $qa 'first-person.gd')
Copy-Item -LiteralPath (Join-Path $root 'tests\test_first_person_polish.gd') -Destination (Join-Path $qa 'first-person-polish.gd')
Copy-Item -LiteralPath (Join-Path $root 'tests\test_loading.gd') -Destination (Join-Path $qa 'loading.gd')
Copy-Item -LiteralPath (Join-Path $root 'tests\test_startup.gd') -Destination (Join-Path $qa 'startup.gd')
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
    # Strip Windows PowerShell's file/provider properties before JSON reporting.
    $lines = @(Get-Content -LiteralPath $out,$err | ForEach-Object { $_.ToString() })
    $diagnostics = @($lines | Where-Object { ($_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$') -or $_ -match '^WARNING:.*(leaked|orphan)' })
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
    Invoke-Preview ($packArgs + @('--headless','--script',('"' + (Join-Path $qa 'first-person.gd') + '"'))) 'first-person-headless' -Harness
    Invoke-Preview ($packArgs + @('--script',('"' + (Join-Path $qa 'first-person.gd') + '"'))) 'first-person-graphics' -Harness
    Invoke-Preview ($packArgs + @('--headless','--script',('"' + (Join-Path $qa 'first-person-polish.gd') + '"'))) 'first-person-polish-headless' -Harness
    Invoke-Preview ($packArgs + @('--script',('"' + (Join-Path $qa 'first-person-polish.gd') + '"'))) 'first-person-polish-graphics' -Harness
    Invoke-Preview ($packArgs + @('--headless','--script',('"' + (Join-Path $qa 'regression.gd') + '"'))) 'regression' -Harness
    Invoke-Preview ($packArgs + @('--headless','--script',('"' + (Join-Path $qa 'preferences.gd') + '"'))) 'preferences' -Harness
    $loadingOut = (Join-Path $qa 'loading-headless').Replace('\','/')
    Invoke-Preview ($packArgs + @('--headless','--script',('"' + (Join-Path $qa 'loading.gd') + '"'),'--',('--loading-out="' + $loadingOut + '"'))) 'loading' -Harness
    $startupOut = (Join-Path $qa 'startup-headless').Replace('\','/')
    $startupSave = (Join-Path $qa 'startup-headless/journey.json').Replace('\','/')
    Invoke-Preview ($packArgs + @('--headless','--script',('"' + (Join-Path $qa 'startup.gd') + '"'),'--',('--startup-out="' + $startupOut + '"'),('--save-path="' + $startupSave + '"'))) 'startup' -Harness
    $startupReview = (Join-Path $qa 'startup-graphics').Replace('\','/')
    $startupReviewSave = (Join-Path $qa 'startup-graphics/journey.json').Replace('\','/')
    Invoke-Preview ($packArgs + @('--script',('"' + (Join-Path $qa 'startup.gd') + '"'),'--',('--startup-out="' + $startupReview + '"'),('--save-path="' + $startupReviewSave + '"'))) 'graphics-startup' -Harness
    $closeOut = (Join-Path $qa 'startup-close').Replace('\','/')
    $closeSave = (Join-Path $qa 'startup-close/journey.json').Replace('\','/')
    Invoke-Preview ($packArgs + @('--script',('"' + (Join-Path $qa 'startup.gd') + '"'),'--','--startup-close',('--startup-out="' + $closeOut + '"'),('--save-path="' + $closeSave + '"'))) 'startup-close' -Harness
    if (Test-Path -LiteralPath $closeSave) { throw 'Closing resource-loading entry wrote a placeholder journey.' }
    foreach ($target in @(100000,1000000,10000000,100000000)) {
        $capture = Join-Path $qa ("map-$target.png")
        Invoke-Preview @('--','--qa',"--target=$target",'--showcase',('--capture="' + $capture + '"')) "graphics-$target"
        if (-not (Test-Path -LiteralPath $capture)) { throw "Missing actual release screenshot for $target" }
    }
    # Real graphical save/load regression uses isolated user:// files, not --qa.
    $review = (Join-Path $qa 'review').Replace('\','/')
    Invoke-Preview ($packArgs + @('--script',('"' + (Join-Path $qa 'regression.gd') + '"'),'--',('--review-out="' + $review + '"'))) 'graphics-regression' -Harness
    $settingsReview = (Join-Path $qa 'settings-review').Replace('\','/')
    Invoke-Preview ($packArgs + @('--script',('"' + (Join-Path $qa 'preferences.gd') + '"'),'--',('--review-out="' + $settingsReview + '"'))) 'graphics-preferences' -Harness
    # Ordinary release boot: new selector and actual v2 continuation, no --qa or
    # --capture (both suppress normal loading). APPDATA remains fully isolated.
    $selectorCapture = Join-Path $qa 'release-new-selector.png'
    Invoke-Preview @('--','--capture-continued',('--capture="' + $selectorCapture + '"')) 'release-new-selector'
    $saveFolder = Join-Path $env:APPDATA 'AzVGames\Jingwei'
    New-Item -ItemType Directory -Path $saveFolder -Force | Out-Null
    $savePath = Join-Path $saveFolder 'coast_journey.json'
    Copy-Item -LiteralPath (Join-Path $qa 'coast_v2.json') -Destination $savePath
    [IO.File]::WriteAllText((Join-Path $saveFolder 'preferences.json'), '{"version":1,"quality":"smooth","fullscreen":false,"volume":0.37,"muted":true}', (New-Object Text.UTF8Encoding($false)))
    $legacyHash = (Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash
    $legacyCapture = Join-Path $qa 'release-legacy-continue.png'
    Invoke-Preview @('--','--capture-continued',('--capture="' + $legacyCapture + '"')) 'release-legacy-continue'
    $movie = Join-Path $qa 'release-smooth.png'
    Invoke-Preview @('--','--capture-continued',('--capture="' + $movie + '"')) 'release-smooth-capture'
    [IO.File]::WriteAllText((Join-Path $saveFolder 'preferences.json'), '{"version":1,"quality":"smooth","fullscreen":false,"volume":0.37,"muted":true,"first_person":true,"view_key":66,"look_sensitivity":1.5,"first_person_fov":95}', (New-Object Text.UTF8Encoding($false)))
    $firstPersonCapture = Join-Path $qa 'release-first-person.png'
    Invoke-Preview @('--','--capture-continued',('--capture="' + $firstPersonCapture + '"')) 'release-first-person'
    foreach ($capture in @($selectorCapture, $legacyCapture, $movie, $firstPersonCapture)) {
        if (-not (Test-Path -LiteralPath $capture)) { throw 'Actual release continuation/selector capture was not produced after loading completed.' }
    }
    if ((Get-FileHash -LiteralPath $savePath -Algorithm SHA256).Hash -ne $legacyHash) { throw 'Short ordinary legacy boot unexpectedly modified the original save.' }
    [ordered]@{package=$info.package; source_commit=$info.source_commit; source_dirty=$info.source_dirty; zip_bytes=(Get-Item -LiteralPath $ZipPath).Length; zip_sha256=(Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash; no_editor_on_path=$true; deep_regression='editor harness explicitly mounts shipping PCK'; release_checks='four real captures, ordinary selector, v2 continuation with persisted smooth settings, first-person preference boot'; save_isolated=$true; records=$records; destination=$Destination} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Destination 'verification.json') -Encoding UTF8
    Write-Host "Standalone ZIP verification passed: $Destination"
} finally {
    $env:PATH = $previousPath
    $env:PYTHONPATH = $previousPython
    $env:GODOT_EXE = $previousGodot
    $env:APPDATA = $previousApp
    $env:LOCALAPPDATA = $previousLocal
}
