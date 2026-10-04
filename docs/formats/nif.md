---
type: File Format
title: NIF mesh (Gamebryo 20.2.0.7, Skyrim SE)
description: Skyrim SE .nif container - header, blocks, footer, the scene graph, and
  BSTriShape geometry.
tags: [format, mesh, geometry, io]
---

# NIF mesh, Gamebryo 20.2.0.7

A NIF file holds a Gamebryo scene graph: a tree of nodes with geometry, materials,
collision, and animation. Skyrim SE meshes are version 20.2.0.7, user version 12, Bethesda
stream (BS) 100. The original Skyrim used stream 83. Fallout 3 and New Vegas use the same
version with user version 11. A file is a header, then the blocks one after another, then a
footer.

Related pages: [NIF skinning](/formats/nif-skinning.md),
[NIF materials](/formats/nif-materials.md), [NIF Havok collision](/formats/nif-collision.md),
[NIF particle systems](/formats/nif-particles.md), and [LOD](/formats/lod.md).

Reference: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml),
structs `Header`, `BSStreamHeader`, `ExportString`, `SizedString`, `Footer`. NifSkope was
used to view real files. All integers are little-endian; the header's endian byte must say
so.

## Strings

| Name | Layout |
| --- | --- |
| HeaderString | Text ending with `\n` (0x0A). No length |
| ExportString | uint8 length (with the null), then the bytes and a null |
| SizedString | uint32 length, then the bytes. No null |

Strings follow the [string decoding](/decisions/string-decoding.md) policy. Some vanilla
string tables hold random bytes from the exporter's memory, for example `0c 90 29 7b ...` in
`dwelexiconstandrunes01.nif`. A garbage name must not reject the mesh.

## Header

Field order from `nif.xml` `Header`, only the fields that exist at 20.2.0.7:

| Type | Field | Notes |
| --- | --- | --- |
| HeaderString | Version line | `Gamebryo File Format, Version 20.2.0.7` |
| uint32 | Version | `0x14020007`, one byte per part |
| uint8 | Endian | 1 is little-endian, the only value accepted |
| uint32 | User version | 12 |
| uint32 | Block count | |
| BSStreamHeader | BS header | When user version >= 3 |
| uint16 | Block type count | |
| SizedString x count | Block types | Type names, for example `BSTriShape` |
| uint16 x block count | Type indices | Into block types. Bit 15 (PhysX) is masked off |
| uint32 x block count | Block sizes | Bytes per block |
| uint32 | String count | |
| uint32 | Max string length | Ignored |
| SizedString x count | Strings | Shared name table |
| uint32 | Group count | |
| uint32 x count | Groups | |

`BSStreamHeader`: uint32 BS version (83 original Skyrim, 100 Skyrim SE), then three
ExportStrings (author, process script, export script), then a fourth (max file path) only
when the BS version is 103 or more. Versions above 130 are Fallout 4 and later, and are
rejected.

## Blocks and footer

Blocks follow the header in table order, with no framing. Block N is exactly `blockSizes[N]` bytes,
so OpenSky can walk the file without knowing every block type. Unknown or unneeded blocks
(controllers, PhysX) are skipped by size. A block larger than the bytes left is an error, and the
caller skips the mesh.

The footer is a uint32 root count, then that many int32 block indices (-1 is null).

## Shared node fields

Typed decoding needs version 20.2.0.7 with stream 83 or 100. Other streams move fields and
are rejected. Every scene object (the `NiNode` family and `BSTriShape`) starts with the
same `NiObjectNET` and `NiAVObject` fields. For streams 83 and 100, flags are uint32
(BS > 26) and there is no property list (BS > 34):

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | Name | Index into the string table. -1 is none |
| uint32 | Extra data count | |
| int32 x count | Extra data refs | Skipped |
| int32 | Controller | Animation. Skipped |
| uint32 | Flags | |
| float x 3 | Translation | |
| float x 9 | Rotation | `Matrix33`, see below |
| float | Scale | Uniform only |
| int32 | Collision ref | See [NIF Havok collision](/formats/nif-collision.md) |

A name index that points nowhere gives no name. The local transform is `T * R * S` with
column vectors (see [coordinates](/decisions/coordinates.md)).

### Matrix33 is transposed

NIF multiplies row vectors (`v * M`). OpenSky multiplies column vectors (`M * v`). So
OpenSky transposes every `Matrix33` when it reads it. The nine floats come in the order
`m11 m21 m31 | m12 m22 m32 | m13 m23 m33`. Reading each group of three as a row gives the
transpose directly.

Static meshes do not show the mistake, because their node rotations are almost all
identity. A skeleton does. Without the transpose, the bind pose from `skeleton.nif`'s nodes
disagrees with the same file's `NiSkinData` by up to about 10 units on a thigh, and with
`skeleton.hkx` by up to 61.9 units. With the transpose, the rig matches the NIF bind pose to
5.3e-5, and `rootParentToSkin * boneWorld * skinToBone` is the identity to 8e-6 for every
bone of a vanilla body. See [actor animation](/engine/actor-animation.md).

## NiNode

After the shared fields:

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | Child count | |
| int32 x count | Children | Block refs. -1 is an empty slot |
| uint32 | Effect count | Only before Fallout 4 |
| int32 x count | Effects | Skipped |

`BSFadeNode`, `BSLeafAnimNode`, `BSTreeNode`, and `BSOrderedNode` use the same layout.
`BSMultiBoundNode` adds a tail (see [LOD](/formats/lod.md)). `NiSwitchNode` and `NiLODNode`
are not walked on purpose. They draw one child, not all, and walking them would stack LOD
versions on top of each other.

## NiStringExtraData

Two `uint32` string-table indices: the name, then the value. -1 is none. A prop mesh
(`ANIO` model) names the bone it rides in an extra data called `Prn`, such as
`AnimObjectR` or `NPC R Hand [RHnd]`. Confirmed on the 82 `ANIO` models of the five
masters: each one carries `Prn`. Each value is a bone of the character `skeleton.hkx`,
except `NPC L Hand` and `NPC R Hand`, which leave out the bone's `[LHnd]` or `[RHnd]` tag.
OpenSky matches such a value to the bone whose name starts with it.

## BSTriShape

Skyrim SE geometry, stream 100 only. After the shared fields:

| Type | Field | Notes |
| --- | --- | --- |
| float x 4 | Bounding sphere | Center and radius, shape-local |
| int32 | Skin ref | -1 is static |
| int32 | Shader property | See [NIF materials](/formats/nif-materials.md) |
| int32 | Alpha property | See [NIF materials](/formats/nif-materials.md) |
| uint64 | Vertex desc | Below |
| uint16 | Triangle count | uint32 only in Fallout 4 |
| uint16 | Vertex count | |
| uint32 | Data size | `stride * vertices + 6 * triangles`. 0 means no arrays |
| ... | Vertices | `BSVertexDataSSE`, interleaved |
| ... | Triangles | 3 x uint16 each. Each index must be below the vertex count |
| uint32 | Particle data size | Skyrim SE only. That many bytes follow and are skipped |

`BSVertexDesc` (uint64): bits 0-3 are the vertex size in 4-byte words. Bits 44-54 are the
attribute flags. OpenSky builds the layout from the flags. If the size it gets differs from
bits 0-3, the shape is rejected. This catches layouts OpenSky does not know.

Vertex fields, present per flag, in this order:

| Flag | Bit | Bytes | Content |
| --- | --- | --- | --- |
| Vertex | 0x001 | 16 | float x, y, z, then bitangent X (with tangents) or unused |
| UVs | 0x002 | 4 | half u, half v |
| Normals | 0x008 | 4 | normal x, y, z bytes, then bitangent Y byte |
| Tangents | 0x010 | 4 | tangent x, y, z bytes, then bitangent Z byte. Only with normals |
| Colors | 0x020 | 4 | RGBA bytes / 255 |
| Skinned | 0x040 | 12 | 4 half weights, 4 uint8 bone indices |
| Eye data | 0x100 | 4 | float. Skipped |

A normal byte maps to `(byte / 255) * 2 - 1` (as in NifSkope and nifly). Positions are
always full floats in Skyrim SE. The "full precision" flag (0x400) chooses half or full
floats only in Fallout 4. It appears in vanilla Skyrim SE files and is ignored.

`BSSubIndexTriShape` is a full `BSTriShape` plus segment data. See [LOD](/formats/lod.md).

### BSDynamicTriShape

FaceGen heads use `BSDynamicTriShape`: a full `BSTriShape`, then (NifTools `nif.xml` at
`292bb94`):

| Type | Field | Notes |
| --- | --- | --- |
| uint32 | Dynamic data size | Must be vertex count x 16 |
| Vector4 x size / 16 | Current vertices | Finite float x, y, z, w. x, y, z is the position |

The inherited vertex count stays set even when its data size is 0. Real FaceGen files keep
the positions in this tail. UVs, normals, colors, and bone weights are in the
`NiSkinPartition` vertex stream, with the vertex flag cleared. OpenSky joins them by vertex
index. A wrong byte count, bad values, or a different vertex count rejects the shape.

## From scene graph to meshes

- The walk starts at the footer roots. It follows node children and composes
  `parent * local` down the tree. `BSTriShape`, `BSSubIndexTriShape`, and
  `BSDynamicTriShape` become meshes with their model-space transform.
- Materials are shared by (shader property, alpha property) pair.
- Collision and controller blocks end the walk of their subtree.
- A ref out of range, a loop, or depth above 64 is an error. A subtree used under two
  parents is allowed; only a loop on the current path is an error.
- Every scene walk (bind pose, meshes, particles, collision targets) uses one explicit work
  stack, not recursion. With recursion, the real depth limit was the thread's stack: a
  512 KB secondary thread, or the main thread under Address Sanitizer, ran out before depth
  64. The limit of 64 is again a rule about plausible files.

## Camera animation

A `CAMS` camera mesh holds one `NiCamera`. In vanilla meshes the camera itself has no
controller: its parent, the root `BSFadeNode`, carries the `NiTransformController`, and the
camera sits at a fixed offset below it. OpenSky reads the first `NiCamera` block, walks up to
the nearest node whose controller chain holds a transform controller, and composes the camera
offset under that node's keys. Reference: `nif.xml` blocks `NiCamera`, `NiTimeController`,
`NiTransformController`, `NiTransformInterpolator`, and `NiTransformData`.

| Block | Fields OpenSky reads |
| --- | --- |
| `NiCamera` | The shared node fields (rest transform and controller ref), then 2 bytes of camera flags and the frustum floats left, right, top, bottom, near; top and bottom are skipped |
| `NiTransformController` | Next controller ref, flags (uint16), frequency, phase, start time, stop time, target ref, interpolator ref |
| `NiTransformInterpolator` | A rest translation, rotation, and scale (32 bytes), then the data ref |
| `NiTransformData` | Rotation and translation keys, as in `.kf` animation files. Scale keys come last and are not read |

The horizontal field of view is `2 * atan((right - left) / 2 / near)`. A camera with no
controller, or with a controller that has no interpolator, keeps its rest transform. Between
two keys OpenSky blends linearly: translations mix, quaternions slerp, and XYZ rotation data
mixes each angle, then applies X, then Y, then Z. It ignores the tangents of quadratic keys,
so a curved camera path is followed as straight segments between keys.

A chain can start with a `BSFrustumFOVController` before the transform controller. OpenSky
follows the next-controller links and skips it, so the field of view stays the frustum's. On
the install, 77 meshes are named by `CAMS` records and one, `killcam_topsideclosea.nif`, is
not in the archives. Of the other 76, 73 use XYZ rotation keys and 67 move the camera; most
run from -0.033 to 15.7 seconds.

## Vanilla meshes

All 22,806 `.nif` files in the vanilla archives parse. All are 20.2.0.7, user version 12,
and stream 100, except one stream 83 file. They use 143 block types. Every mesh in the
geometry archives decodes, and sizes make sense: `farmhouse01.nif` is 1409 x 705 x 744
units (about 20 x 10 x 11 m), and `rockl01.nif` is 333 x 426 x 289.
