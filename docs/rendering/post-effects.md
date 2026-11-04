---
type: Subsystem
title: Screen-space post effects
description: The effects the image-space composite draws from the scene colour and depth -
  ambient occlusion - which game option turns each one on, and its values.
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

## Where OpenSky differs

- Ambient occlusion multiplies the whole colour, sun light included. In the game it darkens
  only the ambient light. The radius, the strength, and the tap count are OpenSky's own.
