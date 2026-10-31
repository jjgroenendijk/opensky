---
type: Subsystem
title: Loading screens
description: How a loading screen covers a door transition, a fast travel, or a load, when
  it is picked, how long it holds, and how it is drawn.
tags: [engine, ui, streaming]
---

# Loading screens

A door to another cell replaces the whole scene. While the new cell builds, the game shows a
loading screen: a slowly turning object on a dark background, with a tip below it. The record
and how a screen is picked are on the [loading screen records](/formats/loading-screens.md)
page.

## Timeline

1. A door transition starts. The view goes dark at once, and the world pauses. No screen is
   picked yet, because the destination's location is not known until its cell record is read.
2. The destination scene is ready. OpenSky picks a screen for the destination's `XLCN`
   location and shows it.
3. The screen holds for at least 1.5 seconds from that point. Then it fades out over 0.4
   seconds, and the world runs again.
4. A transition that fails keeps the old scene, so the cover lifts at once.

A fast travel works like a door. The view goes dark at once, because the destination's
location is known only when its cell is built. Then the screen is picked for that location,
and it holds until the near grid around the marker and its first distant ring are in, or
for at most 60 seconds.

Loading a save, Continue, a launcher start, and a script's `MoveTo` of the player to a
reference outside the loaded cells also show a screen. It is picked at once,
because the save's place is not read yet, and it holds until the player stands there.

A session that starts in the world, not at the title screen, also starts behind a loading
screen. It is picked at once and holds until the near grid and the first ring of
[distant LOD](/engine/distant-lod.md) are in, or for at most 60 seconds. So the world never opens
with bare sky past the grid edge. Then the same minimum and fade apply.

In the game, the screen holds as long as the load takes. OpenSky builds a cell much faster,
so without a minimum the screen would flash for one frame and the tip could not be read. The
1.5 seconds and the 0.4-second fade are OpenSky's choice.

## Drawing

- The cover is its own render layer. While it shows, the renderer draws only the cover: the
  screen's `STAT` model, placed in front of the camera. The world, the player body, and the
  first-person arms are not drawn.
- The object starts at the `RNAM` rotation, `SNAM` scale, and `XNAM` offset. It does not turn
  on its own. The player turns it with the mouse or the left and right keys, inside the
  `ONAM` range. A screen with no range does not turn. Source: CK wiki
  [LoadScreen](https://ck.uesp.net/wiki/LoadScreen), "Rotation Offset Constraints: how far
  the user can rotate the model".
- The camera distance is 2.5 times the model's radius times its scale, and at least 48 units,
  so the whole object fits on screen. The object sits on the view axis and tilts with the
  camera pitch, so it stays centered when the camera looks up or down. `XNAM` moves the
  object to the right, forward, and up of the view from that point. The game's base camera
  placement is not known; this is OpenSky's.
- The `MOD2` camera path moves the eye. Each of the five vanilla path meshes holds one
  `NiCamera` under a `CameraPathNode`, with 60 seconds of translation keys and no rotation.
  The keys start 250 to 300 units back for the four zoom paths, and 25 back and 35 up for
  `LSCameraPanDown01`, and they reach about zero at 30 seconds. At 25 units most models would
  not fit, so the keys cannot be the whole camera place, and how the game adds them to its
  base camera is not known. OpenSky moves the eye sideways and up by the keys, and back by
  the key's distance only where it is farther than the fit distance. So the zoom paths start
  farther out and close in to the fit distance, and the camera never reaches the object. The
  path plays from the moment the screen shows and loops over its 60 seconds. Measured with
  `openskycli nif 'meshes\Cameras\<name>.nif' --sequences`.
- The vanilla `XNAM` values fit this. Its forward part is 0 on every record, and its up part
  is about minus half the model's height, so a model whose origin is at its feet is centred
  on the view axis.
- The cover has its own light: a white light from above, behind the eye, and to the left,
  over a grey ambient, with no fog, so the loaded world's light, such as a dark blue night,
  does not tint it. The game's light is not documented, so these values are OpenSky's. The
  main menu logo brings its own light ([title menu](/engine/main-menu.md)).
- The HUD is hidden while the cover shows, and returns when the cover is gone.
- During the fade, the world draws again under a black panel whose opacity falls to zero.
- A screen with no model shows the tip on black.
- The cover stands on black and takes no weather fog, also when no cell is loaded behind it.

## The loading movie

The tip and the level meter come from the game's own movie, `interface\loadingmenu.swf`, so
the tip uses the game's font. It draws on the SWF overlay layer, and the HUD movie under it is
hidden. These facts were measured with `openskycli swf action-list --movie loadingmenu` and
`swf movie-probe`:

- The menu clip is `/Menu_mc`, class `LoadingMenu`. It holds `LoadingText` inside
  `LoadingTextFader`, and the level meter `LevelMeterRect`.
- `FadeInMenu` calls `GameDelegate.call("RequestPlayerInfo")` and
  `GameDelegate.call("RequestLoadingText", [], this, "SetLoadingText")`, then plays the root
  clip's `fadeIn` label. The text answer goes to `SetLoadingText(text)`. The fader clip calls
  `refreshLoadingText` again at the end of its own fade, so the movie asks for a tip more than
  once.
- `SetLevelProgress(level, percent, show)` writes the level number and fills the meter;
  `percent` runs from 0 to 100.
- `FadeOutMenu` plays the root clip's `fadeOut` label.

OpenSky answers `RequestLoadingText` with the screen's `DESC` text and calls
`SetLevelProgress` with the player's level after `FadeInMenu`. It calls `FadeOutMenu` when the
cover starts its fade. Until the movie is decoded, the tip shows in the UI overlay in the
system font.

## Checking it in the game

`openskycli game debug loadscreen <editor ID>` holds one screen, and
`debug loadscreen` with no ID releases it.
`openskycli game debug fasttravel <marker name>` travels as the map does. `state menu` shows
`loading`: whether the cover is up, the screen, its camera path, the player's turn, and
whether the loading movie is up.

## Differences from the game

- [WARNING] Not confirmed: `Skyrim.esm` has a `UILoadscreenMist` sound descriptor, which
  suggests the game plays a mist sound and draws mist behind the model. OpenSky does neither.
  This, the base camera, and the light wait for a reference capture.
- The tip text comes from the `Skyrim.esm` string tables only, so a DLC screen may show the
  wrong text or none.
