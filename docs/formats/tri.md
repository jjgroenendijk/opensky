---
type: File Format
title: FaceGen TRI expression container
description: FRTRI003 layout, named morph targets, and how a face mesh finds its TRI through
  HDPT records.
tags: [format, tri, facegen, morph, expression, hdpt]
---

# FaceGen TRI expression container

A `.tri` file holds morph targets for a head part. A morph target is a set of vertex
offsets, for example `Aah` for an open mouth. Skyrim's facial expressions use `FRTRI003`
files. OpenSky reads the base mesh shape and the named morph targets. It checks and skips
the character-creation modifier tables, the modifier vertices, and the UV data, because
expressions do not use them.

Sources: NifTools PyFFI
[`tri.xml`](https://github.com/niftools/pyffi/blob/master/pyffi/formats/tri/tri.xml) and
its [`pyffi.formats.tri` decoder](https://github.com/niftools/pyffi/blob/master/pyffi/formats/tri/__init__.py)
for the file. xEdit dev-4.1.6
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
for the record links.

## Header

All integers are little-endian. The header is 64 bytes.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | char[5] | `FRTRI` |
| 0x05 | char[3] | Version, `003` |
| 0x08 | int32 | Base vertex count |
| 0x0C | int32 | Triangle count |
| 0x10 | int32 | Quad count |
| 0x14 | int32 | Unknown count, used only to find later data |
| 0x18 | int32 | Unknown count, used only to find later data |
| 0x1C | int32 | UV count |
| 0x20 | int32 | Has UV, 0 or 1 |
| 0x24 | int32 | Morph target count |
| 0x28 | int32 | Modifier count |
| 0x2C | int32 | Modifier vertex count |
| 0x30 | int32[4] | Reserved or unknown |

A negative count, a UV flag other than 0 or 1, another version, or counts that need more
bytes than the file has, make the file malformed.

## Body

The body follows the counts in this order:

1. Base vertices: `vertexCount` x 3 float32.
2. Modifier vertices: `modifierVertexCount` x 3 float32.
3. Triangles: `triangleCount` x 3 uint32 vertex indices.
4. Quads: `quadCount` x 4 uint32 vertex indices.
5. UVs: `uvCount` x 2 float32.
6. If has UV is 1: triangle and quad UV indices, in the same shapes as steps 3 and 4.
7. Named morph targets.
8. Character-creation modifiers.

Every vertex, UV, and scale must be a finite number. Every index must be below its vertex
count. The body must end exactly at the end of the file. Extra bytes make it malformed.

## Named morph target

| Type | Meaning |
| --- | --- |
| uint32 | Length of the name, with its null byte |
| char[length] | UTF-8 name, ending with a null byte |
| float32 | Scale |
| `int16[vertexCount][3]` | Position offsets |

The offset of a vertex is `Float(component) * scale`. A target has one offset for every
base vertex. It is not sparse. An empty name, bad UTF-8, a missing null, a scale that is not
finite, or too few offset bytes make the target invalid.

## How a face finds its TRI

The face `.nif` does not store the `.tri` path. OpenSky finds it through records:

1. Take the head parts from the race (`RACE`, per gender) and from the NPC (`NPC_ PNAM`).
2. Read each head part's (`HDPT`) `EDID` and its `NAM0` and `NAM1` pairs.
3. Pick the pair with `NAM0 = 1`, which xEdit calls the expression TRI. `NAM0 = 0` is the
   race morph and `NAM0 = 2` is the character-creation morph.
4. `NAM1` is relative to `Data/Meshes`, so add `meshes\` in front.
5. Match the `HDPT` `EDID` to the `BSDynamicTriShape` name in the face mesh, ignoring case.
6. The shape must be skinned, and its vertex count must equal the TRI vertex count.

Each failure has its own reason, so the UI can say why a face part has no expressions.

Vanilla examples:

| `HDPT` editor ID | TRI | Vertices |
| --- | --- | ---: |
| `MaleHeadNord` | `MaleHead.tri` | 898 |
| `FemaleHeadNord` | `FemaleHead.tri` | 996 |
| `MaleMouthHumanoidDefault` | `MouthHuman.tri` | 141 |
| `FemaleMouthHumanoidDefault` | `MouthHumanF.tri` | 141 |

See [face morph runtime](/engine/face-morphs.md) for how the offsets reach the GPU.
