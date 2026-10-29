---
type: Tool
title: Launcher and game window
description: How the app's own interface is built - the launcher, its pages, the game window,
  the theme, and the accessibility id contract.
tags: [tool, gui, ui, launcher]
---

# Launcher and game window

This page covers the app's own interface: the launcher and the window the game runs in. It is
not the in-game UI, which is vanilla SWF movies ([SWF layer](/rendering/swf-layer.md)). The
code is in `Sources/OpenSky/Launcher/` and `Sources/OpenSky/Shell/`.

A behaviour a user must check while the game runs is reached through `openskycli game`
([driving the game](/tools/cli.md)), not through app panels.

## Launcher

The app opens on the launcher. The launcher holds:

- The Play button. It opens the game in its own window. Play needs a valid game folder and a
  valid start.
- A page list on the left: Launch, Asset Optimisation, Graphics, Diagnostics, and Settings.
  Settings is the same view as the Cmd+, window. Under the list, the "Show details" switch
  shows or hides the technical notes and developer settings on every page at once, and in
  the Cmd+, window too.
  - Launch puts Play first, with one line that says what Play will do. Launch options hold
    "Resume latest save", "Skip main menu", and "Full screen"; New game holds where a new
    game starts and the Survival Mode choice. Game files shows the game folder and only the
    asset optimisation state; each row opens Settings or the Asset Optimisation page.
  - Settings holds the game folder, the install check, plugins.txt, the string-table
    language, the Skyrim saves folder, and, under "Show details", the
    [agent control](/tools/agent-control.md) switch and the reference game prefix. The
    game folder is a load setting, so it sits with the others and not on the page a
    player starts from.
  - Asset Optimisation picks the texture quality, the folder, and direct GPU loading, and
    converts, checks, and clears the [asset cache](/engine/asset-cache.md). Its rules live in
    `AssetCacheCoordinator` in `OpenSkyLoading`, shared by the pages through `LauncherContext`.
  - Graphics holds a preset, the base game's options, and the GPU features, such as the
    [pipeline cache](/rendering/pipeline-cache.md) and
    [texture streaming](/rendering/texture-streaming.md)
    ([graphics options](/engine/graphics-options.md)). It writes the player settings file,
    which the game reads when it starts.
  - Benchmark picks the tour length and runs the [benchmark tour](/tools/benchmark.md) in the
    Play window, then shows the newest result as a chart and its summary.
  - Reference Game starts OpenSky and the Windows game side by side, from one save if asked,
    exports OpenSky's view to it, captures both, imports its newest save, and
    shows the newest comparison pair ([reference game](/tools/reference-game.md)).
  - Diagnostics opens the logs folder, copies a system report with the newest benchmark result,
    and opens the Benchmark page.

The rules live in `OpenSkyLaunch`, a package module, so they are tested without AppKit:
`LaunchStart`, `LaunchPlan`, `LaunchPreferences`, and `GameFolderStatus`. The app only draws them.

To add a page, such as a mods list, add one descriptor to `LauncherRegistry.pages`. Put the
page's rules in its own package module, not in the view controller.

A launcher page is built with `LauncherPageLayout`: a title, an optional status line
(`LauncherStatusView`) with a symbol, a word, and one line of detail, then titled groups. A
row that only a curious player needs is wrapped in `layout.detail(_:)`, and the "Show
details" switch at the top of every page shows those rows. The switch is one setting for all
pages, so the launcher stays short by default.

The launcher looks like the SkyUI mod configuration menu, so it feels like part of Skyrim:
black panels, uppercase condensed headings over a thin rule, white and grey text, and flat
outlined buttons. A setting is a `LauncherRow`: its name on the left, its control on the right,
and a band under the pointer. A click anywhere on the row acts on the control. Every heading,
row title, and readout starts at the same left edge (`LauncherStyle.textInset`). The drawing is
original; the face is the Futura Condensed that ships with macOS, so nothing comes from SkyUI
or the game. `LauncherStyle` holds the colours and fonts.

The page area never gets narrower than `LauncherPageLayout.minimumPageWidth`, the page width
plus both margins. The split view enforces it, so the window cannot shrink until a control
clips. The standard split divider stays: an `NSSplitView` subclass set on the split view
controller crashes AppKit with an index error when the controller first lays out.

Play first loads the world data off the main actor. While it runs, the launch page shows a
load panel instead of the Play button: a progress bar, the stages that run now, one row per
stage with its time, and Cancel. The game window opens when the load ends. A settings
change reloads the same way, and the new game view replaces the old one after the load.

Closing the game window, or `Game > Return to Launcher`, ends the game and shows the launcher
again. Closing the launcher quits the app. The launcher hides while the game window is open,
so the Game menu holds the Reference Game page's actions that need a running game, such as
`Game > Capture Both Games`, and shows their result as the window's subtitle.

Set `OPENSKY_SKIP_LAUNCHER` to `1` to skip the launcher and open the game. The load still
runs, without the load panel. The UI tests and `openskycli game launch` set it.

## Theme

The app has a fixed dark design inspired by Skyrim. All tokens are in
`Sources/OpenSky/Shell/Theme.swift`, and the app forces dark appearance, so system controls
match. Take every color and heading font from `Theme`: surfaces, parchment ink, gold accent (also
the asset catalog `AccentColor`), and dividers. Headings are uppercase and tracked in Futura
Condensed Medium, which macOS ships, with a system fallback. Nothing is bundled, so the fallback
must work. No Bethesda fonts, art, or UI assets: the look comes from color and type only.

## Accessibility id contract

Accessibility ids are the UI test API and never change silently.

| Element | Id |
| --- | --- |
| Control and readout | `<Thing>Control` and `<Thing>StatsLabel` |
| Launcher | `LauncherSidebar`, `LauncherPage-<id>` rows, `LaunchPlayControl`, `ReturnToLauncherCommand` |
| Launcher Asset Optimisation page | `AssetOptimisation<Thing>Control` and `AssetOptimisation<Thing>StatsLabel`, `AssetOptimisationProgressIndicator` |
| Launcher Graphics page | `Graphics<Thing>Control`, `GraphicsOption<key>Control`, and `GraphicsStatsLabel` |
| Launcher Benchmark page | `Benchmark<Thing>Control`, `BenchmarkPresetStatsLabel`, `BenchmarkResultStatsLabel`, `BenchmarkChart` |
| Launcher Diagnostics page | `Diagnostics<Thing>Control` and `Diagnostics<Thing>StatsLabel` |
| Launcher Reference Game page | `Reference<Thing>Control`, `Reference<Thing>StatsLabel`, `ReferenceFirstImage`, `ReferenceSecondImage` |
| Launcher details and status | `LauncherShowDetailsControl`, `<Name>StatusStatsLabel` |
| Launcher load panel | `LauncherLoadProgressIndicator`, `LauncherLoadStatusStatsLabel`, `LauncherLoadStageList`, `LauncherLoadStage-<stage>` rows, `LauncherCancelLoadControl` |
| Benchmark overlay | `BenchmarkOverlay`, `BenchmarkOverlayLabel` |
| Benchmark toolbar | `BenchmarkOverlayButton`, `BenchmarkStopButton` (window chrome, the one exception to the suffix rule) |

The ids are pinned as literal assertions in the launcher tests and `OpenSkyUITests`. Update
those literals in the same change that renames an id.
