param([Parameter(Mandatory=$true)][string]$ArchivePath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $root '.tools\export-templates'
$expected = 'F298490B8D44D934BE425A5A65A51BF15F422428B229A06A6E11D9FFEA248011'
if ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash -ne $expected) {
    throw 'Expected the official Godot 4.7.2 standard export templates archive. SHA-256 mismatch.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ArchivePath).Path)
try {
    $version = $archive.GetEntry('templates/version.txt')
    if (-not $version) { throw 'Missing template version.' }
    $reader = New-Object IO.StreamReader($version.Open())
    try { $versionText = $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
    if ($versionText -ne '4.7.2.stable') { throw "Unexpected template version: $versionText" }
    $entry = $archive.GetEntry('templates/windows_release_x86_64.exe')
    if (-not $entry) { throw 'Missing Windows x86_64 release template.' }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $destination 'windows_release_x86_64.exe'), $true)
    Write-Host 'Verified and prepared Godot 4.7.2 Windows release template.'
} finally { $archive.Dispose() }
