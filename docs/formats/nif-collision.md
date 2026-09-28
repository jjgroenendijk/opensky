---
type: File Format
title: NIF Havok collision
description: Skyrim SE bhk collision objects, collision filters, the shape graph, compressed
  meshes, triangle strips, and surface materials.
tags: [format, nif, havok, collision, geometry]
---

# NIF Havok collision

A Skyrim NIF attaches Havok collision to a scene node through a collision object. OpenSky
follows each collision object to its rigid body and its shape graph. It turns them into
triangle lists or simple shapes (box, sphere, capsule, convex hull) in engine units. Rigid-body
physics values and joints are on the [NIF rigid bodies](/formats/nif-rigid-bodies.md) page.

Source: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml): types
`bhkNiCollisionObject`, `bhkWorldObject`, `bhkEntity`, `bhkRigidBodyCInfo2010`, the shape
types below, `bhkCMSChunk`, `bhkCMSBigTri`, `bhkQsTransform`, `hkPackedNiTriStripsData`,
`NiTriStripsData`. Compressed-chunk decoding and strip handling were checked against the
open-source [PyNifly/nifly](https://github.com/BadDogSkyrim/PyNifly/blob/main/NiflyDLL/NiflyWrapper.cpp).

## Units and transforms

Havok uses meters. Skyrim uses its own units. Every Havok position, translation, half extent,
and radius is multiplied by `69.99125` engine units per meter. Rotations and shape scale have
no unit. Matrices are column-vector style: `parent * local`.

The transform of a shape is built in this order:

1. The model transform of the target `NiAVObject`.
2. For `bhkRigidBodyT` only: the translation and quaternion stored in the rigid body. A plain
   `bhkRigidBody` stores the same fields but ignores them.
3. The `Matrix44` of each `bhkTransformShape` or `bhkConvexTransformShape`.
4. For compressed mesh chunks: the chunk's optional `bhkQsTransform`.

A real-data check of the scale: the collision bounds of `mineoreiron04.nif` differ from its
render bounds by about 1 to 2 units per face. City walls follow the render footprint but reach
higher, which is on purpose, to block climbing.

## Collision object and rigid body

| Block | Fields read |
| --- | --- |
| `bhkCollisionObject` | Target ref, uint16 flags, rigid body ref |
| `bhkBlendCollisionObject` | The same, then two blend gain floats (not read) |
| `bhkRigidBody`, `bhkRigidBodyT` | Shape ref, `HavokFilter`, 20-byte world info, response and callback bytes, `bhkRigidBodyCInfo2010`, constraint refs, uint16 body flags |
| `HavokFilter` | uint8 layer, uint8 flags, uint16 group |

The rigid body holds two filters and two response types.

## Solid, trigger, or other

A body blocks the player only when all of these hold:

- Neither filter's layer is `SKYL_TRIGGER` (12) or `SKYL_NONCOLLIDABLE` (15).
- Neither filter has the "No Collision" bit (`0x40`).
- Both response types are `RESPONSE_SIMPLE_CONTACT` (1).

A body on layer 12 in either filter is a trigger volume. "Not solid" and "trigger" are not the
same: layer 15, the "No Collision" bit, and other responses are not solid, but they are not
triggers either. Triggers go to the per-cell trigger set in the
[collision world](/engine/collision-world.md), which reports `OnTriggerEnter` and
`OnTriggerLeave`.

## The filter flags byte

The flags byte is `CollisionFilterFlags` in `nif.xml`, a bit field:

| Bits | Meaning |
| --- | --- |
| 0-4 | `BipedPart` |
| 5 | MOPP scaled |
| 6 | No collision |
| 7 | Linked group |

The biped part only has meaning on layers `SKYL_BIPED` (8), `SKYL_DEADBIP` (32), and
`SKYL_BIPED_NO_CC` (33). On other layers OpenSky reports no part, not 0, because 0 is a real
part (`P_OTHER`, which vanilla uses on `NPC Neck`). Every body of the vanilla human
`skeleton.nif` is on layer 8, group 0, with the correct part number. The
[ragdoll solver](/engine/ragdoll-solver.md#self-collision) uses it.

## Shape graph

| Block | What OpenSky does |
| --- | --- |
| `bhkMoppBvTreeShape` | Follows the child. Skips the MOPP bytecode |
| `bhkListShape` | Follows each child |
| `bhkTransformShape`, `bhkConvexTransformShape` | Adds the `Matrix44`, then follows the child |
| `bhkCompressedMeshShape` | Reads scale and data. Gives big-triangle and per-chunk triangle lists |
| `bhkPackedNiTriStripsShape` | Reads scale and `hkPackedNiTriStripsData`. Gives indexed triangles |
| `bhkNiTriStripsShape` | Reads scale and each `NiTriStripsData`. Gives indexed triangles |
| `bhkConvexVerticesShape` | Reads vertices and planes. Builds hull faces once per model |
| `bhkBoxShape` | Keeps half extents |
| `bhkSphereShape` | Keeps the radius |
| `bhkCapsuleShape` | Keeps both end points and the larger of the stored radii |

MOPP bytecode is a Havok search tree. OpenSky does not run it. The child geometry is the real
shape.

An unknown shape type is counted by name. One broken collision object is recorded as a failure,
and the other collision objects still decode. The graph depth is limited to 64, loops are
detected, and every ref, count, index, strip length, and triangle total is checked before use.

For a convex shape, each plane's XYZ is an outward normal without units, and W is a signed
distance in meters. Hull faces are built by grouping vertices on each plane, sorting them around
the center, and splitting them into triangles. This happens once per model, not once per placed
object.

## Compressed mesh

`bhkCompressedMeshShapeData` holds, in order: compression settings and a bounding box, counted
material lists, chunk materials, named-material count, 32-byte transforms, big vertices, 12-byte
big triangles, chunks, and a convex-piece count.

- A big vertex is a float4 XYZ. Multiply by the shape scale and the unit scale.
- A big triangle is three uint16 indices, a material index, and welding info.
- A chunk has a translation, a material, a chunk reference, a transform index, a list of uint16
  XYZ values, an index list, strip lengths, and welding info.

Chunk vertex position:

```text
point = chunkTranslation + SIMD3(uint16XYZ) / 1000
```

Then the chunk transform, then shape scale and unit scale. Strips flip winding on each
triangle. Indices after all strips are plain triples. Vanilla chunks use reference `0xffff`
(standalone). References to other chunks are reported as unsupported.

## Triangle strips

`hkPackedNiTriStripsData` holds welded uint16 triangles, float3 or float16 vertices, and
sub-shape rows (`hkSubPartData`: Havok filter, vertex count, material). The sub-shapes split the
vertex list in order. A triangle belongs to the sub-shape that holds its first vertex.

`NiTriStripsData` starts with the old `NiGeometryData` fields. One wrong field width shifts
every later field, so here is the order (`NiGeometryData`, then `NiTriBasedGeomData`, then
`NiTriStripsData`):

| Field | Size | Note |
| --- | --- | --- |
| Group ID | uint32 | |
| Num Vertices | uint16 | |
| Keep Flags, Compress Flags | 1 byte each | |
| Has Vertices | 1 byte | 0 is an error for a collision shape |
| Vertices | 12 bytes each | |
| BS Vector Flags | uint16 | Bit 0: one UV set. Bit 12: tangents |
| Material CRC | uint32 | A render material, not a Havok surface |
| Has Normals | 1 byte | Normals 12 bytes each, then tangents and bitangents 24 bytes each |
| Bounding sphere | 16 bytes | Center and radius |
| Has Vertex Colors | 1 byte | Colors 16 bytes each |
| UV set | 8 bytes each | Once, if bit 0 is set |
| Consistency Flags | uint16 | An enum. Not uint32 |
| Additional Data | ref | |
| Num Triangles | uint16 | |
| Num Strips, strip lengths | uint16 each | |
| Has Points | 1 byte | |
| Points | uint16 each | The sum of the strip lengths |

Note the Consistency Flags width. Reading it as 4 bytes moves the strip table 2 bytes late.
Only three vanilla meshes use `bhkNiTriStripsShape`:
`clutter\coffins\nordiccoffinstatic03`, `clutter\goatskin\goatpeltstatic`, and
`clutter\nightmother\nmbody01`. The declared triangle count must match the triangles produced.

## Surface material

Every shape carries a `SkyrimHavokMaterial`. One shape has one material. When a block stores
several, OpenSky makes one shape per material, because those blocks already split their
geometry that way.

| Block | Where the material is |
| --- | --- |
| `bhkSphereShape`, `bhkBoxShape`, `bhkCapsuleShape`, `bhkConvexVerticesShape` | First uint32 of the shape |
| `bhkNiTriStripsShape` | First uint32 of the shape, shared by all its strips |
| `bhkPackedNiTriStripsShape` | The `hkSubPartData` row of each triangle |
| `bhkCompressedMeshShape` | The chunk material table, per chunk and per big triangle |

Example: `mineoreiron04.nif` gives one `MaterialDirt` shape and one `MaterialStone` shape. A
material index past the end of the table gives geometry with no material. The geometry is kept.

Turning the hash into a `MATT` record needs the plugin. See
[material types](/formats/material-type.md).

## Inspecting

`openskycli collision` loads every model used by a target exterior cell. It reports collision
objects, bodies, shapes, triangles, filtered bodies, unsupported types, failures, materials,
and collision and render bounds. It then builds the [collision world](/engine/collision-world.md)
for a grid of cells. It exits with an error on any failure.

Welding data is checked and skipped. Nothing uses it.
