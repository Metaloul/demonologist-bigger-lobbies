Demonologist - Big Lobbies (v1.6.0)
===================================

Play Demonologist with up to 16 players instead of 4. Only the host installs the mod: everyone else joins as usual.

Big Lobbies is based on "16-Player Lobbies" by YzzSlav:
https://www.nexusmods.com/demonologist/mods/13


FEATURES
  - Up to 16 players in the lobby and in the match; the map gets extra spawn points.
  - The lobby stays visible in the server list (shown as "2/4, not started") so your friends can find it.
    Strangers browsing the list see "2/4" too; set lobby_shown_as_2_of_4 = no to publish the real count.
  - More gear: up to 16 flashlights, 16 candles and 16 sanity pills, 4 glasses and 3 crucifixes.
  - The host can start the match without waiting for everyone to be "Ready".
  - Match stuck? Press F4 twice within 4 seconds to leave it.
  - The game keeps the real player count: only what the server list shows is changed.
  - Everything is set in a plain text file (settings.txt).
  - You can tell the mod is running without it getting in the way: "16-player mod" is added after the
    version number at the bottom of the TV menus, and a small faded "16-player mod active" line shows in
    the bottom-right corner of the screen in the safe house (and during the first 20 seconds of a match).


REQUIREMENTS
  - Windows 10 or 11, Demonologist installed through Steam (tested with game version 2.3.4).
  - UE4SS, experimental build for Unreal Engine 5.6. The All-in-one download includes it; the Mod-only
    download needs it installed first (github.com/UE4SS-RE/RE-UE4SS, release "experimental-latest").
  - A game update can break the mod until it is updated.


INSTALLATION
  All-in-one download (recommended):
    1. Close the game.
    2. Unzip the archive anywhere, then double-click INSTALL.bat.
    3. Answer "Y" to start the game: the installer confirms that the mod is loaded.

    The installer finds the game by itself (otherwise it asks for its folder), then copies UE4SS and the
    mod. It downloads nothing. It turns off the sample mods that come with UE4SS (console, cheat
    manager...), which this mod does not need, for a lighter startup; the Blueprint mod loader stays on if
    you have .pak mods in Content\Paks\LogicMods. An old, incompatible UE4SS is moved aside to
    Shivers\Binaries\Win64\_old_UE4SS_<date>, never deleted. If the original 16-Player Lobbies mod
    (ue4ss\Mods\Multiplayer) is installed, it is turned off, since both change the same limits, and its
    settings are carried over.
    To update the mod, run INSTALL.bat again: your settings are kept, and settings added by the new
    version get their default value.

    If Windows shows "Windows protected your PC": "More info" > "Run anyway".

  Mod-only download (manual):
    1. Install UE4SS (experimental build) in Shivers\Binaries\Win64.
    2. Drop the archive's Shivers folder into the game folder (next to Demonologist.exe).
    3. If ue4ss\Mods\Multiplayer exists (the original 16-Player Lobbies mod), delete its enabled.txt.


USAGE
  Start the game, host an online lobby and invite your friends. They have nothing to install.


CONFIGURATION
  Nothing to do by default. To change something, open this file with Notepad:
    <game folder>\Shivers\Binaries\Win64\ue4ss\Mods\BigLobbies\settings.txt
  (the installer shows this path at the end), change a value, save and restart the game.

    max_players            maximum number of players (2 to 32; the mod is designed for 16)    16
    extra_gear             raised gear limits (yes / no)                                       yes
    flashlight, candle,    maximum count of each item when extra_gear = yes                    16, 16,
    sanity_pills, glass,                                                                       16, 4,
    crucifix                                                                                   3
    start_without_ready    start the match without waiting for "Ready" (yes / no)              yes
    lobby_shown_as_2_of_4  the lobby is listed as "2/4, not started" (yes / no)                yes
    leave_key              key to press twice to leave (F4, F7, END...) or none                F4
    indicator              "mod active" line in the bottom-right corner: on (safe house and    on
                           start of a match), always, off

  A deleted or invalid line goes back to its default value; the log (see below) lists the values read
  on its "settings" line.


UNINSTALL
  Double-click UNINSTALL.bat (All-in-one download). It removes the mod and, if you answer "Y", UE4SS
  too (the game goes back to vanilla). By hand: delete ue4ss\Mods\BigLobbies.


TROUBLESHOOTING
  The log is here:
    <game folder>\Shivers\Binaries\Win64\ue4ss\UE4SS.log
  The mod's lines start with [BigLobbies]. One minute after startup, the "hooks status" line tells what
  is in place. After a game update, run INSTALL.bat again, then share this log if it still does not work.


PACKAGE CONTENTS (All-in-one download)
  INSTALL.bat                install and update with a double-click
  UNINSTALL.bat              uninstall
  files\install.ps1          the script both .bat files run
  files\BigLobbies\          the mod (Lua script for UE4SS and the default settings.txt)
  files\UE4SS\               an unmodified copy of UE4SS (see files\UE4SS\VERSION.txt and
                             files\UE4SS\ue4ss\LICENSE)


DEVELOPMENT
  The mod is a Lua script for UE4SS (files\BigLobbies\Scripts\main.lua). It works on the host's side:
  player limits of the game instance, of the Unreal session and of the Steam session (SteamCorePro),
  extra spawn points, gear limits from the DT_ShopTools table, the "Ready" counter, and what the lobby
  list shows. For that list, the game's player counter holds the shown value only while the lobby is
  published to Steam, then goes back to the real count.
  Its timers use UE4SS's delayed actions on the game thread (LoopInGameThreadWithDelay,
  ExecuteInGameThreadWithDelay); a UE4SS build without them is reported in the log and the mod stays off.
  The indicator is a TextBlock added to the game's crosshair widget (WBP_Crosshair), which never takes
  mouse input; the TV text is appended to the VerTxt text of WBP_SmartTVTopInfo.
  Written with AI assistance (Claude, by Anthropic): the Lua script, the installer and this file.


CREDITS AND LICENSE
  - Original mod, "16-Player Lobbies": YzzSlav (https://www.nexusmods.com/demonologist/mods/13).
  - UE4SS: UE4SS-RE contributors (https://github.com/UE4SS-RE/RE-UE4SS), MIT license
    (files\UE4SS\ue4ss\LICENSE).
  - Demonologist is a game by Clock Wizard Games. This mod is not affiliated with or endorsed by them.
