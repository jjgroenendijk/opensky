---
type: Subsystem
title: Screen-space post effects
description: The effects the image-space composite draws from the scene colour and depth -
  FXAA, ambient occlusion, indirect light, volumetric light, depth of field, and lens flare - which game option turns each one on, and its values.
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
- It runs in three compute passes after the scene copy: a trace, then a blur along each screen
  axis. The composite reads the blurred result.
- 5 taps sit on a spiral around the pixel, out to the game's radius of 250 world units, at
  the game's angles `(i + 0.5) × 2.512` radians. A per-pixel noise angle turns them, and the
  turn moves by the golden ratio each frame, so the blend over time averages several turns.
  The game also takes 5 taps and turns them each frame.
- Each tap adds the game's term `max(R² - |v|², 0)³ × max((v . N - b) / (|v|² + 0.01), 0)`,
  where `v` is the vector to the tap in world units and `N` the normal. The bias `b` is
  `2.5 + 2 × (x² + y²) + 10 × max(d / 7000 - 0.3, 0)`, with `x` and `y` the pixel's place in
  clip space and `d` its camera distance. So the bias grows toward the screen edge and far
  away.
- The game's contrast curve: `A = max(1 - sum × 15 / R⁶, 0)`, then `ao = A^0.22`, from the
  game's contrast value 0.11 (`A^(2 × 0.11)`). The sky is not changed.
- Blend over time: the trace keeps each pixel's occlusion and camera distance. Next frame it
  finds the same world point in that history through last frame's view, and
  `ao = ao + w × (history - ao)`. The weight is the game's two ramps multiplied:
  `max(1 - 200 × |Δd| / 7000, 0)` for the distance change, and
  `clamp(1 - 0.3 × |Δao|, 0, 1)` for the occlusion change. So a steady pixel keeps its
  history, and a change fades it out. After a resize or a frame without occlusion, the new
  value stands alone.
- Blur: the game's 7 taps at 0, ±2, ±4, and ±6 texels, with weights 0.153, 0.445, 0.423, and
  0.393, first along x, then along y. A tap whose camera distance differs from the pixel's by
  5 percent or more counts for nothing, so the blur does not cross an edge.
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

## Indirect light

"Screen-space indirect light" on the launcher, off by default as in the game. Lit surfaces
bounce some of their colour onto the surfaces that face them. It runs as one compute pass
beside the occlusion trace, and the composite adds its colour before the occlusion. The
steps follow a clean-room read of the game's shaders (2026-11-06, behaviour only):

- 15 taps on a spiral, at angles `(i + 0.5) × 3.3493` radians plus the per-pixel turn, out to
  a radius `R` of 100 units.
- Each tap adds its scene colour times
  `max(((v . N)(-v . N_t) - b) / (|v|⁴ + 0.01), 0) × max(R² - |v|², 0)³ × (1 - |v| / R)`,
  where `v` runs from the pixel to the tap and `N_t` is the tap's normal. The bias is
  `b = 2.5 + 5 × (x² + y²) + 10 × max(d / 7000 - 0.3, 0)`.
- The light is `max(sum / R⁶ × s / 3, 0)`, faded by a smoothstep of `(10000 - d) / 10000`.
- Blend over time: `out = light + h × (history - light)`, with
  `h = 0.3 × max(1 - 200 × |Δd| / 7000, 0) × Σ max(1 - 0.7 × |Δc|, 0)` over the three colour
  channels. `h` is 0 when last frame's point lies within 1 percent of the screen edge.

The game's strength `s`, its bias at the centre, and how the result joins the lighting are
not known. OpenSky uses `s = 400`, the occlusion's bias 2.5, and adds the light to the lit
colour. The game reads its normals partly from a normal buffer; OpenSky has none and uses the
depth normals. The game blends `(v . N)(v . N_t)`; OpenSky turns the tap normal around, so a
surface facing back at the pixel counts. `state frame` shows it under
`postEffects.indirectLight`.

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

### Focus on the view centre

A modifier with "Use Target" (`DNAM` byte 224) focuses on what the view centre shows, as the
game does in dialogue. The modifier still turns the blur on; the focus values come from the
game's rules (clean-room read of `SkyrimSE.exe` 1.7.104.0 and its shaders, 2026-11-06,
behaviour only):

- The focus `f` is the camera distance at the screen centre, mixed with 8 points on a ring
  around it. Sky and far points count as 50,000 units.
- `t = clamp((f - 100) / 900, 0, 1)`. The range grows from 100 to 10,000 units and the
  strength falls from 0.8 to 0.56 as `t` goes from 0 to 1. The blur grows over the range on
  both sides of `f`, unless the modifier's flags pick a side.
- The centre counts 0.6 as much as each ring point while the view moves. Once the view has
  turned less than 2 degrees and moved less than 5 units for 0.5 seconds, its weight eases to
  1.6 outdoors, or 1.0 indoors, over 1 second on a quarter sine. A turn or move resets it.

The game finds the focus on the GPU with a centre weight; the ring of 8 points at 5 percent of
the screen from the centre is OpenSky's. `state frame` shows `usesTarget` and the
`centreWeight` under `postEffects.depthOfField`.

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

- Ambient occlusion: the tap reach on screen comes from the projection, because the game's
  screen units are not known. The game's history weight also drops where an object moves
  against the camera motion; OpenSky reprojects with the camera only, so it has no such term.
  The 5 percent edge of the blur is OpenSky's own. The camera distance stands in for the
  game's linear depth.
- Screen-space reflections: OpenSky reflects on water only. The game also reflects on other
  surfaces; see [the game's reflections](#the-games-reflections).
- The volumetric light's scales from `VOLI` fields to world units and strength are OpenSky's
  reading of the field names. The noise drifts along X, because no wind direction is known.
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
- Blend over time: `out = A' + w × (history - A')`, with `w = m × a × z`. The motion term
  `m = max(1 - 200 × |motion change|, 0.2)` compares the motion with the motion a little
  ahead along it. The value term is `a = clamp(1 - 0.3 × |A' - history|, 0, 1)`, and the
  depth term is `z = max(1 - 200 × |depth / 7000 - history depth|, 0)`. There is no hard
  cut. Sky pixels output 1.
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
