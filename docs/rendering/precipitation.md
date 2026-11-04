---
type: Subsystem
title: Precipitation volumes
description: Rain and snow as two camera-following particle volumes - intensity from the WTHR
  classification and the weather transition, storm sky darkening, the moving volume, per-drop roof
  occlusion, and the Weather controls.
tags: [rendering, precipitation, weather, particles, collision, metal]
---

# Precipitation volumes

Rain and snow are two particle playbacks owned by the renderer that follow the camera. They use the
shared [particle simulation and billboard pass](/rendering/particles.md), with alpha blending, depth
testing, and the weather wind. The streak and flake masks are generated into textures when the
renderer starts. No game texture is used.

## Intensity

A `WTHR` `DATA` field gives a classification, not a precipitation density. So Rainy means rain 1,
Snow means snow 1, and Pleasant, Cloudy, or no weather means zero. Rain and snow values blend across
the timed [weather](/engine/weather.md) transition. The transition progress is the intensity, so
rain can fade into snow without a jump. The active weather's `SPGD` record then scales rain
and snow speed, size, and density ([SPGD](/formats/environment-shading.md#precipitation-mapping)).

The settled intensity drives emission. The shared fallback rate caps the base at 60 births per
second. Rain multiplies it by 6 and snow by 4 before the capacity clamp. These factors are OpenSky's
visual choice, not known engine constants. Rain speeds up with the wind more than drifting snow does.

At full rain or snow, the sky's upper and lower colors, horizon, sun, and glare darken by up to 35
percent. Authored fog, sunlight, ambient, and `DALC` do not change. Clear weather draws exactly as
before.

## The volume

| | Box (units) | Motion |
| --- | --- | --- |
| Rain | 2,200 by 2,200 by 700 | Falls down |
| Snow | 2,400 by 2,400 by 900 | Falls slower, lives longer, turns more |

The emitter sits 600 units above the camera. When the camera moves, the emitters and every live
particle move by the same amount. So the density near the camera stays the same, and no trail is
left behind while flying or walking. A move of more than 1,100 units in one frame, half the
narrowest box, is a teleport: it drops every live particle, because those flakes belong to the
old place and its weather. The new weather's particles then build up from the emitter.

The renderer owns the playbacks outside the render scene, so rebuilding cells does not reset a storm.
An interior, a world space with no sky, or turning precipitation off clears the particles and skips
drawing. Going back to clear weather sets the birth rate to zero, and existing particles age out.

## Roof occlusion

The game's `[Display] bUsePrecipitationOcclusion` turns roof occlusion on
([graphics options](/engine/graphics-options.md)). While rain or snow falls, the shadow pass draws
one more depth view: it looks straight down on a 4,096-unit square around the camera, from 6,000
units above the camera to 4,000 below, at 1,024 texels a side. It keeps the highest caster over
each texel. Actors are left out. The view lives in a second depth array beside the sun cascades,
built the first time an option needs it.

The particle shader compares each drop with that depth. A drop more than a little below the
highest surface is under a roof and is discarded. So rain still falls outside a window seen from
under a roof.

When the GPU cannot make the depth array, one ray goes up from the camera, up to 4,096 units,
through the loaded [static collision](/engine/collision-world.md). Any hit clears the whole
volume until the ray is open again. When the option is off, rain falls through roofs, as in the
game.

## Not done

- Precipitation collision, splashes, and snow building up.
- Streak shapes separate from the square billboards.
