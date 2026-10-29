---
type: Decision
title: The reference game's bridge plugin
description: Why OpenSky drives the Windows reference game through an SKSE plugin built on
  CommonLibSSE-NG, how it is built on a Mac, and why its GPL dependency and its use of the
  game's class names are allowed in this one developer tool.
tags: [decision, reference, dependency, licensing, skse, clean-room]
---

# The reference game's bridge plugin

OpenSky drives the Windows reference game through `OpenSkyBridge`, a small SKSE plugin
in `reference/bridge/`. It runs console commands that OpenSky sends and reports the
player's place, view, hour, and weather. [Reference game](/tools/reference-game.md) shows
how to use it.

## Why a plugin

Typing into the game's console through Wine does not work reliably (observed
2026-10-26): Wine drops keys while the game is not the front app, Return does not reach
the console with `bAlwaysActive=1`, Return at the main menu opens a dialog and hangs the
game, `sStartingConsoleCommand` does nothing, and the console key depends on the keyboard
layout. Reading the game's state back needed a save and an import.

A plugin inside the game avoids all of these. It needs no Accessibility permission and no
focus change, and it works in both directions.

## Dependencies

| Part | Licence | Where it comes from | Where it goes |
| --- | --- | --- | --- |
| SKSE64 2.3.1 | Its authors' terms; never redistributed | The user downloads it from Nexus | The prefix's game copy |
| Address Library | Its author's terms; never redistributed | The user downloads it from Nexus | The prefix's game copy |
| CommonLibSSE-NG 15.0.1, prebuilt for clang-cl | GPL-3.0-or-later with a modding exception | Its GitHub release, pinned by SHA-256 | The prefix's build folder |
| spdlog 1.17.0, fmt 12.2.0 | MIT | GitHub, pinned by SHA-256 | The prefix's build folder |
| DirectXMath, DirectXTK headers | MIT | GitHub, pinned by SHA-256 | The prefix's build folder |
| Windows SDK and MSVC headers | Microsoft's licence | `xwin`, which accepts it | The prefix's runtime folder |
| clang-cl 22.1, lld-link | Apache-2.0 with LLVM exception | Homebrew `llvm@22`, `lld@22` | Homebrew |

Nothing of these enters the repo, and no release builds or ships the plugin.

- **The GPL.** CommonLibSSE-NG changed from MIT to GPL-3.0-or-later in 2026 (its
  `README.md`, section License). A plugin that links it must use a GPL-compatible
  licence. The plugin source is Apache-2.0, like the rest of the repo, which the GPL-3.0
  accepts. The built DLL is a GPL work, but it is never distributed: each developer builds
  it into their own prefix.
- **Versions.** The prebuilt library must be linked with the same compiler family and
  version, clang-cl 22.1, and with the library versions it was built with. Those come from
  the vcpkg baseline in its `vcpkg-configuration.json`, not from its `vcpkg.json`: an older
  fmt leaves `fmt::v12::detail::allocate` unresolved. Its objects also call STL helpers
  such as `__std_replace_copy_2` that only the Visual Studio 2026 toolset (xwin manifest
  18, MSVC 14.51) has.
- **Wine's C++ runtime.** Wine's own `msvcp140.dll` does not export `__crtLCMapStringA`,
  which MSVC's static regex helpers call. The plugin defines it, forwarding to
  `LCMapStringA`, so the DLL needs no native Microsoft runtime in the prefix.
- **SKSE and the Address Library** are only on Nexus, which needs a login (observed
  2026-10-28), so setup takes the archives the user downloaded. Only SKSE's loader and DLL
  are installed, not its scripts, so the game's own scripts stay vanilla.

## The clean-room boundary

The `using-outside-sources` skill puts CommonLibSSE in Tier 2: OpenSky's engine code never
takes its names or layouts. The bridge is an exception that the owner approved on
2026-10-28, because it runs inside the game's own process by design:

- The plugin may call CommonLibSSE-NG's public API by name. Its source stays in
  `reference/bridge/`, which no release builds.
- The plugin copies no code from CommonLibSSE-NG or SKSE. It uses the library as a
  dependency.
- OpenSky's Swift code sees only the bridge's JSON state: place, angles, cell, hour,
  weather, and field of view. Those are interop facts the console already shows.

## The channel

OpenSky and the plugin share one folder, `OpenSkyBridge/` beside `SkyrimSE.exe`. A file
needs no network permission, works the same under Wine, and can be read by hand.

- OpenSky writes each batch of console lines to `commands/<name>.tmp` and renames it to
  `<name>.txt`, so the plugin never reads half a file. Names sort by time.
- The plugin polls the folder every 0.25 s, runs each batch on the game's main thread
  through SKSE's UI task queue, and deletes it. SKSE's main task queue stops while a menu
  pauses the game, such as the Survival Mode question after a load (observed 2026-10-29).
  The UI task queue keeps running then.
- On the main thread, the plugin writes `state.json` four times a second, also through a
  rename. Its `batch` field names the last batch that ran, so OpenSky knows when a batch
  is done. A file older than 3 s means no game runs.
- `load <save>` goes to the game's save manager rather than the console, so it works at
  the main menu.
- `answer <index>` presses that button of the open message box. `state.json` lists the
  box's text and buttons under `dialog`, so no message box can hold the game.
- `save <name>` goes to the save manager through the main task queue. A save started
  from the UI task queue wrote an empty `.ess.tmp` and stopped the game (observed
  2026-10-29).
