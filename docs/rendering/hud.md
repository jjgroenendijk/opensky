---
type: Subsystem
title: Gameplay HUD
description: How the vanilla hudmenu.swf becomes the gameplay HUD - the observed engine-to-movie
  functions and argument shapes, compass heading mapping, authored placeholder clips, who owns the
  single SWF layer, and the HUD & Interaction panel.
tags: [rendering, ui, swf, hud]
---

# Gameplay HUD

The gameplay HUD is the vanilla `Interface\hudmenu.swf`, loaded through the
[virtual file system](/formats/vfs.md) and run by the [AS2 runtime](/engine/as2-runtime.md) on the
[SWF layer](/rendering/swf-layer.md). Before it publishes any state, the engine checks that the
functions it needs exist on `/HUDMovieBaseInstance`. Missing game data, a missing function, or a
renderer failure leaves the HUD off and logs the reason. It never stops the 3D world from starting.

## The movie's functions

The public SWF format does not describe this GFx contract. The names and argument shapes below were
observed by probing the installed movie. It starts with 203 display nodes and no faults.

| Function | What the engine sends |
| --- | --- |
| `SetCrosshairEnabled` | Keeps the vanilla crosshair visible |
| `SetHealthMeterPercent`, `SetMagickaMeterPercent`, `SetStaminaMeterPercent` | A value clamped to 0 to 1. The movie keeps a value such as 0.75 |
| `SetCrosshairTarget` | The interaction prompt, such as `Open <door name>`, or an empty hidden target |
| `CompassTargetDataA` | Four numbers per marker: heading, Flash `_alpha`, the movie's own marker type value, and Flash scale |
| `SetCompassMarkers` | Applies that array |
| `SetCompassAngle` | The camera heading. Also keeps the compass visible |

The marker field order comes from the movie's own reader of `CompassTargetDataA`. Alpha and scale
use Flash's 0 to 100 property units. The meters are fed from the
[actor value store](/engine/actor-value-store.md#hud-bars), and the prompt and marker from
[interaction](/engine/interaction.md).

OpenSky maps world +X to heading zero and keeps headings in 0 up to 360. The player and compass angles
get the same camera yaw. A local visual check confirmed that heading zero centers the movie's north
marker, and that publishing a prompt does not move the compass.

## Authored placeholder clips

The installed movie starts with authoring samples visible under
`/HUDMovieBaseInstance/RolloverInfoInstance` and `/HUDMovieBaseInstance/SubtitleTextHolder`. Start-up
hides both, so raw font markup and `Dialogue Line 1Dialogue Line 2` do not show in play.

`/HUDMovieBaseInstance/GrayBarInstance` is the thin line between an item's name and its weight
and value, just below the crosshair. It is visible from the first frame too, so start-up hides it
with the item info until OpenSky publishes item info.

The subtitle holder is also used for real. Writing a line sets
`/HUDMovieBaseInstance/SubtitleTextHolder/textField` and shows the holder. Clearing the line hides the
holder, so no empty box is left ([dialogue menu](/engine/dialogue-menu.md)).

The meters are the clips `/HUDMovieBaseInstance/Health`, `Magica`, and `Stamina`, as spelled in the
movie. Hiding a meter hides its clip. Crosshair and compass visibility use the movie's own setters.

## Timing

HUD changes are collected and applied once between frames. A target change only marks the prompt
and marker dirty, and the frame hook changes the renderer. The HUD timeline is not ticked at the
display rate: the direct functions set the state it needs, and one AS2 tick per 60 or 120 Hz frame
would make behavior depend on the monitor. Timed HUD animation needs its own movie frame rate.

## Who owns the SWF layer

There is one SWF layer, and the HUD owns it by default. Two surfaces take it and give it back:

- Choosing a movie in `Developer > UI Lab > SWF movie` is a debug override. Choosing `None` brings
  the HUD back, with its saved element and scale settings.
- Turning on the vanilla movie in `World > System Menu` shows `quest_journal.swf` on its System
  page while the menu is open, and brings the HUD back on Resume
  ([system menu](/engine/system-menu.md)).

## HUD & Interaction panel

`World > HUD & Interaction` has two sections:

- **Elements** turns the layer, crosshair, meters, compass, marker, prompt, and the authored
  placeholder text on and off, and sets the scale to 50, 75, 100, 125, 150, or 200 percent. Scale is
  a centered presentation factor and does not change the display list. The readout shows the load
  state, scale, draw calls, and skipped items. Gameplay elements start on and placeholder text starts
  off.
- **Target** shows the current walk-mode reference and base form IDs, the action and name, the
  distance, the placed and hit positions, the exact prompt, the camera heading, and the marker
  headings. It has no synthetic preview on purpose, so a broken targeting or localization path shows
  as broken.

Captures of the HUD over a real cell contain game art, so they stay in `.logs/`.
