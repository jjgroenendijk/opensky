---
type: File Format
title: FaceGen TRI expression container
description: FRTRI003 layout, named morph targets, and how a face mesh finds its TRI file.
tags: [format, tri, facegen, morph, expression, hdpt]
---

# FaceGen TRI expression container

A `.tri` file holds morph targets for a face. A morph target moves every vertex of a mesh by
a small offset, for example to open the mouth. The format is `FRTRI003`.

OpenSky reads the base shape and the named morph targets used for facial expressions. It
checks and skips the character-creation modifiers, the modifier vertices, and the UV data.

Sources: NifTools PyFFI
[`tri.xml`](https://github.com/niftools/pyffi/blob/master/pyffi/formats/tri/tri.xml) and its
[decoder](https://github.com/niftools/pyffi/blob/master/pyffi/formats/tri/__init__.py). The
record links come from xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).

## Header (64 bytes)

All integers are little-endian.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | char[5] | `FRTRI` |
| 0x05 | char[3] | Version, `003` |
| 0x08 | int32 | Base vertex count |
| 0x0C | int32 | Triangle count |
| 0x10 | int32 | Quad count |
| 0x14 | int32 | Unknown count |
| 0x18 | int32 | Unknown count |
| 0x1C | int32 | UV count |
| 0x20 | int32 | Has UVs, 0 or 1 |
| 0x24 | int32 | Morph target count |
| 0x28 | int32 | Modifier count |
| 0x2C | int32 | Modifier vertex count |
| 0x30 | int32[4] | Unknown |

A negative count, a UV flag other than 0 or 1, another version, or counts larger than the
file are errors.

## Body

The body follows the counts in this order:

1. Base vertices: three float32 each.
2. Modifier vertices: three float32 each.
3. Triangles: three uint32 vertex indices each.
4. Quads: four uint32 vertex indices each.
5. UVs: two float32 each.
6. If the UV flag is 1: UV triangles and UV quads, the same shape as step 3 and 4.
7. Named morph targets.
8. Character-creation modifiers.

Every float must be finite. Every index must be less than its count. The file must end
exactly after step 8.

## Named morph target

| Type | Meaning |
| --- | --- |
| uint32 | Length of the name, including its null byte |
| char[length] | UTF-8 name, ending with a null byte |
| float32 | Scale |
| `int16[vertexCount][3]` | Offset for each vertex |

The offset of a vertex is `Float(component) * scale`. There is one offset for every base
vertex, so the target is not sparse.

## How a face mesh finds its TRI

The face `.nif` does not name its `.tri`. The link goes through plugin records:

1. Collect the head parts: the race's default head parts for the actor's sex, and the
   `NPC_ PNAM` head parts.
2. Read each head part (`HDPT`): its `EDID` and its `NAM0` and `NAM1` pairs.
3. Take the pair with `NAM0 = 1`. xEdit calls it the expression TRI. `NAM0 = 0` is the race
   morph and `NAM0 = 2` is the character-creation morph.
4. `NAM1` is relative to `Data/Meshes`, so add `meshes\` in front.
5. Match the `HDPT` `EDID` to the `BSDynamicTriShape` name in the face mesh, ignoring case.
6. The shape must be skinned, and its vertex count must equal the TRI vertex count.

Each failure has its own reason: missing field, missing shape, missing or broken TRI,
shape not skinned, or vertex count mismatch.

Vanilla examples:

| HDPT editor ID | TRI | Vertices |
| --- | --- | --- |
| `MaleHeadNord` | `MaleHead.tri` | 898 |
| `FemaleHeadNord` | `FemaleHead.tri` | 996 |
| `MaleMouthHumanoidDefault` | `MouthHuman.tri` | 141 |
| `FemaleMouthHumanoidDefault` | `MouthHumanF.tri` | 141 |

The runtime side is in [face morphs](/engine/face-morphs.md).
