---
type: Tool
title: Reference game
description: Running the real Windows Skyrim SE under Apple's Game Porting Toolkit 4 on the
  same Mac, putting it at OpenSky's view, and comparing the two frames side by side.
tags: [tool, reference, gptk, wine, comparison, rendering]
---

# Reference game

The reference game is the real Windows Skyrim SE, run on this Mac under Apple's Game Porting
Toolkit (GPTK). It loads the same data as OpenSky, so a capture from each side at the same
view shows each difference directly: rendering, lighting, weather, UI, and actors.

It is developer tooling. The scripts are in `reference/`, the rules in the `OpenSkyReference`
module, and the commands in `openskycli reference`. No release bundles Wine or GPTK, and the
app lists the Reference Game page only once a prefix is set.

## How the pieces fit

- **Wine** is the gcenx `game-porting-toolkit` Homebrew cask. It runs under Rosetta 2.
  Apple ships GPTK 4 as an "evaluation environment for Windows games": D3DMetal, which turns
  DirectX 11 and 12 into Metal, plus Wine-side libraries, but no runnable Wine. The
  GPTK disk image holds a second image, "Evaluation environment for Windows games". Its
  `redist/lib/` holds only D3DMetal and the Direct3D, DXGI, and NVAPI parts of Wine, not
  Wine itself (no `ntdll.so`). Setup keeps the cask's `lib/external` and `lib/wine` as
  `external.cask` and `wine.cask`, copies them back, and lays `redist/lib/` over them.
- **The prefix** is one self-contained fake Windows folder tree. It holds Windows Steam,
  because the game's copy protection needs a logged-in client, and the game's own copy.
- **The game copy** is an APFS clone of the install OpenSky reads. A clone shares disk
  blocks with the original until one side writes, so it costs almost no space. Windows Steam
  may update or repair the copy; the original stays untouched, because OpenSky treats it as
  read-only input.

Every write goes into the prefix or `.logs/`: the `SkyrimPrefs.ini` edit, the console batch
file, the Wine logs, and the captures. A capture shows game assets, so it never leaves
`.logs/` (root `AGENTS.md`, Legal & IP boundary).

## Setup

Run once per machine. Each step is skipped when its result is already there, so a rerun
continues where the last one stopped.

1. Install Rosetta 2. It needs an administrator password:
   `softwareupdate --install-rosetta --agree-to-license`.
2. Sign in at <https://developer.apple.com/games/game-porting-toolkit/>, download the Game
   Porting Toolkit 4 disk image, open it, and open the "Evaluation environment for Windows
   games" image inside it. Setup finds that second volume.
3. Run `make reference-setup PREFIX=<folder>`. Pick a folder on the same APFS volume as the
   game, outside the repo and outside the install, so the clone is instant. `GAME=<install>`
   overrides the `OpenSkyDataRoot` setting as the copy's source. The script:
   1. taps `gcenx/wine` and installs the cask;
   2. copies the GPTK 4 libraries into the cask's Wine;
   3. creates the prefix and sets Windows 10;
   4. downloads and runs the Windows Steam installer;
   5. clones the game and its `appmanifest_489830.acf` into the prefix's Steam library;
   6. stores the folder as the `OpenSkyReferencePrefix` setting.
4. Run `make reference-game`. Log in to Steam once in the window that opens. In the game's
   Steam properties, set updates to "Only update this game when I launch it", so the copy
   stays on the same build as the install.
5. Run `make reference-check`. It compares the Steam `buildid` of both installs and the
   SHA-256 of every `.esm`, and names each difference.

The setting has an environment override, `OPENSKY_REFERENCE_PREFIX`. The Wine binary is
found the same way: `OPENSKY_REFERENCE_WINE`, then `OpenSkyReferenceWine`, then the cask's
paths. The Settings page shows the prefix with "Show details" on.

## Launching

`make reference-game` (`openskycli reference launch`) does three things:

1. It writes `bBorderless=1`, `bFull Screen=0`, `iSize W`, and `iSize H` into the prefix's
   `SkyrimPrefs.ini`, starting from the game's `High.ini` preset when the game has not
   written the file yet. Under GPTK the window size goes wrong without these keys
   (<https://www.applegamingwiki.com/wiki/The_Elder_Scrolls_V:_Skyrim_Special_Edition>). The
   default size is 1280 x 720; `ARGS='--width 1920 --height 1080'` changes it.
2. It starts Windows Steam with `-silent` unless a `steam.exe` already runs, and waits
   `--steam-wait` seconds for the login.
3. It starts `SkyrimSE.exe` from its own folder, the way the SKSE loader does, so Steam does
   not open the game's launcher window.

The environment sets `WINEMSYNC=1` for faster thread waits. It turns off the Metal HUD
(`MTL_HUD_ENABLED=0`) and MetalFX upscaling (`D3DM_ENABLE_METALFX=0`), because both change
the captured image. Wine's output goes to `.logs/reference-game/<UTC time>/`.

## Same view, two games

Put both games in first person first. The console has no command for the camera mode.

From OpenSky to the reference game:

1. With OpenSky running, `make reference-view` (`openskycli reference export-view`) reads
   `game state view` and writes the batch file `opensky` into the reference copy's game
   folder. The game reads a batch file there only without an extension
   (<https://en.uesp.net/wiki/Skyrim:Console#Using_Batch_Files_with_the_bat_Command>).
2. In the reference game, open the console and type `bat opensky`.

The batch file holds standard console commands:

| Command | Sets |
| --- | --- |
| `cow <worldspace> <x> <y>` or `coc <cell>` | The worldspace cell, or the interior by editor ID |
| `player.setpos x/y/z` | The player's feet |
| `player.setangle x` | Pitch; the console's positive pitch looks down |
| `player.setangle z` | Heading; 0 is north (+Y) and it turns clockwise |
| `set gamehour to` | The hour |
| `fw <FormID>` | The weather, without a transition |
| `fov <angle>` | The field of view |
| `tm` | Hides the HUD. It toggles, so a second run shows it again; `--no-hide-menus` leaves it out |
| `tfc 1` | Only with `--freeze`: frees the camera and freezes the world. It toggles too |

From the reference game to OpenSky: save in the reference game, then use Import Newest Save
on the Reference Game page. It runs the normal Skyrim save import
([save import](/engine/ess-import.md)) on the newest `.ess` in the prefix's `Saves/` folder,
which puts OpenSky at the save's position and time. Pointing the Skyrim saves folder setting
at that folder lists every reference save in the load list.

### Field of view

OpenSky's view is 65 degrees vertical. The UESP console page says the console's default is
"about 65" in one place and 75 in another, and it does not say which axis it measures. The
batch file assumes a horizontal angle measured at a 4:3 view, the usual reading for Skyrim,
so 65 degrees vertical becomes `fov 80.69`. This is unverified: the first matched capture
pair confirms or corrects it.

## Capture and compare

After `bat opensky`, `make reference-capture` (`openskycli reference capture`) writes one run
folder, `.logs/reference/<UTC time>/`:

| File | Holds |
| --- | --- |
| `opensky.png` | OpenSky, rendered at the window size without the interface |
| `reference.png` | The reference window, captured with `screencapture -l` and scaled to the window size |
| `difference.png` | Four times the absolute difference of each channel |
| `opensky.txt` | The batch file of this view |
| `report.json` | The view, the size, the RGB PSNR, and the largest channel error |

The reference window is the biggest normal window whose owner name holds "wine" or
"skyrim". The capture needs the Screen Recording permission for the terminal.

The Reference Game page shows the newest run: side by side, Flip (one image at full width;
press it again to swap the games), and Difference. PSNR is only a rough signal between two
engines: different noise, shadow filtering, or a cloud a few pixels off lowers it as much as
a real bug.

## Caveats

- The gcenx cask is kept up by one person, and a macOS update can break it. CrossOver is
  the paid fallback.
- D3DMetal's output is close to Windows, not identical. Check a rendering difference
  against a Windows screenshot before filing it as an OpenSky bug.
- Metal GPU captures of the reference game would show its passes and render targets. They
  need the owner's decision first. Translated shaders could be read for structure only; their
  code never goes into OpenSky.
