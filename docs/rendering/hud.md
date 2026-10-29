---
type: Subsystem
title: Gameplay HUD
description: How the vanilla hudmenu.swf becomes the gameplay HUD - the observed engine-to-movie
  functions and argument shapes, compass heading mapping, authored placeholder clips, who owns the
  single SWF layer.
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

## HUD modes

The movie hides and shows its parts by HUD mode. `/HUDMovieBaseInstance.HudElements` lists the
elements, and each element has a `true` field for every mode it shows in, such as `All`,
`StealthMode`, or `CartMode`. `ShowElements(mode, show)` on `/HUDMovieBaseInstance` puts a mode on
the movie's mode stack when `show` is true, and takes it off when `show` is false. An element
shows only when the top mode is one of its modes. After `StealthMode` and then `CartMode` are put
on, taking off `StealthMode` leaves `CartMode` on top. These facts were observed by probing the
installed movie with `openskycli swf movie-probe`.

The movie names 14 modes. OpenSky drives the six that follow the player and the scripts, bottom
first:

| Mode | When OpenSky puts it on | What it hides of the base mode |
| --- | --- | --- |
| `HorseMode` | The player rides a horse | Stamina meter, crosshair, item info, arrow info, stealth meter |
| `WarHorseMode` | The player rides a horse with a weapon drawn | Item info, stealth meter |
| `Swimming` | The player swims | Stealth meter |
| `StealthMode` | The player sneaks | Crosshair |
| `CartMode` | `Game.SetHudCartMode` | All but messages, subtitles, and tutorial hints |
| `MovementDisabled` | `DisablePlayerControls` turned movement off | As `CartMode`, but quest updates stay |

"Item info" is the activate button, the item name and info, and the gray bar between them. Only
one of the first four is on at a time, in the order of the table. `MovementDisabled` sits above
`CartMode`: the Creation Kit wiki notes that disabling movement during cart mode loses cart mode
until movement comes back ([SetHudCartMode](https://ck.uesp.net/wiki/SetHudCartMode_-_Game)).
[WARNING] The game's rule for `WarHorseMode` is not documented. OpenSky infers it from the
elements: `WarHorseMode` keeps the arrow info and one of the two charge meters, which only
mounted combat needs.

OpenSky takes every shown mode off and puts the new stack on whenever the stack changes, so the
movie's stack always matches. The movie's own setters, such as `SetCompassAngle` and
`SetCrosshairTarget`, do not show a part that a mode hides. OpenSky's own switches write
`_visible` on the meters, the enemy health bar, the item info, and the subtitle holder, the same
property the modes write. So after each mode change OpenSky applies them again, and it never shows
one of them while the top mode hides it. A HUD movie that starts again, such as after a menu, gets
the modes again.

`openskycli game debug cartmode on|off` sets cart mode. `state menu` shows `hud.cartMode` and the
stack as `hud.modes`.

## Timing

HUD changes are collected and applied once between frames. A target change only marks the prompt
and marker dirty, and the frame hook changes the renderer. The HUD timeline is not ticked at the
display rate: the direct functions set the state it needs, and one AS2 tick per 60 or 120 Hz frame
would make behavior depend on the monitor. Timed HUD animation needs its own movie frame rate.

## Who owns the SWF layer

There is one SWF layer, and the HUD owns it by default. The system menu's vanilla movie takes it:
it shows `quest_journal.swf` on its System page while the menu is open, and brings the HUD back on
Resume ([system menu](/engine/system-menu.md)).

## Where OpenSky differs

- The movie's `Favor` mode, for follower command mode, and its menu modes (`DialogueMode`,
  `BarterMode`, `InventoryMode`, `BookMode`, `TweenMode`, and `WorldMapMode`) are not driven.
  OpenSky has no follower command mode yet, and a menu takes the one SWF layer, so the HUD is not
  drawn under a menu at all.
