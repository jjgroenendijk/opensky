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
system. Decoding is on the [NIF particle systems](../formats/nif-particles.md) page. The meaning of
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
Until something plays a sequence, OpenSky plays one default sequence per controller, chosen
among the sequences that feed it: the first whose name ends in `idle` (any case), else the
first loop, else the first. This is an OpenSky policy, not a value read from the game. A
controller with no keys in that sequence keeps its own keys.

## Sequences

An effect model's behaviour graph plays a NIF sequence with a `BGSGamebryoSequenceGenerator`
([effect graphs](../engine/effect-graphs.md)). The hand effects of spells, for example, run
`Magic\CastingBasic.hkx`, whose states play `mIntro`, `mCharge`, `mReady`, and `mCast`. The
graph moves between these states on the actor's animation events, such as
`MLh_SpellFire_Event`.

Each particle system keeps its controllers as every sequence feeds them. When the graph plays a
sequence that feeds the system, the system switches to those keys and timing and starts them
from 0. The living particles stay. A controller the sequence does not feed keeps its
default-sequence keys. A sequence that feeds none of the system's controllers changes nothing.

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
([effect shapes](../formats/nif-materials.md#effect-shapes)): the system's base color, palette,
falloff, soft effect, effect lighting, and point lights. The particle color is the vertex color
and alpha. An effect shader takes it only when its `Vertex_Colors` flag (SLSF2 bit 5) is on:

| `Vertex_Colors` | `Vertex_Alpha` | A particle's own color and alpha |
| --- | --- | --- |
| on | on or off | Both apply, so the particle fades at birth and death |
| off | on or off | Both are dropped: the particle keeps the shader's color at full alpha |

The `Vertex_Alpha` flag (SLSF1 bit 3) changes nothing for an effect shader, on a particle
system or on a plain shape. A strip particle system always takes its color and alpha. So the
1292 vanilla soft effect shaders on particle systems that set vertex colors without vertex
alpha still fade. A playback takes its reference's `XEMI`
emittance for external emittance. Fog takes the light away from an additive system instead of mixing
in the fog color, because the sum already shows the fogged scene behind it.

| NIF source and destination | Pipeline | Used for |
| --- | --- | --- |
| `SRC_ALPHA`, `ONE` (6 and 0) | Additive | Flame, sparks, glow |
| `ONE`, `ONE` (0 and 0) | Additive one | Full-color glow |
| `DEST_COLOR`, `ZERO` (4 and 1) | Multiply | Modulation effects |
| Anything else, or none | Alpha | Smoke, steam, water |

The alpha pipeline blends in linear light, unlike blended meshes
([blending](image-space.md#blending)).

Placed and effect systems draw far to near, by the distance from the camera to the emitter
origin. Inside an alpha or multiply system, the particles also draw far to near. Additive
systems are not sorted inside, because a sum does not depend on order. Rain and snow follow
the camera and draw last.

## Ribbons

Some systems draw bands instead of squares. A band joins two points. Its width is set at each
end, and it turns about its own length to face the eye. A [lightning](#lightning) bolt uses the
same bands with a fixed side direction. The bands use the same effect shading,
blend pipelines, and depth rules as the squares, and the same instance layout: the start point
and width, the end point and width, the colour, and the texture coordinate along the band.

| System | Bands |
| --- | --- |
| `BSStripParticleSystem` | One band through its particles in birth order, oldest first |
| Rain | Each drop stretched along its velocity ([precipitation](precipitation.md#streaks)) |

A strip's texture runs from its oldest end, U 0, to its newest, U 1. A rain streak's
texture runs along the band in V, because the generated streak mask is tall. A strip
system's particles are not sorted, because the band joins them in birth order.

## Lightning

A `BSProceduralLightningController` grows a lightning bolt. Its target is a node. The first
shape below that node is empty and hidden in the file: the controller fills it and shows it.
The bolt sits at that shape and takes its effect shader and alpha property. nif.xml names the
controller's fields; the rules below say how the game builds the bolt from them.

### The tree

A bolt is a tree. The main bolt has depth 0. Each child is one step deeper than its parent.

| Value at depth d | Rule |
| --- | --- |
| Segments | 2 to the power of the subdivisions; a child has one subdivision less |
| Length | `0.5^d x length + 0.25^d x r x length variation`, with r random in -1 to 1 |
| Width | `child width multiplier^d x width`, the same along the whole bolt |
| Arc size | `0.5^d x arc offset` |
| Branch count and variation | Halved at each depth, rounded down |

A bolt gets its branch count of children, plus or minus a random part of the branch
variation. A bolt with a branch count of 0, or with no subdivisions left, gets none, so the
tree ends there.

Every bolt runs along the shape's +Y. A child runs parallel to its parent. It starts at the
middle of a random segment in the first half of the parent.

The points of a bolt move sideways only, in the shape's XZ plane, by midpoint displacement:
the middle point moves by the arc size in a random direction, then each half does the same
with half the size. Both ends stay in place.

For example, a main bolt with 3 subdivisions, length 512, width 16, 2 branches, and a child
width multiplier of 0.5 has 8 segments. Each of its 2 children has 4 segments, is 256 long
and 8 wide, and has 1 child of its own with 2 segments, 128 long and 4 wide.

### The mesh

Each bolt is two flat ribbons that cross along the bolt, one wide in the shape's X and one
wide in its Z. They do not turn to the eye. The texture's V runs from 0 at the start of the
bolt to 1 at its end.

The vertex alpha is 0 at the far end of every bolt and at the start of the main bolt. With
"fade main bolt" or "fade child bolts" set, the alpha of a point i of n segments is
`1 - i^2 / n^2`. Without the flag it is 1 between the ends.

### Time

Tracks decide when the bolt changes. They come from the controller sequence in play, by
interpolator ID, or from the controller's own interpolators when no sequence feeds it.

| Track | Effect |
| --- | --- |
| `Generation` (bool) | The bolt shows only while it is on. Each change to on grows a new random tree |
| `Mutation` (bool) | Each change gives the same tree new lengths and bends |
| `ArcOffset` (float) | With the "animate arc offset" flag, the arc size follows it; without the flag nothing moves between mutations |
| `Length`, `Width` (float) | Replace the stored field |

A controller that no generation track feeds builds nothing.

The 12 vanilla meshes with a lightning controller, such as `meshes\magic\lightningbolt01.nif`,
feed only these five IDs (`openskycli nif <path> --controllers` lists them). Their `mIdle`
sequence holds the generation on with one key and flips the mutation several times a second.
The meshes with `mBegin`, `mLoop`, and `mEnd` key the generation only in `mBegin`; the other two
leave every track unset.

OpenSky's own choices here:

- A sequence that leaves the generation unset keeps the bolt as the sequence before left it:
  shown or hidden, with the same tree and the same track values.
- Before an effect graph plays a sequence, the bolt follows the default sequence, picked among
  the sequences that key the generation ([sequences](#sequences)).
- The other four values (subdivisions, branches, branch variation, length variation) have no
  interpolator ID in the vanilla files, so only the controller's own interpolators can key
  them.
- One bolt tree draws at most 2,048 quads. A bolt with more segments than fit is drawn with
  fewer segments.

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

- Sequences of placed objects: an object's graph does not play them yet
  ([object animation](../engine/object-animation.md#where-opensky-differs)).
