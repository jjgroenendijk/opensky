---
type: File Format
title: NIF particle systems (Skyrim SE)
description: NiParticleSystem, NiPSysData, and the emitter/modifier blocks, and how OpenSky statically decodes them.
tags: [format, mesh, particles, io]
timestamp: 2026-07-21T00:00:00Z
---

# NIF particle systems

Static decode of Skyrim particle blocks: capacity, emitter shapes, modifier
chain, shader/alpha refs. No playback — the CPU sim + rendering are a later
milestone. Container + scene graph are [NIF mesh](/formats/nif.md); this page
covers only the particle blocks that hang off it. Impl:
`opensky/Formats/NIF/NIFParticle*.swift`, engine types in
`ParticleSystemDefinition.swift`.

Reference: NifTools `nif.xml`
(<https://github.com/niftools/nifxml/blob/develop/nif.xml>) — `NiGeometry`,
`NiParticles`, `NiParticleSystem`, `BSStripParticleSystem`, `NiGeometryData`,
`NiParticlesData`, `NiPSysData`, `BSStripPSysData`, `NiPSysModifier`,
`NiPSysEmitter`, `NiPSysVolumeEmitter`, and the concrete emitter/modifier
blocks. NifSkope as ground-truth viewer. All integers little-endian.

## Version conditions

nif.xml doubles up the particle rows by Bethesda stream. Skyrim assets are file
version 20.2.0.7, user version 12, BS stream 100 (SSE) or 83 (LE — some vanilla
SSE assets remain unconverted). The tokens that drive the layout resolve as:

| token            | expr            | stream 83 | stream 100 |
| ---------------- | --------------- | --------- | ---------- |
| `#BS202#`        | ver 20.2 & BS>0 | yes       | yes        |
| `#BS_GTE_SSE#`   | BS >= 100       | no        | yes        |
| `#NI_BS_LT_SSE#` | BS < 100        | yes       | no         |
| `#BS_GTE_SKY#`   | BS >= 83        | yes       | yes        |
| `#BS_GT_FO3#`    | BS > 34         | yes       | yes        |

So NiPSysData is stream-agnostic within Skyrim (`#BS202#` only), while
NiParticleSystem's NiGeometry section differs by stream (see below).

## NiParticleSystem / BSStripParticleSystem

Inheritance `NiAVObject -> NiGeometry -> NiParticles -> NiParticleSystem`. For
Bethesda 20.2 NiParticles switched to a BSGeometry-style layout, which is why
the NiGeometry rows differ by stream. BSStripParticleSystem appends no fields —
identical layout. Prefix is the shared NiAVObject run
([NIFObjectPrefix](/formats/nif.md)): name, extra-data refs, controller ref,
flags, translation, 3x3 rotation, scale, collision ref.

Stream 100 (SSE) NiGeometry section, after the prefix:

| field           | type            | bytes | kept |
| --------------- | --------------- | ----- | ---- |
| Bounding Sphere | NiBound         | 16    | no   |
| Skin            | Ref             | 4     | no   |
| Shader Property | Ref             | 4     | yes  |
| Alpha Property  | Ref             | 4     | yes  |

Stream 83 (LE) NiGeometry section instead:

| field          | type         | bytes    | kept |
| -------------- | ------------ | -------- | ---- |
| Data           | Ref          | 4        | yes  |
| Skin Instance  | Ref          | 4        | no   |
| Material Data  | MaterialData | variable | no   |
| Shader Property| Ref          | 4        | yes  |
| Alpha Property | Ref          | 4        | yes  |

MaterialData (version 20.2.0.7) = `Num Materials` uint32, then that many
`(NiFixedString name, int extra-data)` 8-byte pairs, then `Active Material`
int32 and a `Material Needs Update` byte.

Then the NiParticleSystem fields:

| field         | type           | stream 83 | stream 100 |
| ------------- | -------------- | --------- | ---------- |
| Vertex Desc   | BSVertexDesc   | absent    | 8 bytes    |
| Far/Near      | 4 x ushort     | 8 bytes   | 8 bytes    |
| Data          | Ref NiPSysData | absent    | 4 bytes    |
| World Space   | bool           | 1 byte    | 1 byte     |
| Num Modifiers | uint32         | 4 bytes   | 4 bytes    |
| Modifiers     | Ref x N        | 4N        | 4N         |

The NiPSysData ref comes from NiGeometry.Data on stream 83 and from
NiParticleSystem.Data on stream 100; OpenSky exposes one `dataRef` either way.
Vertex desc, skin, material data, and the LOD cull shorts are read past but not
kept — static decode needs the data ref, world-space flag, shader/alpha refs,
and the modifier ref list.

## NiPSysData / BSStripPSysData

Inheritance `NiObject -> NiGeometryData -> NiParticlesData -> NiPSysData`, read
with `#BS202#` conditions. Under BS202 the geometry + per-particle arrays
(vertices, normals, colors, UVs, radii, sizes, rotations, particle info) carry
no length for NiPSysData — the sim allocates them at runtime — so only their
presence bytes and the fixed scalars are on disk. Layout is identical for
stream 83 and 100. Fields in order:

NiGeometryData: Group ID (int32), BS Max Vertices (ushort — the particle
capacity), Keep + Compress flags (2 bytes), Has Vertices (bool), BS Data Flags
(ushort), Material CRC (uint32), Has Normals (bool), Bounding Sphere (NiBound,
16), Has Vertex Colors (bool), Consistency Flags (ushort), Additional Data
(Ref).

NiParticlesData: Has Radii (bool), Num Active (ushort), Has Sizes (bool), Has
Rotations (bool), Has Rotation Angles (bool), Has Rotation Axes (bool), Has
Texture Indices (bool), Num Subtexture Offsets (uint32), Subtexture Offsets
(Vector4 x N — UV atlas quads for BSPSysSubTexModifier), Aspect Ratio (float),
Aspect Flags (ushort), Speed-to-Aspect trio (3 floats).

NiPSysData: Has Rotation Speeds (bool). BSStripPSysData appends Max Point Count
(ushort), Start Cap Size (float), End Cap Size (float), Do Z Prepass (bool).

OpenSky keeps `maxParticles` (BS Max Vertices), the presence flags, and the
subtexture offsets; the arrays are the sim's job.

## Modifiers + emitters

Every NiPSysModifier subclass starts with a shared base run: Name (string ref,
resolved lenient like NiObjectNET), Order (NiPSysModifierOrder uint32), Target
(Ptr, skipped), Active (bool). Every NiPSysEmitter subclass then adds a
birth-parameter run: speed, speed variation, declination, declination
variation, planar angle, planar angle variation (6 floats), initial color
(Color4 RGBA), initial radius, radius variation, life span, life span variation
(5 floats). NiPSysVolumeEmitter (box/cylinder/sphere) then adds an Emitter
Object Ptr (skipped) and its shape params; the mesh emitter inherits
NiPSysEmitter directly (no volume ptr).

Decoded blocks:

- Emitters: NiPSysBoxEmitter (width/height/depth), NiPSysCylinderEmitter
  (radius/height), NiPSysSphereEmitter (radius), NiPSysMeshEmitter (mesh refs +
  VelocityType uint32; geometry sampling deferred).
- Modifiers kept by identity: NiPSysAgeDeathModifier, NiPSysSpawnModifier,
  NiPSysRotationModifier, NiPSysPositionModifier, NiPSysBoundUpdateModifier,
  NiPSysDragModifier, BSPSysSimpleColorModifier, BSPSysInheritVelocityModifier,
  BSPSysSubTexModifier.
- Modifiers with a few params: NiPSysGravityModifier (gravity axis, strength),
  BSWindModifier (strength), BSPSysScaleModifier (scale array), BSPSysLODModifier
  (begin/end distance, end emit scale, end size).

## What is skipped + why

- Controllers (NiPSysUpdateCtlr, NiPSysEmitterCtlr, interpolators): animation,
  out of scope, skipped like NiObjectNET already skips controller refs.
- Skin ref / skin instance / material data: skinned particles + legacy material
  metadata are not needed for static decode.
- Shader property blocks: `shaderPropertyRef` / `alphaPropertyRef` are recorded
  as raw block indices (-1 = none) and wired later; BSEffectShaderProperty is
  owned by another subsystem.
- Per-particle arrays: empty under BS202; playback sim allocates them.
- Unknown modifier types -> `.unsupported(typeName:)` (skip + note, never
  throw). Observed in vanilla: NiPSysColliderManager, NiPSysBombModifier,
  BSPSysRecycleBoundModifier, BSPSysStripUpdateModifier. Malformed bytes inside
  a known block throw NIFError so the caller skips the asset.

## Scene graph -> particle system

`NIFFile.particleSystems()` walks from the footer roots exactly like
[NIFModel](/formats/nif.md): accumulate NiNode local transforms down the parent
chain, cap depth at 64, detect ref cycles with a path stack, range-check every
block ref. NiParticleSystem / BSStripParticleSystem leaves become a
`ParticleSystemDefinition` with the accumulated world transform, resolved
capacity, emitter list, modifier list, and the raw shader/alpha refs.

Verified against the vanilla install: 109 effect NIFs decoded (216 systems, 216
emitters, 2347 modifiers) with zero decode failures; the four unmodelled
modifier types above surfaced as `.unsupported`, none threw.
