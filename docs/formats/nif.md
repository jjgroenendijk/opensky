---
type: File Format
title: NIF mesh (Gamebryo 20.2.0.7, Skyrim SE)
description: Skyrim SE .nif container (strings, header, blocks, footer), the shared scene-graph
  prefix, the Matrix33 transpose, NiNode, and how the scene graph becomes engine meshes.
tags: [format, mesh, geometry, io]
---

# NIF mesh (Gamebryo 20.2.0.7)

A `.nif` file is a NetImmerse/Gamebryo scene graph. It holds Skyrim's meshes: a node tree,
geometry, materials, collision, and animation. SSE meshes are version 20.2.0.7, user version
12, Bethesda (BS) stream 100. The original Skyrim used stream 83. Fallout 3 and New Vegas use
the same version with user version 11.

A file is a header, then the block payloads one after another, then a footer.

Source: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml), structs
`Header`, `BSStreamHeader`, `ExportString`, `SizedString`, `Footer`. NifSkope was used to view
real files. All integers are little-endian. The header's endian byte must say so.

Related pages:

- [NIF geometry and skinning](/formats/nif-geometry.md): `BSTriShape`, `BSDynamicTriShape`,
  skin blocks, bind pose.
- [NIF materials](/formats/nif-materials.md): shader properties, texture sets, alpha.
- [NIF collision](/formats/nif-collision.md) and [NIF rigid bodies](/formats/nif-rigid-bodies.md).
- [NIF particle systems](/formats/nif-particles.md).
- [Distant LOD](/formats/lod.md): `BSMultiBoundNode` and `BSSubIndexTriShape`.

## Strings

| Name | Layout |
| --- | --- |
| HeaderString | Text ending in `\n` (0x0A). No length |
| ExportString | uint8 length including the null, then the bytes and a null |
| SizedString | uint32 length, then the bytes. No null |

Header strings use the [string decoding](/decisions/string-decoding.md) rules. Vanilla string
tables contain garbage from the export tool: uninitialized memory with bytes that are not even
valid windows-1252. Example: in
`meshes/dungeons/dwemer/animated/astrolabe/lexiconstand/dwelexiconstandrunes01.nif`, one string
starts `0c 90 29 7b`. A junk name must not reject the mesh.

## Header

Field order from `nif.xml` `Header`, only the fields that exist at 20.2.0.7:

| Type | Field | Notes |
| --- | --- | --- |
| HeaderString | Version line | `Gamebryo File Format, Version 20.2.0.7` |
| uint32 | Version | `0x14020007`, one byte per part |
| uint8 | Endian | 1 is little-endian. The only value accepted |
| uint32 | User version | 12 for Skyrim and SSE |
| uint32 | Block count | |
| BSStreamHeader | BS header | Present when user version >= 3 |
| uint16 | Block type count | |
| SizedString x count | Block types | Type names, such as `BSTriShape` |
| uint16 x block count | Type indices | Into block types. Bit 15 (PhysX) is masked |
| uint32 x block count | Block sizes | Bytes per block |
| uint32 | String count | |
| uint32 | Max string length | A hint. Ignored |
| SizedString x count | Strings | Shared name table |
| uint32 | Group count | |
| uint32 x count | Groups | |

`BSStreamHeader`:

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | BS version | 83 Skyrim, 100 SSE |
| ExportString | Author | |
| ExportString | Process script | |
| ExportString | Export script | |
| ExportString | Max file path | Only when BS version >= 103 |

Fallout 4 and later (BS version above 130) change these fields and are rejected.

Block sizes exist since 20.2.0.5. They let OpenSky walk the file without knowing every block
type.

## Blocks and footer

Blocks follow the header in table order with no framing. Block N is exactly `blockSizes[N]`
bytes. Unknown or unused types (controllers, PhysX) are skipped by size. A block that claims
more bytes than remain is an error, and the mesh is skipped.

Footer: a uint32 root count, then that many int32 block indices. -1 is a null reference.

## Shared scene-graph prefix

Typed decoding needs version 20.2.0.7 with BS stream 83 or 100. Other streams move fields and
are rejected.

Every scene-graph object (the `NiNode` family, `BSTriShape`) starts with the same `NiObjectNET`
and `NiAVObject` fields. For BS 83 and 100, flags are uint32, and there is no property list:

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | Name | Index into the header string table. -1 is none |
| uint32 | Extra data count | |
| int32 x count | Extra data refs | |
| int32 | Controller | Animation controller ref |
| uint32 | Flags | |
| float x 3 | Translation | |
| float x 9 | Rotation | Matrix33. See below |
| float | Scale | Uniform only |
| int32 | Collision ref | See [NIF collision](/formats/nif-collision.md) |

A name index that points nowhere gives no name. The local transform is `T * R * S` with column
vectors (see [coordinates](/decisions/coordinates.md)).

## Matrix33 must be transposed

NIF multiplies row vectors (`v * M`). OpenSky multiplies column vectors (`M * v`). So every
`Matrix33` is transposed when read. The nine floats come in the order
`m11 m21 m31 | m12 m22 m32 | m13 m23 m33`. Reading each group of three as a row gives the
transpose in one step.

Vanilla statics hide this mistake. Their node rotations are almost all identity, and one
rotated part looks like decoration, not an error. Skeletons do not hide it. Without the
transpose, a bind pose built from `skeleton.nif` disagrees with the same file's `NiSkinData`
by up to about 10 units on a thigh, and with `skeleton.hkx` by up to about 62 units. With the
transpose, all three agree to within 0.0001 units. See [actor animation](/engine/actor-animation.md).

## NiNode

After the prefix:

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | Child count | |
| int32 x count | Children | Block refs. -1 is an empty slot |
| uint32 | Effect count | Before Fallout 4 only |
| int32 x count | Effects | Skipped |

`BSFadeNode`, `BSLeafAnimNode`, `BSTreeNode`, and `BSOrderedNode` use the same layout.
`BSMultiBoundNode` adds a tail (see [LOD](/formats/lod.md)).

`NiSwitchNode` and `NiLODNode` are not followed on purpose. They draw one child, not all.
Following them would stack all LOD versions on top of each other.

## From scene graph to engine meshes

1. Start at the footer roots. Follow `NiNode` children, multiplying `parent * local` down the
   tree.
2. Each `BSTriShape`, `BSSubIndexTriShape`, or `BSDynamicTriShape` becomes a mesh with its
   model-space transform.
3. Each unique pair of (shader property, alpha property) becomes one material. Lighting shaders
   give textured materials. Effect, water, and sky shaders give a plain fallback material that
   is still drawn.
4. Skinned shapes also get bone weights (see [NIF geometry](/formats/nif-geometry.md)).
5. Empty shapes are counted and skipped. Collision and controllers end their subtree.

A reference out of range, a loop, or a depth above 64 rejects the mesh. A loop is detected by
the active path, so one subtree used under two parents still works.

Every scene walk uses an explicit work stack on the heap, not recursion. With recursion, the
real limit was the thread's stack, not the depth cap: a 512 KB background thread stack, or the
main thread under Address Sanitizer, ran out before depth 64.

## Vanilla facts

- Every vanilla `.nif` is version 20.2.0.7, user version 12. All but one use BS stream 100.
  The one exception uses 83.
- Every vanilla mesh in the geometry archives decodes.
- The most common block types are `NiNode`, `BSLightingShaderProperty`, `BSShaderTextureSet`,
  and `BSTriShape`.
- Mesh sizes are plausible. `farmhouse01.nif` is about 1409 x 705 x 744 units, which is about
  20 x 10 x 11 meters.
