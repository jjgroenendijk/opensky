---
type: Subsystem
title: Screen-space post effects
description: The effects the image-space composite draws from the scene colour and depth -
  ambient occlusion, volumetric light, and depth of field - which game option turns each one on, and its values.
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

## Ambient occlusion

`[Display] bSAOEnable`. Ambient occlusion darkens creases and corners, where less light from
the sky reaches.

- The surface normal comes from the depth of the four neighbours. Each axis takes the shorter
  of its two steps, so an edge does not bend the normal.
- 12 taps sit on a spiral around the pixel, out to 48 world units, turned by a per-pixel noise
  angle.
- A tap darkens the pixel by how far it rises above the surface plane (the cosine to the
  normal, less a bias of 0.05), times `1 - d² / r²` for its distance `d` in the radius `r`.
- The result is `1 - 1.2 * mean`, clamped to 0 to 1, and multiplies the colour. The sky is
  not changed.

## Volumetric light

`[Display] bVolumetricLightingEnable` and `iVolumetricLightingQuality`. Sun light that falls
through the air between the camera and a surface makes shafts where shadows break it.

- The ray from the camera to the pixel, at most 4,096 units long, takes a fixed number of
  steps: 8, 16, or 32 for quality 0, 1, or 2. A per-pixel noise offset turns the step bands
  into grain.
- Each step takes one tap of the [sun cascades](/rendering/shadows.md). The share of lit
  steps is the light along the ray.
- A Henyey-Greenstein phase with asymmetry 0.6 makes the air brightest toward the sun:
  `(1 - g²) / (1 + g² - 2g cos θ)^1.5`, where θ is the angle between the ray and the sun.
- The added colour is the sun colour times the lit share, the phase, `1 - exp(-length / 4096)`,
  and a strength of 0.05. The sky pixels take the full length.
- With shadows off, nothing is added.

## Depth of field

`[ImageSpace] bDoDepthOfField`. The current image space's `DNAM` gives a strength, a focus
distance, and a range ([image space records](/formats/image-spaces.md)). Weather and cell
image spaces blend these values by weight. A running modifier with a depth of field channel
moves each value toward its own, by the modifier's strength.

- The blur is 0 up to the focus distance. It grows over the range, and is full past
  distance + range. The sky is always full.
- Full blur is the strength, clamped to 0 to 1, times a radius of 8 pixels at a
  1080-pixel-high frame.
- Two rings of 8 taps average the colour. A tap nearer than the focus distance is skipped, so
  a sharp foreground does not bleed into the blur behind it.
- A strength of 0 draws nothing.

## Where OpenSky differs

- Ambient occlusion multiplies the whole colour, sun light included. In the game it darkens
  only the ambient light. The radius, the strength, and the tap count are OpenSky's own.
- Volumetric light uses OpenSky's own strength and reach for every weather. The game's
  weathers name a `VOLI` volumetric lighting record, which OpenSky does not read.
- Depth of field blurs only behind the focus. The `DNAM` sky and blur radius code is not
  decoded, so the radius is OpenSky's own and the sky always blurs. How a modifier's depth of
  field channel combines with the base is not documented.
