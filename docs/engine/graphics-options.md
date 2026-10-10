---
type: Subsystem
title: Graphics options
description: The launcher's Graphics page - the base game's preset files, which options
  OpenSky applies, the texture memory rule, and where each value lives.
tags: [engine, settings, graphics, launcher]
---

# Graphics options

The Graphics page shows the options of the base game first, then OpenSky's own GPU
features. Every value lives in the player settings file, which the game reads when it
starts. OpenSky never writes an INI file ([INI settings](/formats/ini.md)).

## Where the options come from

The list is every key that the install's `Low.ini`, `Medium.ini`, `High.ini`, and `Ultra.ini`
set, read from the install root of Skyrim SE 1.6.1170 on 2026-10-09: 35 keys, in the
sections `Display`, `TerrainManager`, `LOD`, `Grass`, `General`, `ImageSpace`, and `Decals`.
The key meanings follow the UESP wiki's Skyrim INI settings pages. The values are read at
runtime and are never copied into the repository or a test fixture.

- A key whose name starts with `b` is a switch; the others are numbers.
- The default of an option is its value in the layered INI files of the install, so a
  player's own `SkyrimPrefs.ini` shows through. Without an install the default is OpenSky's
  safe terrain fallback, or 0.
- A preset sets every key its file has, and it sets the texture quality on the Asset
  Optimisation page: Ultra keeps the original textures, High, Medium, and Low pick the
  quality of the same name ([asset cache](/engine/asset-cache.md), "Texture quality").
- When the settings match no preset file, the preset menu reads Custom.

## What OpenSky applies

OpenSky applies the four terrain distances today: `fBlockLevel0Distance`,
`fBlockLevel1Distance`, `fBlockMaximumDistance`, and `fTreeLoadDistance`. They feed the
distant terrain the same way the INI keys do, and the terrain LOD override of the developer
sidebar still wins over them.

Every other option is shown, saved, and disabled, with one line that says why it does
nothing yet, such as "OpenSky draws no decals yet". So a player sees what the game would
change, and an option that starts to work only needs its reason removed.

## OpenSky's own groups

- Upscaling: render scale, the MetalFX upscaler, and frame interpolation.
- Rendering: ray-traced sun shadows, mesh shader grass, GPU culling, shallow water depth,
  and the [pipeline cache](/rendering/pipeline-cache.md).
- Texture memory: "Full detail only near the camera" is
  [texture streaming](/rendering/texture-streaming.md), and "Memory for close-up detail" is
  its budget. Automatic follows this Mac's GPU memory.
- Window: full screen for Play, and a frame rate cap of 30, 60, or 120 frames a second. The
  cap holds the live frame pacing to the chosen rate; Off follows the display.

## Command line

`openskycli graphics status` prints the matching preset and each option.
`openskycli graphics preset <name>` writes a preset into the settings file, so a benchmark
run can compare presets without the app ([CLI](/tools/cli.md)).
