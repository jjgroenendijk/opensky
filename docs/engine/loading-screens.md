---
type: Subsystem
title: Loading screens
description: How a loading screen covers a door transition, when it is picked, how long it
  holds, and how it is drawn.
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

In the game, the screen holds as long as the load takes. OpenSky builds a cell much faster,
so without a minimum the screen would flash for one frame and the tip could not be read. The
1.5 seconds and the 0.4-second fade are OpenSky's choice.

## Drawing

- The cover is its own render layer. While it shows, the renderer draws only the cover: the
  screen's `STAT` model, placed in front of the camera. The world, the player body, and the
  first-person arms are not drawn.
- The object starts at the `RNAM` rotation, `SNAM` scale, and `XNAM` offset. It turns around
  its up axis, back and forth across the `ONAM` range, at 6 degrees per second. A screen with
  no range does not turn.
- The camera distance is 2.5 times the model's radius times its scale, and at least 48 units,
  so the whole object fits on screen. `XNAM` moves the object to the right, forward, and up
  from that point. The game's camera placement is not known; this is OpenSky's.
- The tip, the `DESC` text, is drawn at the bottom in the UI overlay.
- During the fade, the world draws again under a black panel whose opacity falls to zero.
- A screen with no model shows the tip on black.

## Differences from the game

- Only doors show loading screens. Fast travel and loading a save do not yet.
- The `MOD2` camera path file is not read.
- The tip text comes from the `Skyrim.esm` string tables only, so a DLC screen may show the
  wrong text or none.

The `World > Loading Screens` panel can force a screen to stay on, release it, turn loading
screens off, and list the screens whose conditions pass where the player stands.
