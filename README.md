# Big Lobbies for Demonologist

A UE4SS Lua mod that lets Demonologist lobbies and matches hold up to 16 players instead of 4. Only the host
installs it: the other players join as usual.

It is based on "16-Player Lobbies" by YzzSlav (https://www.nexusmods.com/demonologist/mods/13), reworked for
the UE4SS experimental build that runs on the game's Unreal Engine 5.6.

## Features

- Up to 16 players in the lobby and in the match, with extra spawn points on the map.
- The lobby stays listed in the server browser, shown as "2/4, not started", so friends can find it
  (`lobby_shown_as_2_of_4 = no` publishes the real count).
- Raised gear limits: 16 flashlights, 16 candles, 16 sanity pills, 4 glasses, 3 crucifixes.
- The host can start the match without waiting for every "Ready".
- F4 pressed twice within 4 seconds leaves a stuck match.
- A faded "16-player mod active" line in the safe house and "16-player mod" after the version number on the
  TV menus show that the mod is running.
- Every option is in a plain text file, `settings.txt`.
- A double-click installer that finds the game, installs UE4SS when needed and keeps existing settings.

## Requirements

- Windows 10 or 11, Demonologist from Steam (tested with game version 2.3.4).
- UE4SS experimental build for Unreal Engine 5.6 (v3.0.1-1220-ga9ffb667). The All-in-one package includes it.
- To build the packages: PowerShell 7 (`pwsh`).

## Installation

Download `BigLobbies-AllInOne-<version>.zip` from the repository's Releases, close the game, unzip the
archive anywhere and double-click `INSTALL.bat`. The installer downloads nothing, moves an old incompatible
UE4SS aside instead of deleting it, and turns off the original 16-Player Lobbies mod if it is installed.

For a game that already has UE4SS, `BigLobbies-<version>.zip` holds the mod alone: drop its `Shivers` folder
into the game folder.

`UNINSTALL.bat` removes the mod and, on request, UE4SS.

## Configuration

Settings live in `<game folder>\Shivers\Binaries\Win64\ue4ss\Mods\BigLobbies\settings.txt` and are read at
startup. The main ones: `max_players` (16), `extra_gear` and the per-item limits, `start_without_ready`,
`lobby_shown_as_2_of_4`, `leave_key` (F4) and `indicator` (on / always / off). A missing or invalid line
falls back to its default. The full table is in [README.txt](README.txt).

## Usage

Start the game, host an online lobby and invite your friends. The mod's lines in
`Shivers\Binaries\Win64\ue4ss\UE4SS.log` start with `[BigLobbies]`; one minute after startup, the
"hooks status" line lists what is in place.

## Repository layout

| Path | Content |
| --- | --- |
| `INSTALL.bat`, `UNINSTALL.bat`, `README.txt`, `files/` | The All-in-one package, as shipped |
| `files/BigLobbies/` | The mod: `Scripts/main.lua`, default `settings.txt`, `enabled.txt` |
| `files/install.ps1` | The installer both `.bat` files run |
| `files/UE4SS/` | UE4SS, unpacked by `scripts/get-ue4ss.ps1` (only `VERSION.txt` is tracked) |
| `scripts/` | Download of UE4SS and build of the release files |
| `nexus/` | Nexus Mods page text, publication checklist and the permission request to the original author |

## Development

The mod is a single Lua script for UE4SS, `files/BigLobbies/Scripts/main.lua`. It runs on the host and
changes the player limits of the game instance, of the Unreal session and of the Steam session
(SteamCorePro), adds spawn points, raises the gear limits of the `DT_ShopTools` table, adjusts the "Ready"
counter and what the lobby list shows. Its timers run on the game thread (`LoopInGameThreadWithDelay`,
`ExecuteInGameThreadWithDelay`).

UE4SS has no hot reload: restart the game after changing the script.

Build the release files:

```powershell
pwsh -File scripts\get-ue4ss.ps1
pwsh -File scripts\build.ps1
```

`get-ue4ss.ps1` downloads `UE4SS_v3.0.1-1220-ga9ffb667.zip` from the UE4SS `experimental-latest` release
and refuses it if its SHA-256 differs from the pinned one. When upstream replaces that release, take
`files/UE4SS/` from the All-in-one archive of a Big Lobbies release instead. `build.ps1` writes both zips to
`dist/`, versioned from `MOD_VERSION` in `main.lua`.

The Lua script, the installer and the documentation were written with AI assistance (Claude, by Anthropic).

## License and credits

- No open-source license is granted for this mod. It derives from "16-Player Lobbies" by YzzSlav: see
  `nexus/PUBLICATION.md` before publishing it anywhere.
- UE4SS: UE4SS-RE contributors (https://github.com/UE4SS-RE/RE-UE4SS), MIT license, shipped unmodified.
- Demonologist is a game by Clock Wizard Games. This mod is not affiliated with or endorsed by them.
