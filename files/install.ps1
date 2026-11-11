# Installer for the "Big Lobbies" mod for Demonologist.
# Started by INSTALL.bat (install / update) or UNINSTALL.bat (-Uninstall).
# Finds the game by itself (Steam), installs the UE4SS copy shipped in files\UE4SS (experimental build, compatible with
# Unreal Engine 5.6), moves an old incompatible UE4SS aside, turns off the "Multiplayer" mod folder (the original
# "16-Player Lobbies" mod, which does the same job), installs the mod, then offers to start the game to check that it
# loads. Nothing is downloaded.

param(
    [switch]$Uninstall,
    [string]$GamePath = "",     # game folder, to force it (otherwise it is found automatically)
    [switch]$NoLaunch           # do not offer to start the game at the end
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModName = "BigLobbies"
$OldModName = "Multiplayer"     # folder of the original "16-Player Lobbies" mod (and of earlier builds of this one)
$GameExe = "Shivers-Win64-Shipping.exe"
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Title($t) { Write-Host ""; Write-Host "== $t ==" -ForegroundColor Cyan }
function Ok($t)    { Write-Host "  [OK] $t" -ForegroundColor Green }
function Info($t)  { Write-Host "  $t" }
function Warn($t)  { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Fail($t)  { Write-Host ""; Write-Host "  [ERROR] $t" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------------ finding the game
function Get-SteamLibraries {
    $roots = @()
    foreach ($key in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam")) {
        try {
            $p = Get-ItemProperty -Path $key -ErrorAction Stop
            foreach ($name in @("SteamPath", "InstallPath")) {
                if ($p.$name) { $roots += ($p.$name -replace "/", "\") }
            }
        } catch { }
    }
    $roots += "${env:ProgramFiles(x86)}\Steam"
    $libraries = @()
    foreach ($r in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        $libraries += $r
        $vdf = Join-Path $r "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf) {
                if ($line -match '^\s*"path"\s*"(.+)"\s*$') { $libraries += ($Matches[1] -replace "\\\\", "\") }
            }
        }
    }
    # common places on every drive, in case Steam itself is not found
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($s in @("SteamLibrary", "Steam", "Program Files (x86)\Steam", "Games\Steam")) {
            $c = Join-Path $d.Root $s
            if (Test-Path -LiteralPath (Join-Path $c "steamapps")) { $libraries += $c }
        }
    }
    return $libraries | Select-Object -Unique
}

function Test-GameFolder($d) {
    return $d -and (Test-Path -LiteralPath (Join-Path $d "Shivers\Binaries\Win64\$GameExe"))
}

function Find-Game {
    foreach ($lib in Get-SteamLibraries) {
        $d = Join-Path $lib "steamapps\common\Demonologist"
        if (Test-GameFolder $d) { return (Resolve-Path -LiteralPath $d).Path }
    }
    return $null
}

function Select-GameFolder {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Demonologist was not found. Pick its folder (the one that contains Demonologist.exe)."
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

function Get-AppId($gameFolder) {
    # the game's Steam id, read from the library manifest (used to start the game through Steam)
    $steamapps = Split-Path -Parent (Split-Path -Parent $gameFolder)
    foreach ($m in (Get-ChildItem -LiteralPath $steamapps -Filter "appmanifest_*.acf" -ErrorAction SilentlyContinue)) {
        $txt = Get-Content -LiteralPath $m.FullName -Raw
        if ($txt -match '"installdir"\s*"Demonologist"' -and $txt -match '"appid"\s*"(\d+)"') { return $Matches[1] }
    }
    return $null
}

# ------------------------------------------------------------------ settings file
# settings.txt holds "name = value" lines. When the mod is updated, the new default file is written and every value the
# player had set is carried over (names and values of the older French settings file reglages.txt are converted).
$KeyAlias = @{
    joueurs_max = "max_players"; equipement_en_plus = "extra_gear"; lampe_torche = "flashlight"; bougie = "candle";
    pilules = "sanity_pills"; verre = "glass"; lancer_sans_pret = "start_without_ready";
    salon_affiche_2_sur_4 = "lobby_shown_as_2_of_4"; touche_quitter = "leave_key"; indicateur = "indicator"
}
$ValueAlias = @{ oui = "yes"; o = "yes"; non = "no"; n = "no"; toujours = "always"; aucune = "none"; aucun = "none" }

function Read-Settings($path) {
    $values = @{}
    if (-not (Test-Path -LiteralPath $path)) { return $values }
    foreach ($line in [System.IO.File]::ReadAllLines($path, $Utf8)) {
        $l = ($line -replace '^\uFEFF', '') -replace '[#;].*$', ''
        if ($l -match '^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$') {
            $k = $Matches[1].ToLower(); $v = $Matches[2]
            if ($KeyAlias.ContainsKey($k)) { $k = $KeyAlias[$k] }
            if ($ValueAlias.ContainsKey($v.ToLower())) { $v = $ValueAlias[$v.ToLower()] }
            if ($k -eq "indicator") {
                $onOff = @{ yes = "on"; no = "off"; none = "off" }
                if ($onOff.ContainsKey($v.ToLower())) { $v = $onOff[$v.ToLower()] }
            }
            $values[$k] = $v
        }
    }
    return $values
}

function Write-Settings($defaultPath, $targetPath, $values) {
    $out = foreach ($line in [System.IO.File]::ReadAllLines($defaultPath, $Utf8)) {
        if ($line -match '^(\s*([A-Za-z0-9_]+)\s*=\s*)(.*)$' -and $values.ContainsKey($Matches[2].ToLower())) {
            $Matches[1] + $values[$Matches[2].ToLower()]
        } else { $line }
    }
    [System.IO.File]::WriteAllText($targetPath, (($out -join "`r`n") + "`r`n"), $Utf8)
}

# ------------------------------------------------------------------ start
Write-Host ""
Write-Host "  Demonologist - Big Lobbies (up to 16 players)" -ForegroundColor White
Write-Host "  ---------------------------------------------"

Title "Finding the game"
if ($GamePath -and -not (Test-GameFolder $GamePath)) { Warn "This folder does not contain the game: $GamePath"; $GamePath = "" }
if (-not $GamePath) { $GamePath = Find-Game }
if (-not $GamePath) { $GamePath = Select-GameFolder }
if (-not (Test-GameFolder $GamePath)) { Fail "Demonologist not found. Run again and pick the game folder (in Steam: right-click the game > Manage > Browse local files)." }
$Win64 = Join-Path $GamePath "Shivers\Binaries\Win64"
$UE4SS = Join-Path $Win64 "ue4ss"
$ModFolder = Join-Path $UE4SS "Mods\$ModName"
Ok "Game found: $GamePath"

Title "The game must be closed"
$p = Get-Process -Name "Shivers-Win64-Shipping" -ErrorAction SilentlyContinue
if ($p) {
    Warn "Demonologist is running. Close it, then press Enter."
    [void](Read-Host)
    $p = Get-Process -Name "Shivers-Win64-Shipping" -ErrorAction SilentlyContinue
    if ($p) { Fail "The game is still running." }
}
Ok "The game is closed"

# A "flat" UE4SS (UE4SS.dll right in Win64: the 2024 v3.0.1 release, as installed by UE4SS Installer GUI) cannot read the
# game's Unreal Engine 5.6: it stops at startup ("PS scan timed out") and loads no mod. Its files are moved aside, never deleted.
function Move-OldUE4SS {
    $old = @("UE4SS.dll", "UE4SS-settings.ini", "UE4SS.log", "UE4SS.pdb", "Changelog.md", "README.md", "Mods", "UE4SS_Signatures", "CustomGameConfigs", "MapGenBP", "UE4SS_SDK_Backends")
    if (-not (Test-Path -LiteralPath (Join-Path $Win64 "UE4SS.dll"))) { return $false }
    $backup = Join-Path $Win64 ("_old_UE4SS_" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Path $backup | Out-Null
    foreach ($n in $old) {
        $src = Join-Path $Win64 $n
        if (Test-Path -LiteralPath $src) { Move-Item -LiteralPath $src -Destination $backup }
    }
    $dwm = Join-Path $Win64 "dwmapi.dll"
    if (Test-Path -LiteralPath $dwm) { Copy-Item -LiteralPath $dwm -Destination $backup }
    Info "Old UE4SS moved to: $backup"
    return $true
}

# ------------------------------------------------------------------ uninstall
if ($Uninstall) {
    Title "Uninstall"
    if (Test-Path -LiteralPath $ModFolder) { Remove-Item -LiteralPath $ModFolder -Recurse -Force; Ok "Mod removed" } else { Info "The mod was not installed" }
    $others = @()
    if (Test-Path -LiteralPath (Join-Path $UE4SS "Mods")) {
        $others = Get-ChildItem -LiteralPath (Join-Path $UE4SS "Mods") -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "enabled.txt") }
    }
    $answer = Read-Host "  Also remove UE4SS (the game goes back to 100% vanilla)? [Y/n]"
    if ($answer -notmatch '^[nN]') {
        if ($others.Count -gt 0) { Warn ("These other UE4SS mods will stop working too: " + (($others | ForEach-Object Name) -join ", ")) }
        [void](Move-OldUE4SS)
        if (Test-Path -LiteralPath $UE4SS) { Remove-Item -LiteralPath $UE4SS -Recurse -Force }
        $dwm = Join-Path $Win64 "dwmapi.dll"
        if (Test-Path -LiteralPath $dwm) { Remove-Item -LiteralPath $dwm -Force }
        Ok "UE4SS removed"
    }
    Write-Host ""; Ok "Done."
    exit 0
}

# ------------------------------------------------------------------ UE4SS
Title "UE4SS (the mod loader)"
if (Move-OldUE4SS) { Warn "An old UE4SS that does not work with this game was found and moved aside." }

# files\UE4SS holds an unmodified copy of a UE4SS release, laid out like Binaries\Win64 (dwmapi.dll + ue4ss\).
$bundle = Join-Path $Here "UE4SS"
$bundleDll = Join-Path $bundle "ue4ss\UE4SS.dll"
if (-not (Test-Path -LiteralPath $bundleDll)) {
    Fail "UE4SS is missing from this package ($bundle). Download the All-in-one file again, or install UE4SS yourself (github.com/UE4SS-RE/RE-UE4SS, experimental build) and copy the BigLobbies folder into ue4ss\Mods."
}
$bundleName = "UE4SS"
$versionFile = Join-Path $bundle "VERSION.txt"
if (Test-Path -LiteralPath $versionFile) { $bundleName = (Get-Content -LiteralPath $versionFile -TotalCount 1) -replace '\s*\(.*$', '' }
$currentDll = Join-Path $UE4SS "UE4SS.dll"
# a UE4SS that is already there and at least as new as the bundled one is kept
$upToDate = (Test-Path -LiteralPath $currentDll) -and ((Get-Item -LiteralPath $currentDll).LastWriteTime -ge (Get-Item -LiteralPath $bundleDll).LastWriteTime.AddMinutes(-1))
if ($upToDate) {
    Ok "UE4SS is already installed and up to date"
} else {
    foreach ($f in (Get-ChildItem -LiteralPath $bundle -Recurse -File)) {
        $rel = $f.FullName.Substring($bundle.Length).TrimStart("\")
        if ($rel -eq "VERSION.txt") { continue }
        $target = Join-Path $Win64 $rel
        # existing settings are kept
        if ((Test-Path -LiteralPath $target) -and ($f.Name -in @("UE4SS-settings.ini", "mods.txt", "mods.json"))) { continue }
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force
        Unblock-File -LiteralPath $target -ErrorAction SilentlyContinue
    }
    Ok "UE4SS installed ($bundleName)"
}

# UE4SS turns on sample mods by default (console, cheat manager, Blueprint mod loader...) that this mod does not need:
# they are turned off for a lighter startup. The Blueprint mod loader stays on when there are .pak mods in
# Content\Paks\LogicMods. Other mods (the ones you add) are not touched.
$unneeded = @("CheatManagerEnablerMod", "ConsoleCommandsMod", "ConsoleEnablerMod", "SplitScreenMod", "LineTraceMod",
              "ActorDumperMod", "jsbLuaProfilerMod", "Keybinds")
$logicMods = Join-Path $GamePath "Shivers\Content\Paks\LogicMods"
$bpPaks = @(Get-ChildItem -LiteralPath $logicMods -Filter "*.pak" -Recurse -ErrorAction SilentlyContinue)
if ($bpPaks.Count -eq 0) { $unneeded += @("BPModLoaderMod", "BPML_GenericFunctions") }
$modsTxt = Join-Path $UE4SS "Mods\mods.txt"
if (Test-Path -LiteralPath $modsTxt) {
    $txt = Get-Content -LiteralPath $modsTxt -Raw
    foreach ($n in $unneeded) { $txt = [regex]::Replace($txt, '(?m)^(\uFEFF?\s*' + [regex]::Escape($n) + '\s*:\s*)1', '${1}0') }
    [System.IO.File]::WriteAllText($modsTxt, $txt, $Utf8)
}
$modsJson = Join-Path $UE4SS "Mods\mods.json"
if (Test-Path -LiteralPath $modsJson) {
    try {
        $raw = Get-Content -LiteralPath $modsJson -Raw | ConvertFrom-Json
        # (PowerShell 5 returns a JSON array as one object: it is enumerated to get the list of mods)
        $list = New-Object System.Collections.ArrayList
        foreach ($x in @($raw)) {
            foreach ($y in @($x)) {
                if ($y.PSObject.Properties.Name -contains "mod_name") { [void]$list.Add($y) }
                elseif ($y.value) { foreach ($z in @($y.value)) { if ($z.mod_name) { [void]$list.Add($z) } } }
            }
        }
        if ($list.Count -eq 0) { throw "no mod" }
        $items = foreach ($e in $list) {
            $on = if ($unneeded -contains $e.mod_name) { "false" } elseif ($e.mod_enabled) { "true" } else { "false" }
            "    {`n        `"mod_name`": `"$($e.mod_name)`",`n        `"mod_enabled`": $on`n    }"
        }
        [System.IO.File]::WriteAllText($modsJson, "[`n" + ($items -join ",`n") + "`n]`n", $Utf8)
    } catch { Warn "mods.json could not be read, left as it is" }
}
Ok "UE4SS sample mods turned off (lighter startup)"

# ------------------------------------------------------------------ the mod
Title "Big Lobbies mod"
$source = Join-Path $Here $ModName
if (-not (Test-Path -LiteralPath (Join-Path $source "Scripts\main.lua"))) { Fail "Mod files not found next to the installer ($source)." }
# the player's settings are kept from one install to the next (and taken over from the "Multiplayer" folder the first time)
$settings = Join-Path $ModFolder "settings.txt"
$oldFolder = Join-Path $UE4SS "Mods\$OldModName"
$kept = @{}
foreach ($file in @((Join-Path $oldFolder "reglages.txt"), (Join-Path $oldFolder "settings.txt"), (Join-Path $ModFolder "reglages.txt"), $settings)) {
    foreach ($kv in (Read-Settings $file).GetEnumerator()) { $kept[$kv.Key] = $kv.Value }
}
# Two mods changing the player limits at once would fight each other: the "Multiplayer" folder (the original 16-Player
# Lobbies mod, or an earlier build of this one) is turned off. Its files stay where they are; UNINSTALL.bat does not
# turn it back on.
$oldEnabled = Join-Path $oldFolder "enabled.txt"
if (Test-Path -LiteralPath $oldEnabled) {
    Move-Item -LiteralPath $oldEnabled -Destination (Join-Path $oldFolder "enabled.txt.off") -Force
    Warn "The '$OldModName' mod (16-Player Lobbies) was turned off: Big Lobbies replaces it."
}
$modsTxt = Join-Path $UE4SS "Mods\mods.txt"
if (Test-Path -LiteralPath $modsTxt) {
    $txt = Get-Content -LiteralPath $modsTxt -Raw
    $new = [regex]::Replace($txt, '(?m)^(﻿?\s*' + $OldModName + '\s*:\s*)1', '${1}0')
    if ($new -ne $txt) { [System.IO.File]::WriteAllText($modsTxt, $new, $Utf8); Warn "'$OldModName' turned off in mods.txt too." }
}
if (Test-Path -LiteralPath $ModFolder) { Remove-Item -LiteralPath $ModFolder -Recurse -Force }
Copy-Item -LiteralPath $source -Destination $ModFolder -Recurse
if ($kept.Count -gt 0) {
    Write-Settings (Join-Path $source "settings.txt") $settings $kept
    Info "Your settings (settings.txt) were kept"
}
New-Item -ItemType File -Path (Join-Path $ModFolder "enabled.txt") -Force | Out-Null
Get-ChildItem -LiteralPath $ModFolder -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
$version = "?"
$m = Select-String -LiteralPath (Join-Path $ModFolder "Scripts\main.lua") -Pattern 'MOD_VERSION = "([^"]+)"' | Select-Object -First 1
if ($m) { $version = $m.Matches[0].Groups[1].Value }
Ok "Mod installed (version $version): $ModFolder"
Info "Settings: $settings"

Write-Host ""
Write-Host "  Installation complete." -ForegroundColor Green
Write-Host "  Only the host needs the mod: host the game, your friends join it as usual."

# ------------------------------------------------------------------ check
if ($NoLaunch) { exit 0 }
$answer = Read-Host "`n  Start Demonologist now to check that the mod loads? [Y/n]"
if ($answer -match '^[nN]') { exit 0 }
$log = Join-Path $UE4SS "UE4SS.log"
$started = Get-Date
$appid = Get-AppId $GamePath
if ($appid) { Start-Process "steam://rungameid/$appid" } else { Start-Process -FilePath (Join-Path $GamePath "Demonologist.exe") -WorkingDirectory $GamePath }
Info "The game is starting... (waiting up to 3 minutes for the mod to report in)"
$deadline = (Get-Date).AddMinutes(3)
$result = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 3
    if (-not (Test-Path -LiteralPath $log)) { continue }
    if ((Get-Item -LiteralPath $log).LastWriteTime -lt $started) { continue }
    $txt = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
    if (-not $txt) { continue }
    if ($txt -match '\[BigLobbies\] loaded \(target (\d+) players\)') { $result = "ok"; break }
    if ($txt -match 'Fatal Error') { $result = "ue4ss"; break }
    if ($txt -match '\[BigLobbies\].*ERROR|BigLobbies.*(syntax error|error loading)') { $result = "mod"; break }
}
switch ($result) {
    "ok"    { Ok "The mod is loaded in the game. You can host a lobby of up to $($Matches[1]) players." }
    "ue4ss" { Warn "UE4SS could not start with this version of the game. Please send this file: $log" }
    "mod"   { Warn "The mod reported an error. Please send this file: $log" }
    default { Warn "No confirmation within 3 minutes (the game may be slow to start). Check ${log}: the line '[BigLobbies] loaded' should be there." }
}
