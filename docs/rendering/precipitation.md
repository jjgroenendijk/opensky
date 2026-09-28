---
type: Subsystem
title: Precipitation volumes
description: Rain and snow as two camera-following particle volumes - intensity from the WTHR
  classification and the weather transition, storm sky darkening, the moving volume, single-ray roof
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
rain can fade into snow without a jump.

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
left behind while flying or walking.

The renderer owns the playbacks outside the render scene, so rebuilding cells does not reset a storm.
An interior, a world space with no sky, or turning precipitation off clears the particles and skips
drawing. Going back to clear weather sets the birth rate to zero, and existing particles age out.

## Roof occlusion

While precipitation is active, one ray goes up from the camera, up to 4,096 units, through the
loaded [static collision](/engine/collision-world.md). The broad phase asks each cell's tree for a
thin vertical box. The narrow phase tests triangle soups, convex hull faces, and boxes exactly, from
both sides. Curved shapes use their world box, which is safe. Any hit clears the volume until the
ray is open again. This is a single-point roof test on purpose.

## Where to see it

`World > Environment > Weather` can force any decoded `WTHR`, has Clear, Rain, and Snow shortcuts,
and can pause the weather transition (particles keep playing). Precipitation has its own on and off
switch. The readout shows the main type, the blended intensity, rain and snow counts, and whether the
camera is under a roof.

## Not done

- Roof masks from several rays, precipitation collision, splashes, and snow building up.
- Density tuned per weather beyond the classification and the transition.
- Streak shapes separate from the square billboards.
