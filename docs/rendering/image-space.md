---
type: Subsystem
title: Image space pass
description: How OpenSky turns the resolved image space and running modifiers into a
  post-process pass, and how to check it.
tags: [rendering, image-space, weather]
---

# Image space pass

The image space pass is the last full-screen pass of a frame. It applies the color grade of
the current place: saturation, brightness, contrast, tint, and fade. The record layout is in
[image space records](/formats/image-spaces.md); this page covers the runtime.

## Data flow

1. The weather system or the interior cell names a baseline `IMGS` each frame, as section
   "Resolution" of the format page explains.
2. Spells, explosions, and the panel start `IMAD` modifiers. Each one runs for its playback
   time, then ends; a looping one runs until it is stopped.
3. The pass reads the baseline with every modifier applied, clamps the values to a range the
   shader can show, and draws. A neutral result skips the pass, so a frame without an image
   space costs nothing.

At most 16 modifiers run at once. The oldest goes first. This is OpenSky's own limit.

## Triggers

| Source | Strength |
| --- | --- |
| A spell hit on the player | 1, from the `MGEF` image-space modifier |
| An explosion | 1 at the center, falling linearly to 0 at the `EXPL` image-space radius, measured to the camera; a zero radius plays at 1 |
| The Effects panel | The panel's strength slider |

A spell hit on another actor starts no modifier, because the modifier describes what the
player sees.

## Where OpenSky differs

- HDR values (bloom, eye adaptation, white point) are decoded and blended but not drawn.
  The renderer has no HDR tone-mapping stage yet.
- Depth of field, radial blur, and motion blur are decoded but not drawn. The blur radius
  is a 12-tap disc blur, and double vision is one ghost image offset to the side.
- The tint mixes the color toward its own brightness times the tint color, by the tint
  amount. The fade mixes toward the fade color by its alpha. The game's exact math is not
  documented, so these are approximations.

## Checking it in the app

`World > Effects > Image Space` holds the pass toggle (`ImageSpacePassControl`), a forced
baseline picker (`ImageSpaceForcedControl`), a modifier picker with a strength slider and a
play button, and the live values (`ImageSpaceStatsLabel`). The `effects` CLI command prints
the same values for a cell (see [CLI](/tools/cli.md)).
