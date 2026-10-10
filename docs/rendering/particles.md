---
type: Subsystem
title: Particle playback
description: CPU particle simulation from NIF particle systems, the interim birth-rate policy,
  camera-facing billboards, blend families mapped from NIF alpha functions, wind input, and the
  Particles controls.
tags: [rendering, particles, metal, weather]
---

# Particle playback

NIF particle definitions become CPU simulations owned by the cell, drawn with one instanced call per
system. Decoding is on the [NIF particle systems](/formats/nif-particles.md) page. The meaning of
emitters, modifiers, and `AlphaFunction` values comes from NifTools
[`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml). The runtime policies below are
OpenSky choices, not known Creation Engine constants.

## Lifetime

Particle definitions are cached, unchanged, beside each loaded model. Every placed reference gets
fresh playback state, seeded by its form ID and the system index. The render scene owns the
playbacks while its cell is loaded, and the instance buffers and effect textures are part of the
scene's residency. Unloading the cell frees them.

Each playback owns a shared buffer with three ranges, one per frame in flight. Its capacity is the
`NiPSysData` `BS Max Vertices`, clamped to 2,048 per system.

## Simulation

The simulation is deterministic for a seed and a sequence of fixed steps.

- Box, cylinder, and sphere emitters create particles in world space. A mesh emitter picks a
  vertex, an edge, or a face of its shapes, as its `EmitFrom` value says. The start direction
  is the surface normal, the emission axis, or random, as its `VelocityType` says.
- Speed, declination, planar angle, color, radius, and lifespan, each with its variation, set up a
  new particle. A particle dies at the end of its lifespan.
- Active modifiers run in file order. Gravity changes velocity. Wind adds the live weather vector
  times the NIF strength. Scale follows the decoded size curve. Modifiers that are not supported do
  nothing and show up in the parser's diagnostics.
- Radius and alpha fade in at birth and out at death, so particles do not pop.
- Subtexture offsets pick each particle's rectangle in the texture atlas.

An emitter with an `NiPSysEmitterCtlr` births at the keyed rate, sampled linearly at the
controller's time. The time loops, reverses, or clamps between the start and stop times. While
the on/off track is off, the emitter births nothing. A full system does not save births for
later.

An emitter without a controller fills about a quarter of the capacity per average lifespan,
clamped to 6 to 60 births per second. Both rates are times the user's emission scale. An
offscreen render at an exact time resets to the seed and steps in 50 ms slices, so frame tests
repeat.

## Drawing

The CPU uploads the center, radius, color, and texture rectangle of each live particle. The vertex
shader builds six corners around each center from the camera's right and up vectors, so there is no
vertex or index buffer. The fragment shader samples the effect texture, applies scene fog, and
discards near-zero alpha. Particles test depth against opaque geometry, never write depth, and are
not culled.

| NIF source and destination | Pipeline | Used for |
| --- | --- | --- |
| `SRC_ALPHA`, `ONE` (6 and 0) | Additive | Flame, sparks, glow |
| `ONE`, `ONE` (0 and 0) | Additive one | Full-color glow |
| `DEST_COLOR`, `ZERO` (4 and 1) | Multiply | Modulation effects |
| Anything else, or none | Alpha | Smoke, steam, water |

Placed and effect systems draw far to near, by the distance from the camera to the emitter
origin. Inside an alpha or multiply system, the particles also draw far to near. Additive
systems are not sorted inside, because a sum does not depend on order. Rain and snow follow
the camera and draw last.

## Wind and controls

The renderer publishes the blended weather wind, and every live frame passes it to the active
`BSWind` modifiers. Calm or no weather is zero.

`World > Environment > Particles` turns drawing on and off (the simulation keeps its state), freezes
the simulation (the current frame stays), turns the far-to-near sort on and off, scales new births
from 0 to 200 percent (living particles go on), and shows resident systems, active emitters, live
particles, and systems with a keyed birth rate. The sort is the player setting
`rendering.particleSorting`, which the launcher's Graphics page also shows.

## Not done

- Birth rates that a controller manager sequence feeds.
- Rotation, drag, spawn and death chains, collision, and strip particles.
- Soft particles that fade near depth.
- Collision and splashes for precipitation, which uses this path ([precipitation](/rendering/precipitation.md)).
