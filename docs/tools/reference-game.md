---
type: Tool
title: Reference game
description: Running the real Windows Skyrim SE under Wine 11 and DXVK on the same Mac,
  putting it at OpenSky's view, and comparing the two frames side by side.
tags: [tool, reference, wine, dxvk, comparison, rendering]
---

# Reference game

The reference game is the real Windows Skyrim SE, run on this Mac under Wine. It loads the
same data as OpenSky, so a capture from each side at the same view shows each difference
directly: rendering, lighting, weather, UI, and actors.

The setup script is in `reference/`, the rules in the `OpenSkyReference` module, the
commands in `openskycli reference`, and the buttons on the launcher's Reference Game page.
No release bundles Wine or DXVK; setup downloads them.

## How the pieces fit

Everything lives in one folder, the prefix, on the external disk:

| Part | Where | What it is |
| --- | --- | --- |
| Wine 11.0 | `opensky-runtime/wine/` | Gcenx's `wine-stable-11.0_1` build of upstream Wine. It runs under Rosetta 2 |
| DXVK | `opensky-runtime/dxvk/`, copied into the game folder | Direct3D 11 on Vulkan (zlib licence). Wine runs Vulkan on Metal through MoltenVK |
| GStreamer | `opensky-runtime/gstreamer/` | Decodes the game's xWMA audio for Wine (LGPL) |
| Steam helper | `opensky-runtime/steam-support/` | soju's web helper wrapper (MIT) |
| Wine prefix | `drive_c/`, `*.reg` | One fake Windows folder tree, with Windows Steam in it |
| Game copy | Steam's `steamapps/common/` | An APFS clone of the install OpenSky reads |

- **Windows Steam** is needed, because the game's copy protection wants a logged-in client.
  Starting the game without Steam, or removing the protection, is not an option.
- **The game copy** shares disk blocks with the original until one side writes, so it costs
  almost no space. Windows Steam may update or repair the copy; the original stays
  untouched, because OpenSky treats it as read-only input.
- **DXVK, not D3DMetal.** The game's frames come from DXVK's translation, not from
  Apple's. "Why not D3DMetal or DXMT" below gives the reasons.

Every write goes into the prefix or `.logs/`: the `SkyrimPrefs.ini` edit, the console batch
file, the Wine logs, and the captures. Wine's default breaks this in two ways, and setup
undoes both. It links the Wine user's `Desktop`, `Documents`, and other folders to the
macOS home folder, so the game's ini and saves would land in `~/Documents/My Games`; setup
replaces the links with real folders, and the launcher refuses to write through a link that
leaves the prefix. `winemenubuilder` writes `.desktop` files to `~/Desktop` and
`~/.local/share`; setup and the launcher turn it off. A capture shows game assets, so it never leaves
`.logs/` (root `AGENTS.md`, Legal & IP boundary).

## Why Steam needs repairs under Wine

These facts come from the soju project (<https://github.com/BCD1210/soju>), which runs
Steam on the same Wine build. OpenSky reimplements its recipe in `reference/setup.sh` and
`OpenSkyReference`. It copies no soju code; setup downloads soju's published
`steam-support-v2` package, uses only its web helper wrapper, and checks its SHA-256.

- **Black Steam window.** Steam's browser (CEF, the Chromium Embedded Framework) draws
  nothing under Wine when it uses the GPU or a separate process. The wrapper starts
  `steamwebhelper_real.exe` with `--disable-gpu --single-process`. A Steam update puts
  Valve's helper back, so the launcher swaps it again before each start: a helper over
  500 KB is Valve's, the wrapper is a few KB.
- **Steam flags.** `steam.exe -no-cef-sandbox -cef-single-process`, plus `-noverifyfiles`
  once the client is downloaded, so Steam does not restore its own helper.
- **No login.** Wine's own `bcrypt` and `ncrypt` are forced (`bcrypt=b;ncrypt=b`), and the
  Steam overlay DLLs are off.
- **Frozen client.** Wine 11.0 probes each audio device format by format in Steam's main
  loop. With virtual audio devices this stalls Steam before login, so `steam.exe` gets
  `winecoreaudio.drv=disabled` as a per-program override.
- **Windowless start after a crash.** Chromium's `Singleton*` and `*.lock` files in the Wine
  user's `AppData/Local/Steam/htmlcache` stay behind. The launcher deletes them.

## What the game needs under Wine

- **The Steam API restart.** `SkyrimSE.exe` started outside Steam asks Steam to start it
  again (`steam://run/489830`), and Steam opens the game's launcher window. Steam marks the
  games it starts with the `SteamAppId` and `SteamGameId` environment variables; the launcher
  sets both for the game. The game still needs the logged-in client for its ownership check.
- **Direct3D.** `SkyrimSE.exe` gets `d3d11,d3d10core=native` as per-program overrides and
  loads DXVK's DLLs from its own folder. `dxgi` stays Wine's own. Steam keeps Wine's own
  Direct3D.
- **Audio.** The game's music and many sounds are xWMA (`.xwm`). Wine decodes them through
  GStreamer, which this Wine build looks for only in `/Library/Frameworks`. Without it Wine
  logs `GStreamer doesn't support WMA decoding`. Setup unpacks the official GStreamer runtime
  package (<https://gstreamer.freedesktop.org/data/pkg/osx/>) into the runtime folder instead
  of installing it. The launcher points `DYLD_FALLBACK_LIBRARY_PATH`, `GST_PLUGIN_SYSTEM_PATH`,
  and `GST_PLUGIN_SCANNER` at it, and `GST_REGISTRY` keeps GStreamer's plugin cache out of
  `~/.cache`.

## Why not D3DMetal or DXMT

- **D3DMetal** comes with Apple's Game Porting Toolkit. Its Wine (7.7) crashes in the
  current Steam client, and GPTK 4 ships no Wine of its own: only D3DMetal and the Direct3D
  parts of Wine. Laid over Wine 11 it crashed Steam.
- **DXMT** (<https://github.com/3Shain/dxmt>), Direct3D 11 on Metal, aborts Skyrim at
  startup with `Pure virtual function called`. The game releases one texture twice. On
  Windows and DXVK the second call lands on a harmless function; in DXMT v0.80 it lands on
  a pure virtual one (DXMT issue #231). The fix is only on DXMT's main branch, and that
  branch needs a `macdrv_functions` table that only DXMT's own Wine exports.
- **DXVK** runs on Vulkan, which Wine 11 maps to Metal through its bundled MoltenVK. The
  newest macOS build is Gcenx's DXVK-macOS 1.10.3 (<https://github.com/Gcenx/DXVK-macOS>).
  It reaches the main menu. MoltenVK is fine here, because the "Metal 4 only, no MoltenVK"
  rule is about OpenSky's own renderer.

## Setup

Run once per machine. Each step is skipped when its result is already there, so a rerun
continues where the last one stopped.

1. Install Rosetta 2. It needs an administrator password:
   `softwareupdate --install-rosetta --agree-to-license`.
2. Run `make reference-setup PREFIX=<folder>`. Pick a folder on the same APFS volume as the
   game, outside the repo and outside the install, so the clone is instant. `GAME=<install>`
   overrides the `OpenSkyDataRoot` setting as the copy's source. The script:
   1. downloads Wine 11.0 and checks its SHA-256;
   2. downloads soju's web helper wrapper, DXVK, and GStreamer, and checks each SHA-256;
   3. creates the prefix, sets Windows 10, and writes the DLL overrides above;
   4. installs Windows Steam and starts it once, so it downloads its client;
   5. clones the game and its `appmanifest_489830.acf` into the prefix's Steam library, and
      copies DXVK's DLLs into the copy's game folder;
   6. stores the folder as the `OpenSkyReferencePrefix` setting.
3. Run `make reference-game`. Log in to Steam once in the window that opens. Steam does not
   start an out-of-date game, so it updates the copy to the current build first. In the
   game's Steam properties, set updates to "Only update this game when I launch it".
4. Run `make reference-check`. It compares the Steam `buildid` of both installs and the
   SHA-256 of every `.esm`, and names each difference.

The setting has an environment override, `OPENSKY_REFERENCE_PREFIX`. The Wine binary is
found the same way: `OPENSKY_REFERENCE_WINE`, then `OpenSkyReferenceWine`, then
`opensky-runtime/wine/bin/wine` in the prefix. The Settings page shows the prefix with
"Show details" on.

## Launching

`make reference-game` (`openskycli reference launch`) and the launcher's Start buttons do
four things:

1. They write `bBorderless=1`, `bFull Screen=0`, `iSize W`, and `iSize H` into the
   prefix's `SkyrimPrefs.ini`, starting from the game's `High.ini` preset when the game has
   not written the file yet. Without these keys the game window does not match the capture
   size. The default is 1280 x 720; `ARGS='--width 1920 --height 1080'` changes it. Wine
   opens the window at the top left and ignores `iLocation X` and `iLocation Y`. The CLI
   applies the game's Low preset first, so both games fit on one GPU;
   `ARGS='--preset high'` picks another. They also
   set `bAlwaysActive=1` in `[General]` of `Skyrim.ini`, so the game keeps running while
   another app is in front. Without it the game pauses on alt-tab, and the bridge pauses
   with it. The game ignores the key in `SkyrimPrefs.ini` (observed 2026-10-29).
2. Unless a `steam.exe` already runs, it deletes the browser lock files and swaps in the
   web helper wrapper.
3. It starts Windows Steam with the flags above, and waits `--steam-wait` seconds for the
   login.
4. It starts `SkyrimSE.exe` from its own folder with the Steam app IDs and the GStreamer
   paths set, so Steam does not open the game's launcher window.

The environment turns off the Metal HUD (`MTL_HUD_ENABLED=0`), because it changes the
captured image. Wine's output goes to `.logs/reference-game/<UTC time>/`, or, from the
launcher, to `~/Library/Application Support/OpenSky/Reference/Wine/<UTC time>/`.

## Side by side from the launcher

The Reference Game page needs no terminal once a prefix exists. Choose Prefix picks one
that `make reference-setup` built.

- **Start Both** splits the main screen. The Windows game opens borderless on the right
  half, and OpenSky's Play window on the left half, both with a 16:9 picture of the same
  size and their tops in line. OpenSky starts the way the Launch page's Play button would.
  Wine ignores the window place in `SkyrimPrefs.ini`, so once the game window is on screen
  OpenSky moves it through the Accessibility API. Wine places the window again while the
  game sets up its display, so OpenSky repeats the move until the window has stayed in
  place for 5 seconds. The move needs the Accessibility permission for OpenSky. Those
  coordinates start at the top left of the main screen, in points, so the page converts
  AppKit's bottom-left frame.
- **Low graphics in both games** is on by default, because the two games share one GPU.
  It sets OpenSky's Graphics preset to Low, and sets every key of the game's `Low.ini` in
  the prefix's `SkyrimPrefs.ini`. Both stay set afterwards; the Graphics page changes
  OpenSky back.
- **Both games load this Windows save** makes Start Both start from one save, chosen in
  the Save pop-up, newest first. OpenSky imports the `.ess` from the prefix's `Saves/`
  folder. With the bridge installed, the Windows game loads it from its main menu; without
  it, choose Continue there for the newest save.
- **Start Windows Game** starts only the Windows game, at the default size.

The launcher hides while OpenSky's game window is open, so the Game menu holds the actions
that need a running game. Each result shows as the game window's subtitle.

| Game menu item | Keys | What it does |
| --- | --- | --- |
| Send View to Windows Game | Shift-Cmd-E | Moves the Windows game to OpenSky's view through the bridge; without it, writes the batch file for `bat opensky` |
| Follow Windows Game | Shift-Cmd-F | Moves OpenSky to the Windows game's view through the bridge |
| Capture Both Games | Shift-Cmd-K | Writes a comparison run |

## The bridge plugin

OpenSky does not type into the Windows game's console, because Wine drops and misroutes
the keys ([the decision](/decisions/reference-bridge.md) lists what was observed). The
`OpenSkyBridge` SKSE plugin runs inside the game instead: it runs the console commands
OpenSky sends and reports the player's state. It changes no game rule and draws nothing.

Install it once per prefix. SKSE and the Address Library are only on Nexus, so download
both first: SKSE's build for the game's version (mod 30379) and the Address Library's
"All in one (Anniversary Edition)" (mod 32444). Then run:

```sh
make reference-bridge SKSE=<skse archive> ADDRESS_LIBRARY=<address library archive>
```

It copies SKSE's loader and DLL and the `versionlib-*.bin` files into the game copy,
installs Homebrew's `llvm@22`, `lld@22`, and `xwin`, downloads the Windows SDK with xwin,
and builds `Data/SKSE/Plugins/OpenSkyBridge.dll`. A later run only rebuilds the plugin.
Once `skse64_loader.exe` is in the game copy, every start goes through it.

| Command | What it does |
| --- | --- |
| `openskycli reference state` | Prints the game's state: place, angles, hour, weather, field of view |
| `openskycli reference send <command>...` | Runs console commands, one per argument |
| `openskycli reference sync` | Puts the Windows game at the running OpenSky's view |
| `openskycli reference follow` | Puts the running OpenSky at the Windows game's view, through `game debug view` |
| `openskycli reference load [<save>]` | Waits for the main menu, then loads the save, by default the newest |
| `openskycli reference answer <button>` | Presses a button of the open message box, by index from 0 or by text |

The launcher's Send View and Follow Windows Game buttons do the same as `sync` and
`follow`. Sync runs the `cow` or `coc` line alone, waits until the state names the new
cell, then runs the rest, because a cell change puts the player at the cell's own marker.
The state names the new cell before its load starts, and the load stops the plugin for a
few seconds, so sync checks the feet a second later and runs the rest again if the load
undid it, up to three times. It leaves out `tm`, which would show the HUD again on every
second send.

The bridge and OpenSky share `OpenSkyBridge/` in the game copy's folder:
`commands/<name>.txt` holds one batch of console lines, and `state.json` holds the game's
state, rewritten four times a second. While a message box is open, such as the Survival
Mode question after loading an old save, `state.json` holds its text and buttons under
`dialog`, and `answer` presses one. `send 'save <name>'` saves into the prefix's
`Saves/` folder. The plugin runs its work on SKSE's UI task queue,
because the game's main task queue stops while a message box pauses the game.
`state.json` reports the console's angles: positive `pitchDegrees` looks down, and
`headingDegrees` is 0 at north and turns clockwise.

## Same view, two games

Put both games in first person first. The console has no command for the camera mode.

Without the bridge, from OpenSky to the reference game:

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

From the reference game to OpenSky without the bridge: save there, then use Import Newest Save
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

The reference window is the normal window of the size the game was started with, whose
owner name holds "wine" or "skyrim"; without such a window it is the biggest one. The
capture needs the Screen Recording permission for the terminal, or for OpenSky when the
Game menu or the Reference Game page captures; OpenSky asks for it on the first capture.
Those write the same files to
`~/Library/Application Support/OpenSky/Reference/Captures/<UTC time>/`, because the app
has no checkout. The batch file is not copied into the game folder there; Export View does
that.

The Reference Game page shows the newest run: side by side, Flip (one image at full width;
press it again to swap the games), and Difference. PSNR is only a rough signal between two
engines: different noise, shadow filtering, or a cloud a few pixels off lowers it as much as
a real bug.

## Caveats

- The recipe depends on one Wine build (Gcenx `wine-stable-11.0_1`), whose GStreamer link
  needs GStreamer 1.28, and on a DXVK build from 2023. A DXMT release with the fix for
  issue #231 would give a Metal path without Vulkan.
- DXVK's output is close to Windows, not identical. Check a rendering difference against a
  Windows screenshot before filing it as an OpenSky bug.
- Metal GPU captures of the reference game would show its passes and render targets. They
  need the owner's decision first. Translated shaders could be read for structure only; their
  code never goes into OpenSky.
