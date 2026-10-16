param(
    [ValidateSet('Run', 'Editor', 'Test', 'Sample')][string]$Mode = 'Run',
    [string]$GodotPath,
    [switch]$NonInteractive,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $projectRoot '.tools\godot-path.txt'
$logRoot = Join-Path $projectRoot 'artifacts'
$enginePath = $null

function Resolve-Engine([string]$Candidate) {
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }
    $candidatePath = $Candidate.Trim().Trim('"')
    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
        $resolved = (Resolve-Path -LiteralPath $candidatePath).Path
        # Prefer the console companion so version checks and diagnostics are reliable.
        if ($resolved.EndsWith('.exe') -and -not $resolved.EndsWith('_console.exe')) {
            $console = $resolved.Substring(0, $resolved.Length - 4) + '_console.exe'
            if (Test-Path -LiteralPath $console -PathType Leaf) { return $console }
        }
        return $resolved
    }
    return $null
}

function Resolve-BundledEngine {
    $bundleFolder = Join-Path $projectRoot 'Godot'
    $bundlePath = Join-Path $bundleFolder 'Godot_v4.7.2-stable_win64.zip'
    if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) { return $null }
    $guiPath = Join-Path $bundleFolder 'Godot_v4.7.2-stable_win64.exe'
    $consolePath = Join-Path $bundleFolder 'Godot_v4.7.2-stable_win64_console.exe'
    if (-not (Test-Path -LiteralPath $guiPath -PathType Leaf) -or -not (Test-Path -LiteralPath $consolePath -PathType Leaf)) {
        # CMD launched from PowerShell 7 can inherit its module paths. Use the
        # Windows PowerShell modules that ship with the interpreter running us.
        Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility') -ErrorAction Stop
        Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Archive') -ErrorAction Stop
        Write-Host 'Preparing the included Godot engine. No download is needed...'
        $expectedHash = '6BF5B2D5BB1580D62615DE321EE4D5896CE0DB452603CA61F1AB9B5157D9AB87'
        if ((Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash -ne $expectedHash) {
            throw 'The included Godot ZIP is incomplete or damaged. Download and fully extract the repository again.'
        }
        Expand-Archive -LiteralPath $bundlePath -DestinationPath $bundleFolder -Force
        if (-not (Test-Path -LiteralPath $guiPath -PathType Leaf) -or -not (Test-Path -LiteralPath $consolePath -PathType Leaf)) {
            throw 'The included Godot engine could not be extracted. Check that the game folder is writable.'
        }
    }
    return $consolePath
}

function Invoke-Engine([string[]]$Arguments, [string]$LogName) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    # Windows PowerShell 5.1 represents redirected native stderr as ErrorRecord.
    # Collect it without terminating early; check the exit code AND Godot diagnostics.
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $script:enginePath @Arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            $lines.Add($line)
            Write-Host $line
        }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedPreference
    }
    $lines | Out-File -LiteralPath (Join-Path $script:logRoot $LogName) -Encoding utf8
    $failures = @($lines | Where-Object {
        $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.'
    })
    if ($code -ne 0 -or $failures.Count -gt 0) {
        throw "Godot did not finish successfully. Please send artifacts\$LogName with the error report."
    }
}

try {
    if ($GodotPath -or $env:GODOT_EXE) {
        $requested = if ($GodotPath) { $GodotPath } else { $env:GODOT_EXE }
        $enginePath = Resolve-Engine $requested
        if (-not $enginePath) { throw "Godot executable not found: $requested. Set GODOT_EXE to the full executable path, or clear it to use automatic detection." }
    }
    if (-not $enginePath) { $enginePath = Resolve-BundledEngine }
    if (-not $enginePath -and (Test-Path -LiteralPath $settingsPath)) {
        $enginePath = Resolve-Engine (Get-Content -LiteralPath $settingsPath -Raw -Encoding utf8)
    }
    # Portable downloads need no hardcoded version filename or neighbouring project.
    foreach ($folder in @((Join-Path $projectRoot '.tools\godot'), (Join-Path $projectRoot 'Godot'), $projectRoot)) {
        if ($enginePath) { break }
        if (Test-Path -LiteralPath $folder -PathType Container) {
            foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter 'Godot*.exe' -File | Sort-Object Name -Descending)) {
                $enginePath = Resolve-Engine $file.FullName
                if ($enginePath) { break }
            }
        }
    }
    if (-not $enginePath) {
        foreach ($command in @('godot', 'godot4')) {
            $found = Get-Command $command -CommandType Application -ErrorAction SilentlyContinue
            if ($found) { $enginePath = Resolve-Engine $found.Source; break }
        }
    }
    # Optional compatibility with the existing local workspace; never required.
    if (-not $enginePath) {
        $shared = Join-Path (Split-Path -Parent $projectRoot) 'RainyArrow\.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
        $enginePath = Resolve-Engine $shared
    }
    $picked = $false
    if (-not $enginePath) {
        Write-Host 'The bundled Godot engine is missing from this copy of the project.'
        Write-Host 'Download and extract the standard Windows Godot 4 build: https://godotengine.org/download/windows/'
        Write-Host 'Put the extracted Godot executables in the Godot folder next to Play.cmd, or select your existing executable.'
        if (-not $NonInteractive -and -not $Check -and $Mode -ne 'Test') {
            Add-Type -AssemblyName System.Windows.Forms
            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            try {
                $dialog.Title = 'Select Godot 4 executable (standard Windows build)'
                $dialog.Filter = 'Godot executable (Godot*.exe)|Godot*.exe'
                $dialog.CheckFileExists = $true
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $enginePath = Resolve-Engine $dialog.FileName
                    $picked = $true
                }
            } finally { $dialog.Dispose() }
        }
        if (-not $enginePath) { throw 'Godot 4 was not found. Extract Godot into the Godot folder, then double-click Play.cmd again.' }
    }
    $version = (& $enginePath --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.') { throw "Expected a Godot 4 executable; received: $version" }
    Write-Host "Godot $version"
    Write-Host "Engine: $enginePath"
    if ($picked) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $settingsPath) -Force | Out-Null
        Set-Content -LiteralPath $settingsPath -Value $enginePath -Encoding utf8
    }
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    if ($Mode -eq 'Test' -or $Check) {
        $env:APPDATA = Join-Path $logRoot 'qa-profile'
        $env:LOCALAPPDATA = Join-Path $logRoot 'qa-profile\local'
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
    }
    if ($Mode -eq 'Sample' -and -not $Check) {
        $env:APPDATA = Join-Path $logRoot 'sample-profile'
        $env:LOCALAPPDATA = Join-Path $logRoot 'sample-profile\local'
        New-Item -ItemType Directory -Path $env:APPDATA, $env:LOCALAPPDATA -Force | Out-Null
    }
    if ($Mode -eq 'Editor') {
        Invoke-Engine @('--path', $projectRoot, '--editor') 'editor-launch.log'
    } else {
        # Required on EVERY fresh checkout, and after new scripts/audio are pulled.
        # Test-only importing hid this failure in the previous Play.cmd workflow.
        Write-Host 'Preparing game scripts and audio. The first launch may take a moment...'
        Invoke-Engine @('--headless', '--path', $projectRoot, '--editor', '--import', '--quit') 'startup-import.log'
        if ($Mode -eq 'Test') {
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_runner.gd') 'state-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_game.gd', '--', '--qa') 'game-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_throw_height.gd', '--', '--qa') 'throw-height-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_audio.gd', '--', '--qa') 'audio-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_ui.gd', '--', '--qa') 'ui-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_preferences.gd') 'preferences-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_first_person.gd') 'first-person-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_first_person_polish.gd') 'first-person-polish-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_first_person_body.gd') 'first-person-body-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_loading.gd') 'loading-tests.log'
            $startupFixture = Join-Path $logRoot ('startup-test-' + [Guid]::NewGuid().ToString('N'))
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_startup.gd', '--', ('--startup-out=' + $startupFixture), ('--save-path=' + (Join-Path $startupFixture 'journey.json'))) 'startup-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_visuals.gd', '--', '--qa') 'visual-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_jingwei.gd', '--', '--qa') 'jingwei-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_pangolin.gd', '--', '--qa') 'pangolin-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_mountain.gd', '--', '--qa') 'mountain-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_environment.gd', '--', '--qa') 'environment-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_expansion.gd', '--', '--qa') 'expansion-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_feedback.gd', '--', '--qa') 'feedback-tests.log'
            Invoke-Engine @('--headless', '--fixed-fps', '60', '--path', $projectRoot, '--script', 'res://tests/test_vertical_slice.gd', '--', '--qa') 'vertical-slice-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_player_locator.gd', '--', '--qa') 'player-locator-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_release_assets.gd') 'release-assets-tests.log'
            # This test exercises real save/load; the script sets every save path
            # to its own artifacts folder before the main scene enters the tree.
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_release.gd') 'release-regression-tests.log'
            Invoke-Engine @('--headless', '--path', $projectRoot, '--script', 'res://tests/test_game.gd', '--', '--qa', '--imported-visuals') 'imported-game-tests.log'
        } elseif ($Check) {
            $entry = if ($Mode -eq 'Sample') { 'res://scenes/art/vertical_slice.tscn' } else { 'res://scenes/startup.tscn' }
            Invoke-Engine @('--headless', '--path', $projectRoot, $entry, '--quit-after', '120', '--', '--qa') 'startup-check.log'
            Write-Host 'Fresh-start check passed.'
        } elseif ($Mode -eq 'Sample') {
            Invoke-Engine @('--path', $projectRoot, 'res://scenes/art/vertical_slice.tscn') 'sample-launch.log'
        } else {
            Invoke-Engine @('--path', $projectRoot) 'game-launch.log'
        }
    }
    exit 0
} catch {
    Write-Host ''
    Write-Host ('Startup failed: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
