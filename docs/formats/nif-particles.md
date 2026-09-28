---
type: File Format
title: NIF particle systems (Skyrim SE)
description: NiParticleSystem, NiPSysData, emitter and modifier blocks, and what OpenSky reads.
tags: [format, mesh, particles, io]
---

# NIF particle systems

A NIF file can hold particle systems, for example fire, smoke, or magic effects. This page
covers the particle blocks only. The NIF container and scene graph are on the
[NIF](/formats/nif.md) page. Playback is on the [particles](/rendering/particles.md) page.

Source: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml):
`NiGeometry`, `NiParticles`, `NiParticleSystem`, `BSStripParticleSystem`, `NiGeometryData`,
`NiParticlesData`, `NiPSysData`, `BSStripPSysData`, `NiPSysModifier`, `NiPSysEmitter`,
`NiPSysVolumeEmitter`, and the emitter and modifier blocks. NifSkope was used to view real
files. All integers are little-endian.

## Version conditions

Skyrim files are version 20.2.0.7, user version 12, with Bethesda stream 100 (SSE) or 83
(the original Skyrim). Some vanilla SSE files were never converted and still use stream 83.
`nif.xml` has separate rows for each stream. The tokens resolve like this:

| Token | Expression | Stream 83 | Stream 100 |
| --- | --- | --- | --- |
| `#BS202#` | version 20.2 and BS > 0 | yes | yes |
| `#BS_GTE_SSE#` | BS >= 100 | no | yes |
| `#NI_BS_LT_SSE#` | BS < 100 | yes | no |
| `#BS_GTE_SKY#` | BS >= 83 | yes | yes |
| `#BS_GT_FO3#` | BS > 34 | yes | yes |

So `NiPSysData` is the same in both streams. The `NiGeometry` part of `NiParticleSystem` is
not.

## NiParticleSystem and BSStripParticleSystem

The chain is `NiAVObject -> NiGeometry -> NiParticles -> NiParticleSystem`.
`BSStripParticleSystem` adds no fields. Both start with the shared `NiAVObject` fields (see
[NIF](/formats/nif.md)).

Stream 100, after the `NiAVObject` fields:

| Field | Type | Bytes | Used |
| --- | --- | --- | --- |
| Bounding Sphere | NiBound | 16 | no |
| Skin | Ref | 4 | no |
| Shader Property | Ref | 4 | yes |
| Alpha Property | Ref | 4 | yes |

Stream 83, after the `NiAVObject` fields:

| Field | Type | Bytes | Used |
| --- | --- | --- | --- |
| Data | Ref | 4 | yes |
| Skin Instance | Ref | 4 | no |
| Material Data | MaterialData | varies | no |
| Shader Property | Ref | 4 | yes |
| Alpha Property | Ref | 4 | yes |

`MaterialData` is a uint32 count, then that many 8-byte pairs (string, int32 extra data),
then an int32 active material and one "needs update" byte.

Then the particle system fields:

| Field | Type | Stream 83 | Stream 100 |
| --- | --- | --- | --- |
| Vertex Desc | BSVertexDesc | absent | 8 bytes |
| Far and Near | 4 x ushort | 8 bytes | 8 bytes |
| Data | Ref to NiPSysData | absent | 4 bytes |
| World Space | bool | 1 byte | 1 byte |
| Num Modifiers | uint32 | 4 bytes | 4 bytes |
| Modifiers | Ref x N | 4N | 4N |

The `NiPSysData` link is in `NiGeometry` on stream 83 and in `NiParticleSystem` on stream
100. OpenSky gives one data link either way.

## NiPSysData and BSStripPSysData

The chain is `NiObject -> NiGeometryData -> NiParticlesData -> NiPSysData`. Under `#BS202#`
the per-particle arrays (positions, normals, colors, UVs, sizes, rotations) have no length on
disk. The game allocates them at runtime. Only the "has" flags and fixed values are stored.

`NiGeometryData`: Group ID (int32), BS Max Vertices (ushort, the particle capacity), Keep and
Compress flags (2 bytes), Has Vertices (bool), BS Data Flags (ushort), Material CRC
(uint32), Has Normals (bool), Bounding Sphere (NiBound, 16 bytes), Has Vertex Colors (bool),
Consistency Flags (ushort), Additional Data (Ref).

`NiParticlesData`: Has Radii (bool), Num Active (ushort), Has Sizes (bool), Has Rotations
(bool), Has Rotation Angles (bool), Has Rotation Axes (bool), Has Texture Indices (bool),
Num Subtexture Offsets (uint32), Subtexture Offsets (Vector4 x N, UV rectangles of an atlas
for `BSPSysSubTexModifier`), Aspect Ratio (float), Aspect Flags (ushort), three
speed-to-aspect floats.

`NiPSysData`: Has Rotation Speeds (bool). `BSStripPSysData` adds Max Point Count (ushort),
Start Cap Size (float), End Cap Size (float), Do Z Prepass (bool).

OpenSky keeps the capacity, the flags, and the subtexture offsets.

## Modifiers and emitters

Every `NiPSysModifier` starts with: Name (string ref), Order (uint32), Target (Ptr, skipped),
Active (bool).

Every `NiPSysEmitter` then adds the birth values: speed, speed variation, declination,
declination variation, planar angle, planar angle variation (6 floats), initial color (RGBA),
initial radius, radius variation, life span, life span variation (5 floats).

`NiPSysVolumeEmitter` (box, cylinder, sphere) then adds an emitter object Ptr (skipped) and
its shape values. The mesh emitter comes straight from `NiPSysEmitter`, with no volume Ptr.

Blocks OpenSky reads:

- Emitters: `NiPSysBoxEmitter` (width, height, depth), `NiPSysCylinderEmitter` (radius,
  height), `NiPSysSphereEmitter` (radius), `NiPSysMeshEmitter` (mesh refs and a uint32
  velocity type).
- Modifiers with no values: `NiPSysAgeDeathModifier`, `NiPSysSpawnModifier`,
  `NiPSysRotationModifier`, `NiPSysPositionModifier`, `NiPSysBoundUpdateModifier`,
  `NiPSysDragModifier`, `BSPSysSimpleColorModifier`, `BSPSysInheritVelocityModifier`,
  `BSPSysSubTexModifier`.
- Modifiers with values: `NiPSysGravityModifier` (axis, strength), `BSWindModifier`
  (strength), `BSPSysScaleModifier` (scale list), `BSPSysLODModifier` (begin and end
  distance, end emit scale, end size).

An unknown modifier is recorded by name and skipped, never an error. Vanilla has four:
`NiPSysColliderManager`, `NiPSysBombModifier`, `BSPSysRecycleBoundModifier`,
`BSPSysStripUpdateModifier`. Broken bytes inside a known block are an error, and the mesh is
skipped.

## What is skipped

- Controllers (`NiPSysUpdateCtlr`, `NiPSysEmitterCtlr`, interpolators). Playback uses a fixed
  birth rate until controllers are read.
- Skin and material data.
- Shader properties other than `BSEffectShaderProperty`. A lit particle system that uses
  `BSLightingShaderProperty` keeps the raw link and has no effect shader.

## From the scene graph

OpenSky walks the scene graph from the footer roots, like the mesh path on the
[NIF](/formats/nif.md) page. It multiplies node transforms down the tree, stops at depth 64,
and detects loops. Each `NiParticleSystem` or `BSStripParticleSystem` leaf becomes one
particle system with its world transform, capacity, emitters, modifiers, effect shader, and
`NiAlphaProperty` blend state.

In vanilla, every effect mesh decodes, and every particle system around Whiterun has an
effect shader and an alpha property.
