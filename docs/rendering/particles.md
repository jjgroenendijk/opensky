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
- Subtexture offsets pick each particle's rectangle in the texture atlas. A sub-texture
  modifier sets the start frame, the loop start, and the frame count, so a particle plays its
  atlas frames.
- A rotation modifier sets each particle's start angle and spin speed, with their variations.
- An inherit velocity modifier adds a share of the emitter's velocity to a new particle in a
  world-space system.
- Drag slows a particle. A particle collider makes it bounce or die where its path crosses the
  collider.
- An age death modifier with a spawn modifier spawns children when a particle dies, up to the
  spawn's generation count.

An emitter with an `NiPSysEmitterCtlr` births at the keyed rate, sampled linearly at the
controller's time. The time loops, reverses, or clamps between the start and stop times. While
the on/off track is off, the emitter births nothing. A full system does not save births for
later.

A controller that a controller manager drives takes its keys and timing from one sequence.
The game starts sequences from animation events, which OpenSky does not send to effects yet.
So OpenSky plays one default sequence per controller, chosen among the sequences that feed
it: the first whose name ends in `idle` (any case), else the first loop, else the first.
This is an OpenSky policy, not a value read from the game. A controller with no keys in
that sequence keeps its own keys.

An emitter without a controller fills about a quarter of the capacity per average lifespan,
clamped to 6 to 60 births per second. Both rates are times the user's emission scale. An
offscreen render at an exact time resets to the seed and steps in 50 ms slices, so frame tests
repeat.

## Drawing

The CPU uploads the center, radius, color, and texture rectangle of each live particle. The vertex
shader builds six corners around each center from the camera's right and up vectors, so there is no
vertex or index buffer. Particles test depth against opaque geometry and never write depth. A
system whose live particles lie outside the view is not drawn. Its simulation still runs, so it
looks the same when it comes back into view.

The fragment shader shades a particle like an effect shape that faces the eye
([effect shapes](/formats/nif-materials.md#effect-shapes)): the system's base color, palette,
falloff, soft effect, effect lighting, and point lights. The particle color is the vertex color
and alpha. OpenSky always applies it, also when the shader's vertex flags are off, because the
color modifier and the birth and death fade live there. In the vanilla files with particle
systems, 1292 soft effect shaders set vertex colors without vertex alpha. It is not known
whether the game then drops the particle alpha. A playback takes its reference's `XEMI`
emittance for external emittance. Fog takes the light away from an additive system instead of mixing
in the fog color, because the sum already shows the fogged scene behind it.

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

## Ribbons

Some systems draw bands instead of squares. A band joins two points. Its width is set at each
end, and it turns about its own length to face the eye. The bands use the same effect shading,
blend pipelines, and depth rules as the squares, and the same instance layout: the start point
and width, the end point and width, the colour, and the texture coordinate along the band.

| System | Bands |
| --- | --- |
| Lightning controller | A grown bolt; see below |

A `BSProceduralLightningController` sits on an empty shape. nif.xml names its fields but not
how the bolt is built, so this is OpenSky's reading:

- The main bolt runs from the shape's origin along its +Y for the length, plus or minus the
  length variation. The vanilla `lightningbolt01.nif` has its `BeamEnd` node 512 units
  along +Y, the same as its length field.
- The bolt is halved `subdivisions` times (at most 8). Each new middle point moves sideways,
  in the shape's XZ plane, by up to the arc offset, and by half as much at each next level.
- `branches` plus or minus `branch variation` child bolts start at a random point on the
  main bolt, lean up to about 30 degrees away from it, and are 0.3 to 0.5 of its length.
  They are halved two times fewer, bend half as far, and are `child width multiplier` times
  as wide.
- With "fade main bolt" or "fade child bolts" set, a bolt narrows and fades to nothing at
  its far end.
- Every 0.1 s a new bolt grows from a new seed, and the drawn bolt blends from one to the
  next, so it crawls instead of jumping.

The texture runs along the band in U. The interpolators of the vanilla bolts are blend
interpolators that no sequence keys, so the fields are used as stored.

## Mesh particles

An `NiMeshParticleSystem` draws the meshes of its pool node at each live particle, as an
effect placement, instead of a square. Each particle turns by its rotation angle about its
own axis: the rotation modifier's axis, or with random axis set, a random axis chosen at
birth. The particle size scales the mesh. A placed (cell) mesh particle system still draws
squares.

## Emitters on moving nodes

A system knows the names of the nodes above it. When an effect model or a placed mesh moves
a node, by a controller, a lag bone, or its effect graph, a system below that node emits
where the node is now. The inherit velocity modifier names an inherit object; a new particle
takes that node's velocity, such as a weapon tip's, not the system's.

## Wind

The renderer publishes the blended weather wind, and every live frame passes it to the active
`BSWind` modifiers. Calm or no weather is zero. The far-to-near sort is the player setting
`rendering.particleSorting`, which the launcher's Graphics page shows.

## Not done

- Switching sequences on animation events.
- Collision and splashes for precipitation, which uses this path ([precipitation](/rendering/precipitation.md)).
