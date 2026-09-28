---
type: File Format
title: NIF geometry and skinning
description: BSTriShape, BSDynamicTriShape, the SSE vertex format, skin blocks, the two bone
  index spaces, and the bind pose.
tags: [format, mesh, geometry, skinning]
---

# NIF geometry and skinning

This page covers SSE geometry blocks and the skinning blocks that attach them to bones. The
container is on the [NIF](/formats/nif.md) page.

Sources: NifTools `nif.xml`, and for skinning `nif.xml` at commit
[`292bb94`](https://github.com/niftools/nifxml/blob/292bb9403cbf4052c58d66e80906b6bde1700779/nif.xml):
`BSTriShape`, `BSDynamicTriShape`, `NiSkinInstance`, `BSDismemberSkinInstance`, `NiSkinData`,
`BoneData`, `NiSkinPartition`, `SkinPartition`, `BSVertexDataSSE`. All refs are int32. -1 is
null.

## BSTriShape

SSE only (BS 100). The original Skyrim had no such block, and Fallout 4 changed it. After the
shared prefix:

| Type | Field | Notes |
| --- | --- | --- |
| float x 4 | Bounding sphere | Center and radius, shape-local |
| int32 | Skin ref | -1 means static |
| int32 | Shader property | See [NIF materials](/formats/nif-materials.md) |
| int32 | Alpha property | See [NIF materials](/formats/nif-materials.md) |
| uint64 | Vertex desc | Below |
| uint16 | Triangle count | uint32 only in Fallout 4 |
| uint16 | Vertex count | |
| uint32 | Data size | `stride * vertices + 6 * triangles`. 0 means no arrays |
| ... | Vertices | `BSVertexDataSSE` records |
| ... | Triangles | uint16 x 3 each |
| uint32 | Particle data size | A copy follows if not 0. Skipped |

Vertex desc (uint64): bits 0-3 are the vertex size in 4-byte words. Bits 44-54 are the
attribute flags. The nibbles between them are attribute offsets. They repeat what the flags say,
so OpenSky does not use them. It builds the layout from the flags and rejects the shape when
that layout's size disagrees with bits 0-3. This catches layouts OpenSky does not model.

`BSVertexDataSSE` fields, in this order, each present when its flag is set:

| Flag | Bit | Bytes | Content |
| --- | --- | --- | --- |
| vertex | 0x001 | 16 | float x, y, z, then bitangent X or unused W |
| uvs | 0x002 | 4 | half u, half v |
| normals | 0x008 | 4 | normbyte x, y, z, then bitangent Y |
| tangents | 0x010 | 4 | normbyte x, y, z, then bitangent Z |
| colors | 0x020 | 4 | RGBA bytes, divided by 255 |
| skinned | 0x040 | 12 | 4 half weights, 4 uint8 bone indices |
| eye data | 0x100 | 4 | float. Skipped |

- Positions are always full floats in SSE. The full-precision flag (0x400) still appears in
  vanilla, but only matters in Fallout 4, so it is ignored.
- The fourth float of the position is bitangent X when tangents exist.
- Tangent bytes exist only when normals exist too.
- The bitangent is split over three places (X, Y, Z above) and put back together when read.
- A normbyte becomes a float as `(byte / 255) * 2 - 1` (as in NifSkope and nifly).
- Every triangle index must be less than the vertex count.

`BSSubIndexTriShape` is a complete `BSTriShape` plus segment data (see [LOD](/formats/lod.md)).

## BSDynamicTriShape

FaceGen head meshes use `BSDynamicTriShape`. It is a full `BSTriShape`, then:

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | Dynamic data size | Must be vertex count x 16 |
| Vector4 x (size / 16) | Current vertices | Finite float xyzw. xyz is the position |

The header keeps the vertex count even when its own data size is 0. Real FaceGen meshes store
positions in this tail. UVs, normals, colors, and bone weights are in the top-level stream of
`NiSkinPartition`, with the vertex flag clear. OpenSky merges the two by vertex index. A size
mismatch, a short or non-finite value, or a count mismatch rejects the shape.

## NiSkinInstance

Links a shape to its bind data and its partitions.

| Type | Field | Notes |
| --- | --- | --- |
| int32 | Data | `NiSkinData` ref |
| int32 | Skin partition | `NiSkinPartition` ref |
| int32 | Skeleton root | `NiNode` pointer |
| uint32 | Bone count | |
| int32 x count | Bones | `NiNode` pointers. These are the global bone IDs |

`BSDismemberSkinInstance` adds a uint32 partition count, then per partition a uint16 flags and
a uint16 body part ID. OpenSky keeps them but does not hide parts yet.

## NiSkinData

One 52-byte `NiTransform` (Matrix33 rotation, Vector3 translation, float scale), then a uint32
bone count and a uint8 "has vertex weights". Each `BoneData` is an `NiTransform` (the inverse
bind, from skin to bone), a bounding sphere (float3 center, float radius), a uint16 vertex
count, and optional (uint16 vertex, float weight) pairs. SSE bodies keep their real weights in
`NiSkinPartition`. The old pairs are still read.

## NiSkinPartition

A uint32 partition count, a uint32 vertex data size, a uint32 vertex stride, a uint64 vertex
desc, then one top-level interleaved vertex stream. Each `SkinPartition` then has counts, a bone
palette, a map from local to global vertex, optional weights, faces, and uint8 bone indices, an
LOD byte, a "global vertex buffer" byte, the vertex desc again, and a required global uint16
triangle list.

OpenSky draws the global triangle list. In later `malebody_1.nif` partitions, the local
"primary faces" contain indices past the local vertex count. So those faces are checked and
skipped.

## Two bone index spaces

Two kinds of bone index exist. Do not mix them up:

- The top-level `BSVertexDataSSE` stream stores global bone IDs. They index the
  `NiSkinInstance` bone list directly.
- A partition's own bone index array stores local IDs. They go through that partition's bone
  palette to become global.

OpenSky uses the top-level stream when it exists (normal skinned `BSTriShape`). Otherwise it
uses the partition indices with the palette (FaceGen, with an empty top-level stream).

Example: `SabreCat.nif` has 61 bones and two partitions that share the top-level stream.
Partition 1 has a 59-entry palette `[0, 3, 4 ... 60]`, and the top-level stream uses global
bone 60. Sending the top-level indices through that palette fails. Treating them as global
works. Vanilla human bodies have identity palettes, which hide the mistake. The "global vertex
buffer" byte is 0 on every SabreCat partition, so that byte does not choose the space. The
presence of the top-level stream does.

The rule is per vertex, not per shape. In `Armor\Iron\Male\1stPersonCuirassLight_1.nif`, 6 of
468 top-level vertices have all four weights at 0, but the same vertices have weights in their
partition. So an empty top-level entry uses the partition entry when there is one. A vertex
with no weights anywhere keeps zero weights. Its triangles collapse, which is what the GPU would
do too. That is better than refusing a mesh with hundreds of good vertices. A non-finite weight
sum means a broken file and is still refused.

## Skeleton and bind pose

The skin matrix of a bone, from the public
[NiSkinInstance notes](https://morrowind-nif.github.io/Notes_EN/module_2_3_2_38_4.htm):

```text
rootParentToSkin * currentBoneToRootParent * skinToBoneBind
```

- Bones are found by name in the race's `skeleton.nif`. A missing bone rejects the skin.
- For the bind pose alone, `currentBoneToRootParent` comes from the body's own inverse-bind
  transforms, which gives an identity palette.
- Vanilla body dummy nodes have no bind translation, so they cannot give a full pose.
- FaceGen meshes carry their own `NPC Head` and `NPC Spine2` nodes with the current pose. These
  place dynamic shapes correctly. For example, they move the mouth from bone space up to head
  height.
- Animation replaces `currentBoneToRootParent`. Weights and GPU layout do not change.
