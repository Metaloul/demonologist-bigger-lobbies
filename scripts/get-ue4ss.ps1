# Puts the UE4SS build that the All-in-one package ships into files\UE4SS: downloads the official archive,
# checks its SHA-256 and unpacks it next to files\UE4SS\VERSION.txt. The files are not kept in git.
# Usage: pwsh -File scripts\get-ue4ss.ps1 [-Force]
param([switch]$Force)
$ErrorActionPreference = "Stop"

$Asset = "UE4SS_v3.0.1-1220-ga9ffb667.zip"
$Url = "https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/$Asset"
$Sha256 = "900A4CDFC167ECB8447E6D78994924025364841BBC6F93746F33ED5730E67BE6"

$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root "files\UE4SS"
if ((Test-Path -LiteralPath (Join-Path $dest "ue4ss\UE4SS.dll")) -and -not $Force) {
    "UE4SS is already in files\UE4SS (use -Force to download it again)."
    return
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ue4ss-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $zip = Join-Path $tmp $Asset
    Invoke-WebRequest -Uri $Url -OutFile $zip
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($hash -ne $Sha256) {
        throw "SHA-256 of ${Asset}: $hash, expected $Sha256. The upstream file changed: do not use it."
    }
    $unpacked = Join-Path $tmp "unpacked"
    Expand-Archive -LiteralPath $zip -DestinationPath $unpacked
    Get-ChildItem -LiteralPath $dest -Force | Where-Object Name -ne "VERSION.txt" | Remove-Item -Recurse -Force
    Copy-Item -Path (Join-Path $unpacked "*") -Destination $dest -Recurse -Force
    "UE4SS ($Asset) unpacked into files\UE4SS."
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
