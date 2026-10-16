param([string]$Destination, [string]$GodotPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Destination) { $Destination = Join-Path $root ('builds\Windows-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
if (-not [IO.Path]::IsPathRooted($Destination)) { $Destination = Join-Path $root $Destination }
$Destination = [IO.Path]::GetFullPath($Destination)
$buildRoot = [IO.Path]::GetFullPath((Join-Path $root 'builds')) + [IO.Path]::DirectorySeparatorChar
if (-not $Destination.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Build output must stay inside builds.' }
if ((Test-Path -LiteralPath $Destination) -or (Test-Path -LiteralPath ($Destination + '.zip'))) { throw 'Choose a fresh output folder.' }
if (-not $GodotPath) { $GodotPath = Join-Path $root 'Godot\Godot_v4.7.2-stable_win64.exe' }
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Run Play.cmd -Check -NonInteractive once to prepare the bundled editor.' }
if (-not (Test-Path -LiteralPath (Join-Path $root '.tools\export-templates\windows_release_x86_64.exe'))) { throw 'Run tools/prepare-windows-template.ps1 with the official 4.7.2 TPZ first.' }
$templateHash = 'D34D36F3BE1A6C49C56525AE86469B92E4F417DDF0B43CF00DD80C385C4B0562'
if ((Get-FileHash -LiteralPath (Join-Path $root '.tools\export-templates\windows_release_x86_64.exe') -Algorithm SHA256).Hash -ne $templateHash) { throw 'Cached release template has changed; prepare it again from the verified official archive.' }
$previousApp = $env:APPDATA
$previousLocal = $env:LOCALAPPDATA
$logs = Join-Path $Destination 'build-logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
function Invoke-BuildEngine([string[]]$EngineArguments, [string]$Name) {
    $out = Join-Path $logs ($Name + '.log')
    $err = Join-Path $logs ($Name + '-errors.log')
    $process = Start-Process -FilePath $GodotPath -ArgumentList $EngineArguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    $handle = $process.Handle
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    while (-not $process.WaitForExit(1000)) {
        if ([DateTime]::UtcNow -gt $deadline) { $process.Kill(); throw "$Name exceeded five minutes. See $logs" }
    }
    $process.WaitForExit()
    $diagnostics = @(Get-Content -LiteralPath $out,$err | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.$' })
    if ($process.ExitCode -ne 0 -or $diagnostics.Count) { throw "$Name failed: $($diagnostics -join '; ')" }
}
Push-Location $root
try {
    $env:APPDATA = Join-Path $root 'artifacts\build-profile'
    $env:LOCALAPPDATA = Join-Path $env:APPDATA 'local'
    $versionOut = Join-Path $logs 'version.log'
    Invoke-BuildEngine @('--version') 'version'
    $version = (Get-Content -LiteralPath $versionOut -Raw).Trim()
    if ($version -ne '4.7.2.stable.official.ed1daf0bf') { throw "Unexpected engine: $version" }
    Invoke-BuildEngine @('--headless','--path',('"' + $root + '"'),'--editor','--import') 'import'
    $exe = Join-Path $Destination 'Jingwei.exe'
    Invoke-BuildEngine @('--headless','--path',('"' + $root + '"'),'--export-release','"Windows Preview"',('"' + $exe + '"')) 'export'
    foreach ($name in @('Jingwei.exe','Jingwei.pck')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Destination $name))) { throw "Export omitted $name" }
    }
    Copy-Item -LiteralPath (Join-Path $root 'docs\releases\player-readme.txt') -Destination (Join-Path $Destination '开始游戏.txt')
    $licenses = Join-Path $Destination 'licenses'
    New-Item -ItemType Directory -Path $licenses | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'Godot\LICENSE.txt') -Destination (Join-Path $licenses 'Godot-LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $root 'Godot\COPYRIGHT.txt') -Destination (Join-Path $licenses 'Godot-COPYRIGHT.txt')
    $revision = (git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve build source revision.' }
    $dirty = [bool](git status --porcelain)
    $files = @('Jingwei.exe','Jingwei.pck','开始游戏.txt','licenses/Godot-LICENSE.txt','licenses/Godot-COPYRIGHT.txt')
    $hashes = @($files | ForEach-Object { $file = Join-Path $Destination $_; [ordered]@{path=$_; bytes=(Get-Item -LiteralPath $file).Length; sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash} })
    [ordered]@{package='QA-05'; product_version=(Get-Item -LiteralPath $exe).VersionInfo.FileVersion; engine=$version; release_template_sha256=$templateHash; source_commit=$revision; source_dirty=$dirty; architecture='Windows x86_64'; renderer='Compatibility'; signed=$false; files=$hashes} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Destination 'build-info.json') -Encoding UTF8
    # Logs and authoring tools are deliberately outside the downloadable ZIP.
    $zipFiles = @($files | ForEach-Object { Join-Path $Destination $_ }) + (Join-Path $Destination 'build-info.json')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open(($Destination + '.zip'), [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $zipFiles) {
            $relative = $file.Substring($Destination.Length + 1).Replace('\','/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file, $relative, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $zip.Dispose() }
    Write-Host "Windows preview created: $Destination.zip"
    Write-Host ('ZIP SHA-256: ' + (Get-FileHash -LiteralPath ($Destination + '.zip') -Algorithm SHA256).Hash)
} finally {
    $env:APPDATA = $previousApp
    $env:LOCALAPPDATA = $previousLocal
    Pop-Location
}
