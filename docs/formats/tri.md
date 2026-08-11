---
type: File Format
title: FaceGen TRI expression container
description: FRTRI003 topology, named delta targets, HDPT association, and defensive decode
  policy.
tags: [format, tri, facegen, morph, expression, hdpt]
timestamp: 2026-08-11T00:00:00Z
---

# FaceGen TRI expression container

Skyrim's FaceGen expression files are `FRTRI003` containers. OpenSky decodes the base
topology and named morph targets needed for facial expressions. Chargen modifier tables,
absolute modifier vertices, and UV topology are validated and skipped because expression
playback does not consume them.

The format source is NifTools PyFFI
[`tri.xml`](https://github.com/niftools/pyffi/blob/master/pyffi/formats/tri/tri.xml) and its
[`pyffi.formats.tri` decoder](https://github.com/niftools/pyffi/blob/master/pyffi/formats/tri/__init__.py).
The record association source is xEdit dev-4.1.6
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).

## Header

All integers are little-endian. The header is 64 bytes.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | char[5] | `FRTRI` signature |
| 0x05 | char[3] | ASCII version, `003` |
| 0x08 | int32 | base vertex count |
| 0x0C | int32 | triangle count |
| 0x10 | int32 | quad count |
| 0x14 | int32 | unknown count, retained only for framing |
| 0x18 | int32 | unknown count, retained only for framing |
| 0x1C | int32 | UV coordinate count |
| 0x20 | int32 | has-UV flag, zero or one |
| 0x24 | int32 | morph target count |
| 0x28 | int32 | modifier count |
| 0x2C | int32 | modifier vertex count |
| 0x30 | int32[4] | reserved or unknown header words |

Negative counts, a non-Boolean UV flag, unsupported versions, and count-by-stride products
that exceed the remaining bytes are malformed input.

## Body order

The body follows the counts exactly:

1. Base vertices: `vertexCount` triples of Float32.
2. Modifier vertices: `modifierVertexCount` triples of Float32.
3. Triangle faces: `triangleCount` triples of UInt32 vertex indices.
4. Quad faces: `quadCount` groups of four UInt32 vertex indices.
5. UV coordinates: `uvCount` pairs of Float32.
6. When `hasUV` is one, triangle and quad UV-index faces in the same shapes as the vertex
   faces.
7. Named morph records.
8. Chargen modifier records.

Every decoded vertex, UV, and scale must be finite. Every base-topology index must be less
than its vertex count. A successful decode consumes the file exactly; trailing bytes are a
malformed container rather than silently accepted extension data.

## Named morph record

Each expression target contains:

| Type | Meaning |
| --- | --- |
| UInt32 | byte length of the following name, including its NUL terminator |
| char[length] | UTF-8 name with a required terminal NUL |
| Float32 | scale |
| `Int16[vertexCount][3]` | signed position-delta components |

Runtime position delta is `Float(component) * scale`. The record contains one delta for
every base vertex; it is not a sparse target. OpenSky rejects an empty name, invalid UTF-8,
a missing NUL, a non-finite scale, or a target whose delta payload does not fit.

## Association with a baked FaceGen mesh

The `.tri` path is not stored in the FaceGen `.nif`. It is reached through plugin records:

1. Resolve the actor's gendered RACE default head-part list and the NPC_ `PNAM` head parts.
2. Decode each HDPT `EDID` and its paired `NAM0`/`NAM1` values.
3. Select `NAM0 = 1`, which xEdit names the expression TRI. `NAM0 = 0` is the race morph;
   `NAM0 = 2` is the chargen morph.
4. Prefix the HDPT path with `meshes\` because `NAM1` is relative to the Data `Meshes`
   directory, then resolve it through the VFS.
5. Match HDPT `EDID` to the baked FaceGen `BSDynamicTriShape` name without case
   sensitivity.
6. Require a skinned shape and exact TRI/mesh vertex-count equality before binding.

Every failure remains reason-tagged: absent fields, missing shape, missing or malformed TRI,
unskinned shape, and vertex-count mismatch are distinct outcomes.

## Verification

The 2026-08-11 read-only install probe found 569 archive entries ending in `.tri`.
Representative expression containers matched their baked shapes exactly:

| HDPT editor ID | TRI | Vertices |
| --- | --- | ---: |
| `MaleHeadNord` | `MaleHead.tri` | 898 |
| `FemaleHeadNord` | `FemaleHead.tri` | 996 |
| `MaleMouthHumanoidDefault` | `MouthHuman.tri` | 141 |
| `FemaleMouthHumanoidDefault` | `MouthHumanF.tri` | 141 |

Heimskr's acceptance render paired six expression containers and exposed 47 named targets.
Applying `Aah = 1` changed 708 pixels in the close render; rendering the same state again
changed zero pixels. Captures remain local under the run directory because they embed the
user's game assets.

Implementation: `opensky/Engine/Formats/TRI/TRIFile.swift`. Runtime composition and GPU
upload: [face morph runtime](/engine/face-morphs.md).
