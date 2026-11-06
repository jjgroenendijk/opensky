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
2. Spells, explosions, and scripts start `IMAD` modifiers. Each one runs for its playback
   time, then ends; a looping one runs until it is stopped.
3. The pass reads the baseline with every modifier applied, clamps the values to a range the
   shader can show, and draws. A neutral result skips the pass, so a frame without an image
   space costs nothing.

Most grades read only the pixel they change. Those draw one fullscreen triangle inside the scene
pass, and the shader reads the pixel from tile memory, so the frame needs no copy and keeps its
depth [memoryless](/rendering/metal4-renderer.md). Blur, radial blur, motion blur, double
vision, and bloom read other pixels. For them the scene pass ends, the color is copied, and a second
pass grades the copy. The
[screen-space post effects](/rendering/post-effects.md) use the same split, and the composite
also runs when only they are on.

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

The launcher's graphics page holds the tone mapping switch.

## Combining modifiers

The [CK wiki "ImageSpace Modifiers"](https://ck.uesp.net/wiki/ImageSpace_Modifiers) page gives
two rules, and OpenSky follows both:

- The tint RGB is the average of every active tint, weighted by its alpha. The alpha is the
  highest alpha. The baseline `IMGS` tint takes part like a modifier. A modifier's alpha is
  multiplied by its strength first.
- The blur radius and the double vision are the highest value over the active modifiers.

OpenSky also keeps the highest motion blur. The radial blur of the strongest modifier wins
with its whole shape: ramps, start points, and centre.

## Blur effects

- **Radial blur.** Each pixel takes 8 taps on the line to the `DNAM` centre. The radius `r` is
  the share of the centre-to-corner distance. The weight is
  `clamp((r - start) * rampUp, 0, 1)`; when `downStart` is past `start`, it is also multiplied
  by `clamp(1 - (r - downStart) * rampDown, 0, 1)`. The taps reach `strength` percent of the
  way to the centre, times the weight.
- **Motion blur.** The pass keeps last frame's view-projection. For each pixel it finds where
  the same far-plane direction was last frame, so only the camera's turn makes a trail. The
  trail is 3 × `s / (1 - s)` frames of that motion, the trail of a frame blend that keeps `s`
  of the last frame. It is capped at a tenth of the screen.

## Bloom and light scales

These need colour above 1, so they run only with the HDR target on
(`bUse64bitsHDRRenderTarget`).

- **Bloom.** Three rings of 8 taps reach out to the `IMGS` bloom radius. One radius step is 4
  pixels at a 1080-pixel-high frame; the CK wiki gives the range 1 to 7. Each tap adds what it
  holds above the bloom threshold. The sum is scaled by the bloom scale and added before tone
  mapping.
- **Sunlight and sky scale.** The CK wiki calls both "non-imagespace". The sun colour is
  multiplied by the sunlight scale and the sky dome colours by the sky scale. Clouds keep their
  colour.

At most 16 modifiers run at once. The oldest goes first. This is OpenSky's own limit.

## Triggers

| Source | Strength |
| --- | --- |
| A spell hit on the player | 1, from the `MGEF` image-space modifier |
| An explosion | 1 at the center, falling linearly to 0 at the `EXPL` image-space radius, measured to the camera; a zero radius plays at 1 |
| `ImageSpaceModifier.Apply(float afStrength = 1.0)` or `PopTo(ImageSpaceModifier, float)` | The script's strength, clamped to 0 to 1 |
| `ImageSpaceModifier.ApplyCrossFade(float afFadeDuration = 1.0)` | Rises from 0 to 1 over the fade time, held until `Remove` or the global `RemoveCrossFade(float afFadeDuration = 1.0)`, which falls back to 0 over its own fade time |

A spell hit on another actor starts no modifier, because the modifier describes what the
player sees.

## Low health

Behaviour described from a clean-room read of `SkyrimSE.exe` 1.7.104.0 on 2026-11-06 (only the
behaviour was reported, no code). The share is the player's health over its maximum. The game
reads it each time the health changes.

- At or below `fPlayerHealthHeartbeatSlow` (0.2) the default object `IMLH` (`LowHealthImod`)
  pulses: the first pulse starts at once, then one every `fLowHealthIModInterval` (2 s). Each
  pulse is a new one-shot start. Its strength runs in a straight line from
  `fLowHealthIModStrengthMin` (0.8) at a share of 0.2 to `fLowHealthIModStrengthMax` (1.5) at
  `fPlayerHealthHeartbeatFast` (0.1), and stays 1.5 below that, even at 0.
- Above 0.2 no new pulse starts; a running one plays to its end.
- The heartbeat sound `HSSD` plays from above 0.1 up to 0.2, and `HFSD` above 0 up to 0.1. A
  change between the two stops the old one at once and starts the new one at full volume.
  Leaving both bands, by healing or by death, fades the sound out over
  `iPlayerHealthHeartbeatFadeMS` (1,000 ms). A heartbeat that ended starts again on the next
  health change in its band.

Loading a save stops the heartbeat at once, and the cues read the health afresh.
The launcher's "Low-health pulse" switch stands for the game's `bLowHealthIModEnabled`.
OpenSky reads the maximum with temporary modifiers included; the game leaves them out.

## Where OpenSky differs

- The scene renders into an 8-bit target, so tone mapping works on display-range color. With
  the game's `bUse64bitsHDRRenderTarget` on, the target is half-float in linear sRGB instead,
  and colour above 1 reaches the tone mapping. Only then do bloom and the light scales draw.
- The bloom tap pattern, the radius step, and the receive-bloom threshold are not documented.
  OpenSky reads the receive threshold but does not use it.
- The radial blur reach, its radius unit, and the centre's screen space are OpenSky's reading
  of the CK wiki text. Motion blur follows only the camera's turn, not moving objects.
- Depth of field draws as a [post effect](/rendering/post-effects.md#depth-of-field) when its
  game option is on. The blur radius is a 12-tap disc blur, and double vision is one ghost
  image offset to the side.
- A cross-fade rises and falls linearly over its fade time. The curve is OpenSky's choice.
  Only one cross-faded modifier is held, as in the game, and a new one replaces it; the old
  one fades out over the new one's fade time.
- The tint mixes the color toward its own brightness times the tint color, by the tint
  amount. The fade mixes toward the fade color by its alpha, and several fades lay over each
  other like alpha. How one tint or fade changes a pixel is not documented, so these mixes are
  approximations; only the way tints combine has a source.
