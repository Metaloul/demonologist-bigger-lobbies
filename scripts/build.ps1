# Builds the two release files of Big Lobbies into dist\ (PowerShell 7: its zip entries use "/").
#   BigLobbies-AllInOne-<version>.zip   INSTALL.bat, UNINSTALL.bat, README.txt, files\ (installer, mod, unmodified UE4SS)
#   BigLobbies-<version>.zip            Shivers\Binaries\Win64\ue4ss\Mods\BigLobbies\ (mod only, with README.txt)
# The version comes from MOD_VERSION in files\BigLobbies\Scripts\main.lua.
# Usage: pwsh -File scripts\get-ue4ss.ps1, then pwsh -File scripts\build.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist"
$stage = Join-Path ([IO.Path]::GetTempPath()) ("biglobbies-build-" + [guid]::NewGuid().ToString("N"))

if (-not (Test-Path -LiteralPath (Join-Path $root "files\UE4SS\ue4ss\UE4SS.dll"))) {
    throw "UE4SS is missing from files\UE4SS: run pwsh -File scripts\get-ue4ss.ps1 first."
}
$version = (Select-String -LiteralPath (Join-Path $root "files\BigLobbies\Scripts\main.lua") -Pattern 'MOD_VERSION = "([^"]+)"').Matches[0].Groups[1].Value
New-Item -ItemType Directory -Path $dist -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-Zip($folder, $zip) {
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
    [IO.Compression.ZipFile]::CreateFromDirectory($folder, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
    "{0}  {1:N0} KB" -f (Split-Path -Leaf $zip), ((Get-Item -LiteralPath $zip).Length / 1KB)
}

try {
    # All-in-one
    $a = Join-Path $stage "allinone"
    New-Item -ItemType Directory -Path $a | Out-Null
    foreach ($n in "INSTALL.bat", "UNINSTALL.bat", "README.txt", "files") { Copy-Item -LiteralPath (Join-Path $root $n) -Destination $a -Recurse }
    New-Zip $a (Join-Path $dist "BigLobbies-AllInOne-$version.zip")

    # Mod only
    $m = Join-Path $stage "modonly"
    $modDir = Join-Path $m "Shivers\Binaries\Win64\ue4ss\Mods\BigLobbies"
    New-Item -ItemType Directory -Path $modDir -Force | Out-Null
    Copy-Item -Path (Join-Path $root "files\BigLobbies\*") -Destination $modDir -Recurse
    Copy-Item -LiteralPath (Join-Path $root "README.txt") -Destination $modDir
    New-Zip $m (Join-Path $dist "BigLobbies-$version.zip")
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
