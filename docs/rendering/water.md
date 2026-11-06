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

- **Normal.** Each of the three noise layers samples its `NAM2`-`NAM4` normal map. The map
  repeats every UV-scale units, scrolls along the layer's wind direction at its wind speed in
  tiles per second, and its amplitude scales the slope. `NAM0` linear velocity moves the whole
  pattern, so a river flows. Every vanilla water names `textures\water\defaultwater.dds`, a
  2048 by 2048 BC1 tangent-space normal map, for all three layers. Until the maps load, each
  layer adds three sine waves with the same wind, tile size, and amplitude instead.
- **Rings.** Splash and wading rings, and rain rings, tilt the normal further; see
  [Displacement and rain](#displacement-and-rain).
- **Reflection.** A Schlick fresnel term starts at the fresnel amount and grows toward grazing
  angles. Reflectivity scales it. The reflected color is the `WATR` reflection color mixed with
  the far fog color, so it follows the sky a little.
- **Sun.** The sun highlight uses the sun specular power (divided by 4, at least 8) and the sun
  specular magnitude. The sparkle adds sharp glints of the same normal: the reflected sun
  direction raised to the sun sparkle power, times the sun sparkle magnitude.
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
water or a soft effect in view. Soft effects read the same copy, so they fade where they meet
the ground ([effect shapes](/formats/nif-materials.md#effect-shapes)); the copy does not hold
the water itself. It can be turned off in Environment > Water; the water then uses a fixed middle
depth and stays half see-through.

## Refraction

When the water reads the scene depth, the split also copies the colour drawn so far. The
water then draws the ground below it itself and writes an opaque pixel. The ground sample
moves by the normal's x and y times the `DNAM` refraction magnitude, in screen units, scaled
up from 0 at the surface to 1 at the fog far depth. A moved sample that lands on something in
front of the water, such as a leg standing in it, takes the straight sample.

## Displacement and rain

A splash starts a ring where it hits the surface: strength 1 for a heavy splash, 0.6 for a
lighter one. An actor or body less than 150 units below the surface starts a strength 0.4
ring each time it has moved 48 units. The newest 8 rings live 3 seconds.

Each ring is a crest that runs out at the `DNAM` displacement velocity, as wide as the
starting size. Its slope is the force times the strength. It fades with the dampener raised
to 30 times its age, as a per-frame factor at 30 frames per second, and over its life. It
falls off with distance by the falloff. Velocity, width, and force have floors of 8, 4, and
0.2, so a record with zeros still shows a ring.

Rain on exterior water draws its own rings: on a 48-unit grid, each cell holds one drop at a
random place and time, if a random draw is below the rain intensity. A drop's ring grows to
24 units over 0.8 seconds.

## Under the water

When the camera is inside a water item's bounds and below its top, the frame fog becomes the
water's under-water fog: the `DNAM` near and far planes, the fog amount as the maximum, and
the deep colour. The water's `INAM` image space becomes the frame's baseline image space
([image spaces](/formats/image-spaces.md#resolution)). In vanilla, `Update.esm` gives almost
every water one shared image space, and the Dawnguard and Dragonborn waters their own.

## Screen-space reflections

With the game's `[Display] bScreenSpaceReflectionEnabled` on, the depth split also copies the
colour drawn so far, and the water reflects it:

- The reflected view ray starts at the water pixel and takes up to 24 steps. The first step is
  24 units long, and each step is a quarter longer than the one before.
- Each step is projected to the screen. The first point behind a stored surface is a hit, if it
  lies less than two step lengths behind it. Sky pixels never hit.
- The hit colour replaces the reflection colour by a weight, as in the game:
  `(1 - c²) * (1 - L)`, where `c` is twice the hit's distance from the screen centre (at most
  1) and `L` is the screen distance from the water pixel to the hit. So the weight is 0 half a
  screen from the centre. A ray that leaves the screen or finds no hit keeps the colour.
- The game marches 16 even steps over a fixed screen length and then refines between the
  last two, and the scale of its length fade is not known; the march above and the scale of
  1 per screen are OpenSky's. Clean-room read of the game's shaders, 2026-11-06.

The water and the blended layers after it are not in the copy, so they do not reflect. With the
water depth switch off, nothing is copied and the reflection stays a colour.

## Where OpenSky differs

- The `NAM5` flow map and the `FNAM` flow-map flags are read but not used, so a river's
  surface follows only `NAM0`.
- The noise normals fade in a straight line from full strength at the camera to flat at the
  noise falloff distance. The
  [Creation Kit](https://ck.uesp.net/wiki/WaterType#noise-falloff) calls the falloff a
  curve but does not give its shape.
- There is no reflection of what lies off screen. Without the game's screen-space reflection
  option, the reflection is a colour.
- In the game, other surfaces reflect too: a lit surface's specular mask (its normal map's
  alpha) weights a screen-space reflection that is added over it. OpenSky reflects only on
  water.
- The game simulates displacement on a height grid. OpenSky draws closed-form rings with the
  `DNAM` displacement fields, so rings do not bounce off the shore or add up. The rain rings
  use OpenSky's own sizes, because the `DNAM` rain simulator is unused
  ([water format](/formats/water.md#watr-colors-and-surface)).
- The refraction unit, the ring shape, and the under-water fog colour are OpenSky's readings.
- The under-water image space replaces the cell's or the weather's at once when the camera
  crosses the surface. Whether the game blends between the two is not known.
