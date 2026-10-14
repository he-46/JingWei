param(
    [string]$GodotPath,
    [string]$OutputDirectory,
    [ValidateSet(0, 100000, 1000000, 10000000, 100000000)][long]$Target = 0,
    [ValidateSet('', 'coast', 'mountain', 'inland', 'deep_sea', 'overview')][string]$View = '',
    [ValidateRange(1, 60)][double]$Seconds = 5,
    [ValidateSet('1440x900', '1152x720')][string]$Resolution = '1440x900'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'artifacts\art\baseline-run' }
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $projectRoot $OutputDirectory }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

# A child process prepares bundled Godot and imports resources, without ending
# this script through run.ps1's exit or inheriting its temporary environment.
$prepare = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'run.ps1'), '-Check', '-NonInteractive')
if ($GodotPath) { $prepare += @('-GodotPath', $GodotPath) }
& powershell.exe @prepare
if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare project for the art baseline.' }
if (-not $GodotPath) { $GodotPath = Join-Path $projectRoot 'Godot\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw 'Set -GodotPath to the console executable, or use the bundled engine.' }
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
$savedAppData = $env:APPDATA
$savedLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $OutputDirectory 'qa-profile'
    $env:LOCALAPPDATA = Join-Path $OutputDirectory 'qa-profile\local'
    New-Item -ItemType Directory -Path $env:APPDATA, $env:LOCALAPPDATA -Force | Out-Null
    $arguments = @('--path', $projectRoot, '--resolution', $Resolution, '--borderless', '--script', 'res://tests/art_baseline.gd', '--', '--qa', "--baseline-out=$OutputDirectory", "--baseline-seconds=$($Seconds.ToString([Globalization.CultureInfo]::InvariantCulture))")
    if ($Target) { $arguments += "--baseline-target=$Target" }
    if ($View) { $arguments += "--baseline-view=$View" }
    # Windows paths cannot contain a quote; quote each argument to retain spaces.
    $quoted = @($arguments | ForEach-Object { '"' + $_ + '"' })
    $stdout = Join-Path $OutputDirectory 'run.log'
    $stderr = Join-Path $OutputDirectory 'error.log'
    $process = Start-Process -FilePath $GodotPath -ArgumentList $quoted -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    # Keep the process handle open so Windows PowerShell 5.1 retains ExitCode.
    $processHandle = $process.Handle
    while (-not $process.WaitForExit(1000)) { }
    $process.WaitForExit()
    $errors = @(Get-Content -LiteralPath $stderr | Where-Object { $_ -match '^(ERROR:|SCRIPT ERROR:)' -and $_ -notmatch '^ERROR: Failed to read the root certificate store\.' })
    if ($process.ExitCode -ne 0 -or $errors.Count -gt 0) { throw "Baseline failed. See $stderr" }
    Get-Content -LiteralPath $stdout
    if (-not (Test-Path -LiteralPath (Join-Path $OutputDirectory 'results.json'))) { throw 'Baseline did not write results.json.' }
} finally {
    $env:APPDATA = $savedAppData
    $env:LOCALAPPDATA = $savedLocalAppData
}
