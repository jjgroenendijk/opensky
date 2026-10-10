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

Most grades read only the pixel they change. Those draw one fullscreen triangle inside the scene
pass, and the shader reads the pixel from tile memory, so the frame needs no copy and keeps its
depth [memoryless](/rendering/metal4-renderer.md). Blur and double vision read other pixels. For
them the scene pass ends, the color is copied, and a second pass grades the copy.

## HDR tone mapping

Tone mapping runs first in the grade, before saturation. It has two parts:

- **Eye adaptation.** Every 16th pixel in each direction adds its log2 luminance to two GPU
  counters per frame slot. When the slot comes round again, the CPU reads the mean and moves
  the eye towards it. The exposure is `(0.18 / eye) ^ (strength / (strength + 10))`, clamped
  to 0.25 to 4. So a dark cave gets brighter and a bright snowfield gets darker.
- **White point.** An extended Reinhard curve, `c * (1 + c / white²) / (1 + c)`, maps the
  `white` value to display white. Vanilla values are about 0.9 to 1.05, so the curve stays
  close to the identity.

The `HNAM` units are not documented. Vanilla speeds are 30 to 45, and strengths are 1 (clear
nights) to 25. OpenSky divides the speed by 20 to get a rate per second, and turns the
strength into the weight above. Both constants are OpenSky's own choice, made so that a
cave entrance adapts in about half a second. An image space with no strength and no white
point turns the stage off.

`World > Effects > Image Space` holds the switch (`ImageSpaceToneMappingControl`), and its
readout shows the white point, exposure, measured scene luminance, and eye. The launcher's
graphics page holds the same switch.

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

- The scene renders into an 8-bit target, so tone mapping works on display-range color.
  Bloom, the sunlight scale, and the sky scale are decoded and blended but not drawn.
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
