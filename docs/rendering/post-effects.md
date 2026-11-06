---
type: Subsystem
title: Screen-space post effects
description: The effects the image-space composite draws from the scene colour and depth -
  FXAA, ambient occlusion, volumetric light, depth of field, and lens flare - which game option turns each one on, and its values.
tags: [rendering, image-space, metal]
---

# Screen-space post effects

The [image space pass](/rendering/image-space.md) also draws the game's screen-space effects.
Each one is a game option on the launcher's graphics page
([graphics options](/engine/graphics-options.md)). They all read pixels around the one they
change, and most read the scene depth. So when any of them is on, the composite uses its split
path: the scene pass ends, the colour and the depth are copied, and one fullscreen triangle
reads both copies. The grade (tone mapping, tint, fade) runs after the effects, in the same
shader.

The shader rebuilds a pixel's world position from its depth with the inverse of the frame's
view-projection matrix. Upscaled frames add a sub-pixel jitter, which this matrix leaves out.
A frame with no perspective projection, or in a render debug view, draws no effect.

## FXAA

`[Display] bFXAAEnabled`. FXAA (fast approximate anti-aliasing) smooths stair-step edges. It
runs first, on the colour the other effects start from.

- The brightness of a pixel is the square root of its linear luminance.
- Where the pixel and its 4 diagonal neighbours differ by less than 0.0312, or less than 1/8
  of the brightest, the pixel stays as it is.
- Otherwise the neighbours give the edge direction. Two taps at 1/6 of the step average to a
  near result, and two more at 1/2 widen it. The wide result wins unless its brightness
  leaves the neighbours' range.

With an upscaler on, FXAA runs on the smaller scene image, before the upscaler.

## Ambient occlusion

`[Display] bSAOEnable`. Ambient occlusion darkens creases and corners, where less light from
the sky reaches.

- The surface normal comes from the depth of the four neighbours. Each axis takes the shorter
  of its two steps, so an edge does not bend the normal.
- 5 taps sit on a spiral around the pixel, out to 48 world units, turned by a per-pixel noise
  angle. The game also takes 5 taps.
- A tap darkens the pixel by how far it rises above the surface plane (the cosine to the
  normal, less a bias of 0.05). Each tap has the game's weight `(1 - q)³ / (q + 0.01)`, where
  `q = d² / r²` for its distance `d` in the radius `r`. So a near tap counts much more than a
  far one. The game's weight is `(r² - d²)³ / (d² + 0.01)`; OpenSky divides `d` by `r` first,
  because the game's distance units are not known.
- The result is `ao = 1 - 1.2 * mean`, where `mean` is the weighted mean, clamped to 0 to 1.
  The sky is not changed.
- It multiplies the whole lit colour by `ao`: the sun, point lights such as torches, the
  ambient light, and glow alike. The game does the same: its scene colour holds all the
  light in one target, and the occlusion step multiplies that colour (clean-room read of the
  game's shaders in `Skyrim - Shaders.bsa`, 2026-11-06, behaviour only). On snow the game
  raises `ao` by a bias, so snow stays bright. OpenSky leaves a pixel with snow unchanged, as
  the game turns occlusion off wherever the snow mask is above zero
  ([snow ground](/engine/terrain.md#snow-ground)).
- It darkens the colour under the fog, as the game's fog variant does. The fog part of the
  pixel, `fog colour × fog amount`, stays as it is, and only the rest is multiplied by `ao`.
- The effect fades out between 2,048 and 4,096 units from the camera. Far away, depth
  precision makes the normals noisy, and the noise would darken the whole distant view.

## Volumetric light

`[Display] bVolumetricLightingEnable` and `iVolumetricLightingQuality`. Sun light that falls
through the air between the camera and a surface makes shafts where shadows break it.

Each weather names 4 `VOLI` volumetric lighting records in `WTHR` `HNAM`, one per time of
day ([UESP VOLI](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VOLI)). They blend with
the same time-of-day and weather-transition weights as the sky colours. An interior, or a
weather without the link, uses the fallback values in brackets below. Each field maps to the
shader like this:

| `VOLI` field | Use | Fallback |
| --- | --- | --- |
| `CNAM` intensity | strength = 0.025 × intensity | 2 |
| `DNAM` custom colour contribution `c` | light = sun colour × (1 - c) + colour × c | 0 |
| `ENAM` to `GNAM` colour | as above | 1, 1, 1 |
| `HNAM` density contribution | how much the density noise thins the air | 0 |
| `INAM` density size | one noise cell is 64 × size units | 10 |
| `JNAM` wind speed | the noise drifts 4 × speed units per second along X | 0 |
| `KNAM` falling speed | the noise falls 64 × speed units per second | 0 |
| `LNAM` phase contribution `p` | phase = mix(1, Henyey-Greenstein, p) | 1 |
| `MNAM` phase scattering `g` | the Henyey-Greenstein asymmetry | 0.6 |
| `NNAM` sampling range factor | the ray reach = 102.4 × factor units | 40 |

The vanilla records all use colour 1, 1, 1, custom colour 0, density 0.3, size 10, wind 15,
falling 0.3, and range 40. Intensity runs 1 to 4, and `p` and `g` run 0.7 to 0.85.

- The ray from the camera to the pixel, at most the reach long, takes a fixed number of
  steps: 8, 16, or 32 for quality 0, 1, or 2. A per-pixel noise offset turns the step bands
  into grain.
- Each step takes one tap of the [sun cascades](/rendering/shadows.md), times the air density
  there: `1 - density × noise`, where the noise is smooth value noise from 0 to 1. The mean
  over the steps is the light along the ray.
- The Henyey-Greenstein phase makes the air brightest toward the sun:
  `(1 - g²) / (1 + g² - 2g cos θ)^1.5`, where θ is the angle between the ray and the sun.
- The added colour is the light times the lit share, the phase, `1 - exp(-length / reach)`,
  and the strength. The sky pixels take the full length.
- A sky pixel does not march: its lit share is 1. A sky ray leaves the cascades at their
  edges, and those edges would cut a hard disc and bands into the sky.
- With shadows off, nothing is added.

## Depth of field

`[ImageSpace] bDoDepthOfField`. The current image space's `DNAM` gives a strength, a clear
distance, a range, and a code for the blur radius and the sky
([image space records](/formats/image-spaces.md#depth-of-field)). Weather and cell image
spaces blend the numbers by weight; the sky flag comes from the heaviest one. A running
modifier with a depth of field channel moves each value toward its own, by the modifier's
strength.

- The CK wiki ([ImageSpace Modifiers](https://ck.uesp.net/wiki/ImageSpace_Modifiers)) says
  the distance "contains a clean, non-blurred view", and a distance higher than the range
  "will create a blurred foreground with a clear background". So the blur is 0 at the
  distance and full at the range, on whichever side the range is. Example: distance 0 and
  range 2,000 blur everything past 2,000 units fully; distance 500 and range 100 blur
  everything nearer than 100 units fully.
- A modifier's `DNAM` front and back flags pick the side instead: front blurs nearer than
  the distance, back blurs past it, and both blur both sides.
- The sky counts as infinitely far. "No Sky", in the image space code or a modifier's flag,
  keeps it sharp.
- Full blur is the strength, clamped to 0 to 1, times `2 + 2 × radius` pixels at a
  1080-pixel-high frame, for the Creation Kit's "Blur Radius" of 0 to 7. A record without the
  code uses radius 3, which is 8 pixels.
- Two rings of 8 taps average the colour. A tap that is itself sharp is skipped, so a sharp
  shape does not bleed into the blur around it.
- A strength of 0 draws nothing.

## Lens flare

`[ImageSpace] bLensFlare`. Bright ghost discs appear on the line from the sun through the
screen centre.

- Only outdoors under a sky, and only while the sun is above the horizon and in front of the
  camera.
- 9 depth taps around the sun's screen position count how much of it is open sky. A sun
  hidden behind a hill or a roof draws no flare.
- 5 soft discs in fixed tints sit at 0.4, 0.7, 1.1, 1.5, and 1.9 of the way from the sun to
  the centre and past it. They take the sun colour, and fade as the sun nears the screen edge.
- The strength is 0.6 times the sun disc's alpha and the weather's Sun Glare, the `WTHR`
  `DATA` byte read as 0 to 1 ([UESP WTHR](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WTHR)).
  A storm with no glare hides the sun, so it draws no flare.

## Image-based lens flare

`[Display] bIBLFEnable`. OpenSky does not draw it yet. Behaviour described from a clean-room
read of the shaders in `Skyrim - Shaders.bsa` and of `SkyrimSE.exe` 1.7.104.0 on 2026-11-06
(only the behaviour was reported, no code):

- A 4-tap downsample keeps the brightest tap by luminance (0.3, 0.59, 0.11), optionally
  averaged half and half with last frame's value.
- A 1-D blur then runs along each screen axis. It takes `2n + 1` taps a fixed step apart. A tap
  counts only if one of its channels is above a threshold, and then adds its whole colour,
  clamped to 0 to 1. The sum is scaled by one factor.
- The game names ghosts, a halo, and a horizontal streak for this effect, but no shipped shader
  draws them.

A second read on 2026-11-06 found the tap counts: the horizontal blur has a radius of 7 taps
on each side, 15 in all, and the vertical blur a radius of 2, 5 in all. Each tap adds
`max(colour × exposure - threshold, 0) × scale`; one variant weights the colour by its
luminance first. The game's defaults for the effect: 3 lenses, a dispersal of 0.3, a channel
offset of +2 for red and -2 for blue, a halo of 0.5 with a width power of 3, an anamorphic
strength of 0.1, and an overall strength of 0.7.

The step between taps, the threshold and scale values, and how the result joins the frame are
still not known.

## Where OpenSky differs

- Ambient occlusion: the radius and the strength are OpenSky's own, and the tap distance is
  divided by the radius before the game's weight. The game then applies a contrast curve, a
  blend over time, and a blur, which OpenSky does not have. A second clean-room read of the
  game's shaders and of `SkyrimSE.exe` 1.7.104.0 (2026-11-06, behaviour only) describes them;
  see [the game's occlusion steps](#the-games-occlusion-steps).
- Screen-space reflections: OpenSky reflects on water only. The game also reflects on other
  surfaces; see [the game's reflections](#the-games-reflections).
- The volumetric light's scales from `VOLI` fields to world units and strength are OpenSky's
  reading of the field names. The noise drifts along X, because no wind direction is known.
- A modifier's "Use Target" flag, which focuses on the crosshair target, is not used.
- The lens flare is OpenSky's own pattern. The game names a `LENS` lens flare record, but the
  vanilla install has none (Skyrim.esm, Update.esm, and the three DLC files have no `LENS`
  group), so there is no data to draw from.

## The game's occlusion steps

Behaviour described from a clean-room read of the game's shaders and of `SkyrimSE.exe`
1.7.104.0 on 2026-11-06. Which user value feeds which shader value is likely, not confirmed.

- Defaults: on, intensity 15, radius 250 game units, bias 2.5, a contrast exponent of 0.11,
  and a history difference factor of 0.3.
- Each tap adds `max((v . N - b) / (|v|² + 0.01), 0) × max(R² - |v|², 0)³`, where `v` is the
  view-space vector to the tap in game units. A tap counts only if its stored depth is not in
  front of a threshold.
- The bias `b` grows with depth and toward the screen edge:
  `b = bias + 10 × max(depth / 7000 - 0.3, 0) + 2 × (x² + y²)`, with `x` and `y` in clip space.
- The 5 taps sit at angle `(i + 0.5) × 2.512` radians plus a per-pixel angle, which changes
  each frame for near pixels. Tap `i` reaches `0.2 × (i + 0.5) × R / depth` on screen.
- Contrast: `A = max(1 - sum × intensity, 0)`, then `A' = A^(2k)` for a contrast value
  `k` below 0.5, else `A' = A^(1 / (2 - 2k))`. With the default 0.11, `A' = A^0.22`.
- Blend over time: `out = A' + w × (history - A')`. The weight `w` drops to 0 when the depth
  or the motion differs from last frame, or when the occlusion changed by much. Sky pixels
  output 1.
- Blur: a 7-tap two-pass blur at 0, ±2, ±4, and ±6 texels, with weights 0.153, 0.445, 0.423,
  and 0.393, each cut by the depth difference.

## The game's reflections

Behaviour described from the same read. The game reflects every pixel whose reflectance mask
is above zero, not only water; water uses a flat up normal.

- The reflected ray is marched in 16 equal steps over 0.4 of the screen, then refined in up
  to 16 smaller steps. A hit must lie within a thin depth band, 0.001 thick, behind the ray.
- No hit, a ray toward the camera, or an end point off screen gives no reflection.
- The colour is the hit colour times a strength of 0.8. The alpha is the mask, times a fade
  over the ray length, times a fade toward the screen edge, `1 - min(2 × |hit - 0.5|, 1)²`.
- The reflection buffer is half the frame size.
