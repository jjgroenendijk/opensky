---
type: File Format
title: NIF skinning (Skyrim SE)
description: NiSkinInstance, BSDismemberSkinInstance, NiSkinData, and NiSkinPartition
  layouts, the two bone index spaces, and the bind pose.
tags: [format, mesh, skinning, skeleton, geometry]
---

# NIF skinning

A skinned mesh moves with a skeleton. Each vertex has up to four bones and weights. This
page covers the skin blocks that a `BSTriShape` links to through its skin ref (see
[NIF](/formats/nif.md)). See [actor animation](/engine/actor-animation.md) for how the pose
is applied.

Reference: NifTools
[`nif.xml` at `292bb94`](https://github.com/niftools/nifxml/blob/292bb9403cbf4052c58d66e80906b6bde1700779/nif.xml):
`NiSkinInstance`, `BSDismemberSkinInstance`, `NiSkinData`, `BoneData`, `NiSkinPartition`,
`SkinPartition`, `BSVertexDataSSE`. All refs are int32, and -1 is null.

## NiSkinInstance

Links a shape to its bind data and partitions.

| Type | Field | Notes |
| --- | --- | --- |
| int32 | Data | `NiSkinData` ref |
| int32 | Skin partition | `NiSkinPartition` ref |
| int32 | Skeleton root | `NiNode` pointer |
| uint32 | Bone count | |
| int32 x count | Bones | `NiNode` pointers. The index is the global bone ID |

`BSDismemberSkinInstance` adds a uint32 partition count, then per partition a uint16 flags
and a uint16 body part ID. OpenSky keeps them but does not hide body parts yet.

## NiSkinData

A 52-byte `NiTransform` (`Matrix33` rotation, `Vector3` translation, float scale), a uint32
bone count, and a uint8 "has vertex weights". Then per bone (`BoneData`): an `NiTransform`
from skin to bone (the inverse bind), a bounding sphere (float3 center, float radius), a
uint16 vertex count, and optional (uint16 vertex, float weight) pairs. Skyrim SE bodies keep
their weights in `NiSkinPartition` instead. OpenSky still reads the pairs.

## NiSkinPartition

In Skyrim SE: a uint32 partition count, a uint32 vertex data size, a uint32 vertex size, a
uint64 `BSVertexDesc`, and one top-level interleaved vertex stream. Then each
`SkinPartition`: counts, a bone palette (global bone IDs), a map from local to global
vertex, optional float weights, faces, and uint8 palette indices, an LOD byte, a "global
vertex buffer" byte, the vertex desc again, and a required copy of the triangles with
global uint16 indices.

OpenSky draws the global triangle copies. In later `malebody_1.nif` partitions, the local
faces hold indices past the local vertex count, even though `nif.xml` says they are local.
The global copies match the real geometry, so the local faces are checked and skipped.

## Two bone index spaces

Two kinds of bone index exist. They must not be mixed:

- The top-level vertex stream (`BSVertexDataSSE` bone indices, per global vertex) holds
  global bone IDs. They index the `NiSkinInstance` bone list directly. There is no palette
  step.
- The per-partition bone index array holds palette indices. They go through the
  partition's bone palette to get a global ID.

OpenSky uses the top-level stream when it exists (a normal skinned `BSTriShape`).
Otherwise it uses the partition indices through the vertex map and palette (FaceGen
`BSDynamicTriShape`, whose top-level stream is empty).

Example, `SabreCat.nif`: one shape, 3,311 vertices, 61 bones, two partitions sharing the
top-level stream. Partition 1 has a 59-entry palette `[0, 3, 4 ... 60]`, which is not the
identity. The top-level stream uses global bone 60. Sending the top-level indices through
the palette fails with an index out of range. Vanilla bodies (`malebody_1.nif`) have
identity palettes, which hides the mistake. The "global vertex buffer" byte is 0 on every
SabreCat partition, so it does not choose the index space. The presence of the top-level
stream does.

The rule is per vertex, not per shape. In `Armor\Iron\Male\1stPersonCuirassLight_1.nif`, 6
of 468 top-level vertices have all four weights 0, while the same vertices have weights in
their partition. So an empty top-level entry uses the partition entry when that has
weights. A vertex with no weights anywhere keeps zero weights. It collapses onto the
skeleton root, as it does on the GPU in the game. This is better than refusing a mesh whose
other vertices are fine. A weight total that is not a finite number is a broken file and is
refused.

## Skeleton and bind pose

OpenSky reads the node names and local transforms of `skeleton.nif` into a tree of world
transforms. Body and FaceGen bones are found by name in that tree. A missing bone rejects
the skin. Vanilla body files have dummy nodes without bind translations, so they are not a
full pose source. FaceGen's own `NPC Head` and `NPC Spine2` nodes hold the current pose,
which moves the mouth up to head height.

The Gamebryo skin matrix, from the
[public NiSkinInstance help](https://morrowind-nif.github.io/Notes_EN/module_2_3_2_38_4.htm):

`rootParentToSkin * currentBoneToRootParent * skinToBoneBind`

For a bind-pose render, `currentBoneToRootParent` comes from the body's inverse bind
transforms, so the result is the identity within float error. For FaceGen, it comes from
the world transforms of the referenced nodes. Animation later replaces the current bone
transforms without changing weights or GPU layout.

## Vanilla examples

- `malebody_1.nif`: 2 skinned meshes, 1,802 vertices, 2,948 triangles. The underwear has
  417 vertices and 5 bones. The body has 1,385 vertices and 24 bones in 3 partitions.
- `skeleton.nif`: 268 blocks, 98 `NiNode`s.
- Heimskr's FaceGen head `00013bac.nif`: 6 dynamic skinned meshes, 1,591 vertices.
