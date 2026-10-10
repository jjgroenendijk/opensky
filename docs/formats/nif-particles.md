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
- Modifiers known by type only: `NiPSysAgeDeathModifier`, `NiPSysSpawnModifier`,
  `NiPSysRotationModifier`, `NiPSysPositionModifier`, `NiPSysBoundUpdateModifier`,
  `NiPSysDragModifier`, `BSPSysInheritVelocityModifier`, `BSPSysSubTexModifier`.
- Modifiers with values: `NiPSysGravityModifier` (axis, strength), `BSWindModifier`
  (strength), `BSPSysScaleModifier` (scale list), `BSPSysLODModifier` (begin and end
  distance, end emit scale, end size).
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
"Next Controller". OpenSky reads each `NiPSysEmitterCtlr` and passes over the rest, such as
`NiPSysUpdateCtlr`. In version 20.2.0.7 its fields are:

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
- A blend interpolator, which a controller manager feeds, gives no keys. Such a system
  keeps the fallback rate ([particle playback](/rendering/particles.md)).

## Not read

- Skin and material data. Particles do not need them.
- Shader properties other than `BSEffectShaderProperty`. For example, a lit particle
  system that uses `BSLightingShaderProperty` gets its material from the mesh material path.
- Unknown modifier types are marked unsupported and skipped. Vanilla has four:
  `NiPSysColliderManager`, `NiPSysBombModifier`, `BSPSysRecycleBoundModifier`, and
  `BSPSysStripUpdateModifier`. Broken bytes inside a known block are an error, and the
  caller skips the file.

## From scene graph to particle system

OpenSky walks the scene graph from the footer roots, the same way as for meshes (see
[NIF](/formats/nif.md)). It adds up the `NiNode` transforms, stops at depth 64, and stops
on loops. Each `NiParticleSystem` or `BSStripParticleSystem` becomes one particle system
with its world transform, capacity, emitters, modifiers, effect shader, and alpha
property.

All vanilla effect NIFs checked (109 files, 216 systems) decode without errors. In
Whiterun, every particle system has an effect shader and an alpha property.
