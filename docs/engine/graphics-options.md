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

Each row is an option OpenSky applies, and how. A preset file sets most of them, and the
player's own `SkyrimPrefs.ini` shows through as the default.

| Option | How OpenSky applies it |
| --- | --- |
| `fBlockLevel0Distance`, `fBlockLevel1Distance`, `fBlockMaximumDistance`, `fTreeLoadDistance` | The terrain and tree LOD distances ([terrain](/engine/terrain.md)) |
| `uGridsToLoad` | The side of the full-detail cell grid ([cell streaming](/engine/cell-streaming.md#the-desired-grid)). No preset sets it, so a preset leaves it unchanged |
| `fSplitDistanceMult` | Scales the distances where terrain and object LOD blocks split into the finer levels 4, 8, and 16. The level 32 reach stays at `fBlockMaximumDistance`. 0 keeps 1 |
| `bDecals`, `uMaxDecals`, `iMaxDecalsPerFrame` | Decals on, the most decals kept, and the most placed in one frame; the rest of that frame's decals are dropped ([impacts and decals](/rendering/decals.md)) |
| `fShadowDistance` | The far end of the last sun shadow cascade. 0 keeps OpenSky's 12288 units. The low shadow quality caps it at 8192 |
| `iShadowMapResolution` | The width and height of each cascade slice: a power of two from 512 to 4096. A change builds a new map while the game runs |
| `iNumFocusShadow` | Up to 4 actors nearest the camera get a sharp sun-shadow map of their own ([shadows](/rendering/shadows.md#focus-shadows)). 0 draws none |
| `bUsePrecipitationOcclusion` | A top-down depth view around the camera hides each rain or snow drop under a roof ([precipitation](/rendering/precipitation.md#roof-occlusion)). Off lets rain fall through roofs |
| `bToggleSparkles` | The glint of sparkle-snow shapes (shader type 14) ([surface shading](/rendering/surface-shading.md)). Both it and the "Snow and ice sparkle" switch must be on |
| `fLODFadeOutMultActors`, `fLODFadeOutMultItems`, `fLODFadeOutMultObjects` | A placed reference is drawn up to multiplier x 16 x its bound radius (at least 32) from the camera, and dissolves over the last 15% of that reach. Actors use the actor value, references a rigid body moves the item value, other statics the object value. A faded reference casts no shadow. 0 never fades |
| `fGrassStartFadeDistance` | Grass starts to thin out at this distance, and is gone at the distance / 0.7, inside 512 to 16384 units. 0 keeps OpenSky's 8192-unit grass reach |
| `fMeshLODLevel1FadeDist`, `fMeshLODLevel2FadeDist` | Past each distance from the camera, a `BSLODTriShape` instance draws its next coarser level ([NIF](/formats/nif.md#nitrishape)). Such meshes stay on the CPU cull path, which writes the instances grouped by level. Shadows keep full detail. 0 never switches |
| `bSAOEnable` | Screen-space ambient occlusion in the image-space composite ([post effects](/rendering/post-effects.md#ambient-occlusion)) |
| `bVolumetricLightingEnable`, `iVolumetricLightingQuality` | Sun shafts from a march through the sun cascades; quality 0, 1, or 2 takes 8, 16, or 32 steps ([post effects](/rendering/post-effects.md#volumetric-light)) |
| `bDoDepthOfField` | Blurs what lies past the image space's `DNAM` focus distance ([post effects](/rendering/post-effects.md#depth-of-field)) |
| `bLensFlare` | Ghost discs from the sun while it is in view and not hidden ([post effects](/rendering/post-effects.md#lens-flare)) |
| `bFXAAEnabled` | FXAA smooths edges in the image-space composite ([post effects](/rendering/post-effects.md#fxaa)) |

An option that is not in this table is shown, saved, and disabled, with one line that says why it
does nothing yet. So a player sees what the game would change, and an option that starts to work
only needs its reason removed.

## OpenSky's own groups

- Upscaling: render scale, the MetalFX upscaler, and frame interpolation.
- Rendering: ray-traced sun shadows, mesh shader grass, GPU culling, shallow water depth,
  [terrain normal maps](/engine/terrain.md), impact effects,
  [HDR tone mapping](/rendering/image-space.md), and the
  [pipeline cache](/rendering/pipeline-cache.md).
- Texture memory: "Full detail only near the camera" is
  [texture streaming](/rendering/texture-streaming.md), and "Memory for close-up detail" is
  its budget. Automatic follows this Mac's GPU memory.
- Window: a frame rate cap of 30, 60, or 120 frames a second. The cap holds the live frame
  pacing to the chosen rate; Off follows the display. Full screen is on the Launch page.

## Command line

`openskycli graphics status` prints the matching preset and each option.
`openskycli graphics preset <name>` writes a preset into the settings file, so a benchmark
run can compare presets without the app ([CLI](/tools/cli.md)).
