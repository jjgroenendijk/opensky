---
type: Subsystem
title: Water
description: How OpenSky draws cell water planes and placed water meshes - the WATR fields it
  uses, the noise normal, the depth split that makes shallow water see-through, and where it
  differs from the game.
tags: [rendering, water, metal]
---

# Water

Water has two sources. An exterior cell with water gets one flat plane at its water height. A
placed mesh whose shape uses `BSWaterShaderProperty` draws as water too, with the water type of
its cell. Both draw in the water pass, after opaque, alpha-test, and grass geometry, and before
the [blended shapes](/rendering/scene-drawing.md#blended-shapes). The pass tests depth without
writing it and blends straight alpha.

The record fields come from `WATR` ([exterior water records](/formats/water.md)). A cell with a
missing or unknown water type gets fixed fallback colors and a calm default shading. A placed
water mesh in a cell without a water plane gets the same fallback.

## Surface

- **Normal.** Each of the three noise layers adds three sine waves. Their directions spread
  around the layer's wind direction. The layer's tile size sets the wave length, its wind speed
  sets how fast the waves move in tiles per second, and its amplitude sets the slope. `NAM0`
  linear velocity moves the whole pattern, so a river flows.
- **Reflection.** A Schlick fresnel term starts at the fresnel amount and grows toward grazing
  angles. Reflectivity scales it. The reflected color is the `WATR` reflection color mixed with
  the far fog color, so it follows the sky a little.
- **Sun.** The sun highlight uses the sun specular power (divided by 4, at least 8) and the sun
  specular magnitude.
- **Body.** The body color blends from the shallow color to the deep color over the fog near
  and far depths. Ambient light and some sunlight light it.

## Depth

To know how deep the water is under a pixel, the water reads the scene depth. A Metal render
encoder cannot sample its own depth attachment, so the pass splits:

1. The scene pass starts on a stored depth target, as a split
   [image-space grade](/rendering/image-space.md) does.
2. Before the water, the encoder ends and the depth is copied to a texture the shader can read.
3. A second encoder loads the color and depth and draws the water, and every later layer.

The shader turns the stored depth back into view depth with two projection terms: view depth =
`m32 / (depth + m22)`. That is the inverse of the right-handed perspective projection that maps z
to 0...1. The difference to the water's own view depth, divided by how much the ray faces
forward, is the water along the ray. Times the vertical part of the ray, it is the water column.

Shallow water shows the ground: there the alpha drops toward the `ANAM` opacity. Deep water, and
water seen edge-on, is opaque. The split costs one depth copy and one encoder per frame with
water in view. It can be turned off in Environment > Water; the water then uses a fixed middle
depth and stays half see-through.

## Where OpenSky differs

- The game samples noise normal textures (`WATR NAM2`-`NAM4`). OpenSky computes the normal from
  sine waves with the same wind, tile size, and amplitude, so it needs no texture and no fallback
  when vanilla rivers leave those paths empty.
- There is no real reflection of the scene and no refraction offset. The reflection is a color.
- The sun sparkle fields, displacement, rain simulation, and under-water fog are not drawn.
