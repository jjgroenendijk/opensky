---
type: File Format
title: NIF particle systems (Skyrim SE)
description: NiParticleSystem, NiPSysData, emitter and modifier blocks, and how OpenSky
  builds a particle system from them.
tags: [format, mesh, particles, io]
---

# NIF particle systems

This page covers the particle blocks inside a [NIF](/formats/nif.md) file: how many
particles, the emitter shape, the modifiers, and the shader and alpha links. See
[particle playback](/rendering/particles.md) for the simulation.

Reference: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml):
`NiGeometry`, `NiParticles`, `NiParticleSystem`, `BSStripParticleSystem`, `NiGeometryData`,
`NiParticlesData`, `NiPSysData`, `BSStripPSysData`, `NiPSysModifier`, `NiPSysEmitter`,
`NiPSysVolumeEmitter`, and the emitter and modifier blocks. NifSkope was used to view real
files. All integers are little-endian.

## Version conditions

Skyrim files are version 20.2.0.7, user version 12. The Bethesda stream (BS) is 100 for
Skyrim SE, or 83 for the original Skyrim. Some vanilla Skyrim SE files still use 83.
`nif.xml` has separate rows per stream. These tokens decide the layout:

| Token | Condition | Stream 83 | Stream 100 |
| --- | --- | --- | --- |
| `#BS202#` | version 20.2 and BS > 0 | yes | yes |
| `#BS_GTE_SSE#` | BS >= 100 | no | yes |
| `#NI_BS_LT_SSE#` | BS < 100 | yes | no |
| `#BS_GTE_SKY#` | BS >= 83 | yes | yes |
| `#BS_GT_FO3#` | BS > 34 | yes | yes |

So `NiPSysData` is the same for both Skyrim streams. The `NiGeometry` part of
`NiParticleSystem` differs.

## NiParticleSystem and BSStripParticleSystem

The chain is `NiAVObject -> NiGeometry -> NiParticles -> NiParticleSystem`.
`BSStripParticleSystem` adds no fields. Both start with the shared `NiAVObject` fields (see
[NIF](/formats/nif.md)): name, extra data refs, controller ref, flags, translation, 3x3
rotation, scale, collision ref.

The `NiGeometry` part on stream 100:

| Field | Type | Bytes | Used |
| --- | --- | --- | --- |
| Bounding Sphere | NiBound | 16 | no |
| Skin | Ref | 4 | no |
| Shader Property | Ref | 4 | yes |
| Alpha Property | Ref | 4 | yes |

The `NiGeometry` part on stream 83:

| Field | Type | Bytes | Used |
| --- | --- | --- | --- |
| Data | Ref | 4 | yes |
| Skin Instance | Ref | 4 | no |
| Material Data | MaterialData | varies | no |
| Shader Property | Ref | 4 | yes |
| Alpha Property | Ref | 4 | yes |

`MaterialData` (version 20.2.0.7) is a uint32 count, then that many 8-byte pairs
(`NiFixedString` name, int32 extra data), then an int32 active material and a one-byte
"needs update" flag.

Then the `NiParticleSystem` fields:

| Field | Type | Stream 83 | Stream 100 |
| --- | --- | --- | --- |
| Vertex Desc | BSVertexDesc | absent | 8 bytes |
| Far/Near | 4 x uint16 | 8 bytes | 8 bytes |
| Data | Ref to `NiPSysData` | absent | 4 bytes |
| World Space | bool | 1 byte | 1 byte |
| Num Modifiers | uint32 | 4 bytes | 4 bytes |
| Modifiers | N x Ref | 4N | 4N |

The link to `NiPSysData` is `NiGeometry` Data on stream 83 and `NiParticleSystem` Data on
stream 100.

## NiPSysData and BSStripPSysData

The chain is `NiObject -> NiGeometryData -> NiParticlesData -> NiPSysData`. It is the same
on both streams. Under `#BS202#`, the per-particle arrays (positions, normals, colors, UVs,
sizes, rotations) have no data on disk. The game creates them at runtime. Only their "has"
flags and the fixed values are stored. In order:

- `NiGeometryData`: Group ID (int32), BS Max Vertices (uint16, the particle capacity), Keep
  and Compress flags (2 bytes), Has Vertices (bool), BS Data Flags (uint16), Material CRC
  (uint32), Has Normals (bool), Bounding Sphere (NiBound, 16 bytes), Has Vertex Colors
  (bool), Consistency Flags (uint16), Additional Data (Ref).
- `NiParticlesData`: Has Radii (bool), Num Active (uint16), Has Sizes (bool), Has Rotations
  (bool), Has Rotation Angles (bool), Has Rotation Axes (bool), Has Texture Indices (bool),
  Num Subtexture Offsets (uint32), Subtexture Offsets (N x Vector4, the atlas rectangles
  for `BSPSysSubTexModifier`), Aspect Ratio (float32), Aspect Flags (uint16), Speed to
  Aspect (3 x float32).
- `NiPSysData`: Has Rotation Speeds (bool).
- `BSStripPSysData` adds: Max Point Count (uint16), Start Cap Size (float32), End Cap Size
  (float32), Do Z Prepass (bool).

## Modifiers and emitters

Every `NiPSysModifier` starts with: Name (string ref), Order (uint32), Target (Ptr), Active
(bool).

Every `NiPSysEmitter` then adds the birth values: speed, speed variation, declination,
declination variation, planar angle, planar angle variation (6 x float32), initial color
(RGBA float32), initial radius, radius variation, life span, life span variation
(5 x float32).

A `NiPSysVolumeEmitter` (box, cylinder, sphere) then adds an Emitter Object Ptr and its
shape values. The mesh emitter comes straight from `NiPSysEmitter`, with no Emitter Object.

Blocks OpenSky reads:

- Emitters: `NiPSysBoxEmitter` (width, height, depth), `NiPSysCylinderEmitter` (radius,
  height), `NiPSysSphereEmitter` (radius), `NiPSysMeshEmitter` (see below).
- `NiPSysPositionModifier` has no fields. It moves each particle by its velocity, which
  the simulation always does.
- Modifiers with values: `BSWindModifier` (strength), `BSPSysScaleModifier` (scale list),
  `BSPSysLODModifier` (begin and end distance, end emit scale, end size).
- Age death, spawn, gravity, rotation, bound update, drag, inherit velocity, and sub-texture:
  see [Parameter modifiers](#parameter-modifiers).
- `BSPSysSimpleColorModifier`: fade in, fade out, colour 1 end, colour 2 start, colour 2
  end, colour 3 start (6 x float32, each a fraction of the particle's life), then three
  RGBA colours (12 x float32). A particle holds colour 1, blends to colour 2, holds it, then
  blends to colour 3. Alpha also ramps up over the fade-in and down over the fade-out.
  Example: `fxfirewithembers01.nif` smoke stores 0.1, 0.45, 0.46, 1.0 as its stops and peaks
  at alpha 0.4 in colour 2, so it never draws opaque.

### NiPSysMeshEmitter

After the `NiPSysEmitter` fields: a uint32 mesh count, that many `Ptr` refs to the emitter
shapes, then `VelocityType` (uint32: 0 normals, 1 random, 2 the emission axis), `EmitFrom`
(uint32: 0 vertices, 1 face centre, 2 edge centre, 3 face surface, 4 edge surface), and the
emission axis (Vector3).

OpenSky reads the positions, normals and triangles of each `BSTriShape`,
`BSSubIndexTriShape` or `BSDynamicTriShape` the refs name. It moves them into the particle
system's space with the shape's scene graph transform. A skinned shape uses its bind pose.
At most 65,536 vertices are kept per emitter.

## Emitter controllers

The particle system's controller ref starts a chain of `NiTimeController` blocks, linked by
"Next Controller". OpenSky reads each `NiPSysEmitterCtlr` and
`BSPSysMultiTargetEmitterCtlr` as below, and the other particle controllers in
[Parameter controllers](#parameter-controllers). In version 20.2.0.7 its fields are:

| Field | Type | Bytes |
| --- | --- | --- |
| Next Controller | Ref | 4 |
| Flags | uint16 | 2 |
| Frequency, Phase, Start Time, Stop Time | 4 x float32 | 16 |
| Target | Ptr | 4 |
| Interpolator (birth rate) | Ref | 4 |
| Modifier Name | string index | 4 |
| Visibility Interpolator (emitter on or off) | Ref | 4 |

Flags bits 1 and 2 are the cycle: 0 loop, 1 reverse, 2 clamp. The modifier name matches
the emitter's name.

- The birth rate is an `NiFloatInterpolator`: a float32 pose value, then a ref to
  `NiFloatData`. `NiFloatData` is a `KeyGroup<float>`: a uint32 count, a uint32 key type
  when the count is not zero, then keys of time and value. Quadratic keys add two floats
  and TBC keys add three. The pose value -3.402823466e+38 means "unset".
- The on/off track is an `NiBoolInterpolator` or `NiBoolTimelineInterpolator`: a pose
  byte (2 means unset), then a ref to `NiBoolData`, a `KeyGroup<byte>`.
- A blend interpolator gives no keys. A controller with flags bit `0x20` set is driven by
  an `NiControllerManager`, and its keys come from a sequence instead (below).

`BSPSysMultiTargetEmitterCtlr` is an `NiPSysEmitterCtlr` with two more fields: `Max Emitters`
(uint16) and `Master Particle System` (Ptr). OpenSky reads it like `NiPSysEmitterCtlr` and
ignores the two fields.

## Controller manager sequences

An `NiControllerManager` lists `NiControllerSequence` blocks. Each sequence names, per
controller, the interpolator that feeds it. Layout for 20.2.0.7, BSVER 100, from nif.xml
`NiSequence` and `NiControllerSequence`:

| Field | Type | Bytes |
| --- | --- | --- |
| Name | string index | 4 |
| Num Controlled Blocks | uint32 | 4 |
| Array Grow By | uint32 | 4 |
| Controlled Blocks | 29 bytes each | 29 x n |
| Weight | float32 | 4 |
| Text Keys | Ref | 4 |
| Cycle Type | uint32 | 4 |
| Frequency, Start Time, Stop Time | 3 x float32 | 12 |
| Manager | Ptr | 4 |
| Accum Root Name | string index | 4 |
| Num Anim Note Arrays, then refs | uint16, Ref x n | 2 + 4 x n |

A controlled block is an interpolator Ref, a controller Ref, a priority byte, then five
string indices: node name, property type, controller type, controller ID, and interpolator
ID. For an emitter controller the interpolator ID is `BirthRate` (an `NiFloatInterpolator`)
or `EmitterActive` (an `NiBoolInterpolator`). Their layout is the same as above.

Checked on the vanilla install: 525 of 912 particle NIFs hold sequences, and 142 use
`BSPSysMultiTargetEmitterCtlr`. Every controller with flags bit `0x20` has a sequence that
feeds it. Cycle types are 0 (loop) or 2 (clamp). Common emitter sequence names are `mIdle`,
`Waiting`, `mBegin`, `mLoop`, and `mEnd`.

A NIF does not say which sequence plays first; the game starts them from animation events.
OpenSky's pick is in [particle playback](/rendering/particles.md).

## Parameter modifiers

Each layout follows the modifier header. `bool` is one byte.

| Block | Fields |
| --- | --- |
| `NiPSysAgeDeathModifier` | bool spawn on death, spawn modifier Ref |
| `NiPSysSpawnModifier` | uint16 generations, float32 percentage, uint16 minimum and maximum count, float32 speed variation, direction variation, life span, life span variation |
| `NiPSysGravityModifier` | gravity object Ptr, Vector3 axis, float32 decay, strength, uint32 force type (0 planar, 1 spherical), float32 turbulence, turbulence scale, bool world aligned |
| `NiPSysRotationModifier` | float32 speed, speed variation, angle, angle variation, bool random speed sign, bool random axis, Vector3 axis |
| `NiPSysBoundUpdateModifier` | uint16 update skip |
| `NiPSysDragModifier` | drag object Ptr, Vector3 axis, float32 percentage, range, range falloff |
| `BSPSysInheritVelocityModifier` | inherit object Ptr, float32 chance, multiplier, variation |
| `BSPSysSubTexModifier` | float32 start frame, start frame fudge, end frame, loop start frame, loop start frame fudge, frame count, frame count fudge |

What OpenSky does with them. nif.xml names the fields but not their exact effect, so the
items marked "inferred" are OpenSky's reading, not confirmed against the game:

- Gravity. A planar pull adds `axis * strength` to the velocity each second. A spherical
  pull points at the gravity object and fades by `exp(-decay * distance)` (inferred). The
  axis turns with the gravity object unless the modifier is world aligned. Turbulence adds a
  random push of up to `turbulence * turbulenceScale` per second on each axis (inferred).
- Drag. A particle within `range` of the drag object, measured along the axis, loses
  `percentage` of its speed each 1/30 second (inferred). Past the range the drag fades to
  none over `rangeFalloff`. Vanilla ranges are `FLT_MAX`, so the drag applies everywhere.
- Rotation. Each particle starts at the angle plus or minus its variation, and spins at the
  speed plus or minus its variation. With random speed sign, half spin the other way. The
  billboard turns in the screen plane; the axis is ignored, because a billboard has one
  free turn.
- Sub-texture. A particle picks its start frame, loop start frame, and frame count, each
  plus up to its fudge at random (inferred). It plays the frame count over its life. Past
  the end frame it goes back to the loop start frame. The frames index the subtexture
  offsets of `NiPSysData`.
- Inherit velocity. A new particle in a world-space system takes, with the given chance in
  percent, the emitter's velocity times the multiplier plus or minus the variation. OpenSky
  uses the velocity of the particle system, not of the inherit object.
- Age death and spawn. A particle dies at the end of its life. With spawn on death set, it
  first spawns children that start at its place and speed. A particle spawns while its
  generation is at most the generation count, so a count of 0 spawns once (inferred). On the
  install, every age death modifier has spawn on death off, so no vanilla particle spawns.
- Bound update. The skip count is read and shown in the mesh preview. OpenSky does not cull
  particle systems by their bound.
- `NiPSysGravityStrengthCtlr` sets the gravity strength, and `NiPSysInitialRotSpeedCtlr`
  sets the rotation speed of new particles.

Values seen on the install: gravity uses both force types and every one names an object.
Drag percentages are 0.02 to 0.1 on the x, y, or z axis. Inherit chances are 50 to 100,
multipliers 0.05 to 1. The rotation modifiers sampled set random axis, with axis (1, 0, 0).
Sub-texture examples, as start, start fudge, end, loop start, loop fudge, count, count
fudge: (0, 4, 3, 0, 0, 30, 10) and (0, 64, 63, 0, 0, 256, 0).

## Parameter controllers

These controllers animate one value of the emitter or modifier their name matches. Each is
an `NiSingleInterpController` (time controller fields, interpolator Ref), then the
modifier name (string index). The interpolator is an `NiFloatInterpolator`, or an
`NiBoolInterpolator` for `NiPSysModifierActiveCtlr`; a manager-controlled one gets its keys
from the sequence, as above.

| Controller | Value it sets |
| --- | --- |
| `NiPSysModifierActiveCtlr` | The modifier or emitter is on or off |
| `NiPSysEmitterSpeedCtlr` | Emitter speed |
| `NiPSysEmitterInitialRadiusCtlr` | Emitter initial radius |
| `NiPSysEmitterLifeSpanCtlr` | Emitter life span |
| `NiPSysEmitterDeclinationCtlr` | Emitter declination |
| `NiPSysEmitterPlanarAngleCtlr` | Emitter planar angle |
| `NiPSysGravityStrengthCtlr` | Gravity strength |
| `NiPSysInitialRotSpeedCtlr` | Rotation modifier speed |

`NiVisController` on a particle system (an `NiSingleInterpController` with a bool
interpolator) hides the whole system while its keys say off. `NiPSysUpdateCtlr` has only
the time controller fields. A system whose controller chain holds no `NiPSysUpdateCtlr`
does not step its particles. A system with no controller chain at all steps anyway, so
synthetic test meshes keep working.

## Force modifiers

| Block | Fields after the `NiPSysModifier` part |
| --- | --- |
| `NiPSysBombModifier` | Bomb object Ptr, axis (Vector3), decay, delta V (float32), decay type, symmetry type (uint32) |
| `NiPSysColliderManager` | First collider Ref |
| `BSPSysRecycleBoundModifier` | Offset (Vector3), extent (Vector3), bound object Ptr |
| `BSPSysStripUpdateModifier` | Update interval in seconds (float32) |

A collider (`NiPSysPlanarCollider`, `NiPSysSphericalCollider`) is not a modifier. It is a
bounce factor (float32), spawn on collide and die on collide (bool each), then Refs to a
spawn modifier, the manager, the next collider, and the collider object. A planar collider
adds width, height (float32), and its X and Y axes (Vector3 each); a spherical one adds a
radius. The colliders of a manager form a chain by their next refs.

Each object Ptr names a node; OpenSky places the bomb or collider at that node's origin in
the system's space, and the simulation moves it to the world with the system. Semantics:

- Bomb: a push of `delta V` per second away from the bomb (negative pulls). Spherical
  pushes away from the point, cylindrical away from the axis line, planar along the axis
  on each side. The push fades with no decay (1), linear decay (`1 - d / decay`), or
  exponential decay (`exp(-d / decay)`).
- Collider: a particle that crosses the plane rectangle, or enters the sphere, either dies
  or stops at the surface. Its speed into the surface turns back, times the bounce factor.
  Spawn on collide is not done; no vanilla collider sets it.
- Recycle bound: a particle that leaves the box comes back in on the other side, so a
  system that follows the camera keeps the view filled. OpenSky reads the offset as the
  box's lowest corner and the extent as its full size, measured from the bound object.
  Vanilla stores offset (-391, -250, 0) with extent (782, 500, 695), which fits that
  reading, but it is not confirmed in the game.

Strip particle systems draw as billboards, so the strip update interval reaches only the
mesh preview.

## Mesh particles

`NiMeshParticleSystem` has the `NiParticleSystem` layout. Its data, `NiMeshPSysData`, is an
`NiPSysData`, then a uint32 default pool size, a fill-pools-on-load bool, a uint32 count of
uint32 generation pool sizes, and a Ref to the node whose children are the particle meshes.
`NiPSysMeshUpdateModifier` holds a Ref list of meshes; `BSPSysHavokUpdateModifier` adds a
Ref to a modifier it drives. On the install, only
`effects\dragoncrash\fxdragoncrashfurrow01.nif` uses them: three systems whose particles
are rock `NiTriShape` meshes. OpenSky simulates these systems like the others and draws
billboards; drawing the rock meshes per particle is not done.

## Not read

- Skin and material data. Particles do not need them.
- Shader properties other than `BSEffectShaderProperty`. For example, a lit particle
  system that uses `BSLightingShaderProperty` gets its material from the mesh material path.
- An unknown modifier type is marked unsupported and skipped. Vanilla has none. Broken
  bytes inside a known block are an error, and the caller skips the file.

## From scene graph to particle system

OpenSky walks the scene graph from the footer roots, the same way as for meshes (see
[NIF](/formats/nif.md)). It adds up the `NiNode` transforms, stops at depth 64, and stops
on loops. Each `NiParticleSystem`, `BSStripParticleSystem`, or `NiMeshParticleSystem`
becomes one particle system
with its world transform, capacity, emitters, modifiers, effect shader, and alpha
property.

All vanilla effect NIFs checked (109 files, 216 systems) decode without errors. In
Whiterun, every particle system has an effect shader and an alpha property.
