---
type: File Format
title: NIF Havok collision
description: Skyrim SE bhk collision objects, collision filters, the shape graph, compressed
  meshes, triangle strips, and surface materials.
tags: [format, nif, havok, collision, geometry, physics]
---

# NIF Havok collision

A Skyrim NIF attaches Havok collision to a scene node through a collision object. OpenSky
follows each collision object to its rigid body and shape graph. It turns the shapes into
triangle lists or simple convex shapes in engine units. The mass, joints, and ragdoll data
of a rigid body are in [NIF rigid bodies](/formats/nif-rigid-body.md). The per-cell
collision world is in [collision world](/engine/collision-world.md).

Main source: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml),
types `bhkNiCollisionObject`, `bhkWorldObject`, `bhkEntity`, `bhkRigidBodyCInfo2010`, the
shape types below, `bhkCMSChunk`, `bhkCMSBigTri`, `bhkQsTransform`,
`hkPackedNiTriStripsData`, and `NiTriStripsData`. The compressed chunk math and strip
reading were checked against
[PyNifly/nifly](https://github.com/BadDogSkyrim/PyNifly/blob/main/NiflyDLL/NiflyWrapper.cpp).

## Units and transforms

Havok stores meters. Skyrim uses its own units. Every Havok position, translation, half
extent, and radius is multiplied by `69.99125` engine units per meter. Rotations and shape
scale have no unit. Matrices use column vectors: `parent * local`.

The transform of a shape is built in this order:

1. The model transform of the target `NiAVObject`, from the scene walk.
2. `bhkRigidBodyT` adds its stored translation and rotation. Plain `bhkRigidBody` stores the
   same fields but ignores them.
3. `bhkTransformShape` and `bhkConvexTransformShape` add their `Matrix44`.
4. A compressed mesh chunk may add a `bhkQsTransform` to its vertices.

Real data check: `mineoreiron04.nif` has collision bounds within 1 to 2 units of its render
bounds on each side. City walls follow their render footprint in X and Y but reach higher,
which fits blockers placed on purpose.

## Collision object and body

| Block | Fields read |
| --- | --- |
| `bhkCollisionObject` | Target ref, uint16 flags, rigid body ref |
| `bhkBlendCollisionObject` | The same three, then two blend gain floats (not read) |
| `bhkRigidBody` / `bhkRigidBodyT` | Shape ref, `HavokFilter`, 20-byte world info, response and callback bytes, `bhkRigidBodyCInfo2010`, constraint refs, uint16 body flags |
| `HavokFilter` | uint8 layer, uint8 flags, uint16 group |

The filter flags byte is a bit field (`nif.xml` `CollisionFilterFlags`): bits 0-4 are a
biped part, bit 5 "MOPP Scaled", bit 6 "No Collision", bit 7 "Linked Group". The biped part
has a meaning only on layers `SKYL_BIPED` (8), `SKYL_DEADBIP` (32), and `SKYL_BIPED_NO_CC`
(33). On other layers OpenSky reports no part, not 0, because 0 is itself a part
(`P_OTHER`, which vanilla puts on `NPC Neck`). Every body of the vanilla human
`skeleton.nif` is on layer 8, group 0, with the correct part number. See
[ragdoll self-collision](/engine/ragdoll-solver.md#self-collision).

A body is solid for the player when all of these are true:

- Neither layer is `SKYL_TRIGGER` (12) or `SKYL_NONCOLLIDABLE` (15).
- Neither filter has the "No Collision" bit (`0x40`).
- Both response types are `RESPONSE_SIMPLE_CONTACT` (1).

A trigger volume is a body on layer 12 in either filter. This is not the same as "not
solid": layer 15, the "No Collision" bit, or another response also make a body not solid,
without making it a trigger. Trigger bodies go to the per-cell trigger set for
`OnTriggerEnter` and `OnTriggerLeave`.

## Shape graph

| Block | What OpenSky does |
| --- | --- |
| `bhkMoppBvTreeShape` | Follows the child. Skips the MOPP bytecode |
| `bhkListShape` | Follows each child |
| `bhkTransformShape`, `bhkConvexTransformShape` | Adds the `Matrix44`, follows the child |
| `bhkCompressedMeshShape` | Reads scale and data. Gives big triangles and chunks, below |
| `bhkPackedNiTriStripsShape` | Reads scale and `hkPackedNiTriStripsData` |
| `bhkNiTriStripsShape` | Reads scale and each `NiTriStripsData` |
| `bhkConvexVerticesShape` | Reads vertices and planes. Builds the hull faces once per model |
| `bhkBoxShape` | Half extents |
| `bhkSphereShape` | Radius |
| `bhkCapsuleShape` | End points and the larger of the stored radii |

An unknown shape type is counted. A broken collision root is recorded, and its sibling
roots still decode. The walk stops at depth 64 and rejects loops. Every ref, count, index,
strip, transform index, and triangle total is checked before use. The walk uses an explicit
work stack, like the scene walk in [NIF](/formats/nif.md).

Convex planes: XYZ is the outward normal, with no unit. W is the signed distance and gets
the unit factor. OpenSky groups the vertices on each plane, sorts them around the center,
and makes triangles once per model.

## Compressed mesh

`bhkCompressedMeshShapeData` has, in order: compression data and a bounding box, counted
material arrays, chunk material records, a named material count, 32-byte transforms, big
vertices, 12-byte big triangles, chunks, and a convex piece count.

- Big vertices are float4 XYZ, times the shape scale and the unit factor.
- A big triangle is three uint16 indices, a material index, and welding data.
- A chunk has a translation, a material, a chunk reference, a transform index, uint16 XYZ
  values, an index list, strip lengths, and welding data.

A chunk vertex is:

`point = chunkTranslation + SIMD3(uint16XYZ) / 1000`

Then the chunk transform, if any, then the shape scale and unit factor. Strips alternate
their winding. Indices after all strips are plain triangles.

Vanilla chunks use reference `0xffff` (standalone). Chunks that refer to another chunk are
reported as unsupported.

## Triangle strips

`hkPackedNiTriStripsData` has welded uint16 triangles, float3 or float16 vertices, then
sub-shape rows (`hkSubPartData`: Havok filter, vertex count, material). The sub-shapes split
the vertex array. A triangle belongs to the sub-shape of its first vertex.

`NiTriStripsData` starts with the old `NiGeometryData` fields. One wrong width moves every
later field, so here is the order (`NiGeometryData -> NiTriBasedGeomData ->
NiTriStripsData`):

| Field | Width | Note |
| --- | --- | --- |
| Group ID | uint32 | |
| Num Vertices | uint16 | |
| Keep Flags, Compress Flags | 1 byte each | |
| Has Vertices | 1 byte | 0 is an error for collision |
| Vertices | 12 bytes each | |
| BS Vector Flags | uint16 | Bit 0: one UV set. Bit 12: tangents |
| Material CRC | uint32 | A render material name, not a Havok surface |
| Has Normals | 1 byte | Normals 12 bytes each, then tangents and bitangents 24 each |
| Bounding sphere | 16 bytes | Center and radius |
| Has Vertex Colors | 1 byte | Colors 16 bytes each |
| UV set | 8 bytes each | Once, when bit 0 is set |
| Consistency Flags | uint16 | Not uint32 |
| Additional Data | ref | |
| Num Triangles | uint16 | Must match the triangles built |
| Num Strips, strip lengths | uint16 each | |
| Has Points | 1 byte | |
| Points | uint16 each | The sum of the strip lengths |

Reading Consistency Flags as 4 bytes once lost the collision of the only three vanilla
meshes that use `bhkNiTriStripsShape`: `clutter\coffins\nordiccoffinstatic03`,
`clutter\goatskin\goatpeltstatic`, and `clutter\nightmother\nmbody01`.

## Surface material

Every shape has a `SkyrimHavokMaterial` value. One shape has one material. Where a block
stores several, OpenSky makes one shape per material.

| Block | Material |
| --- | --- |
| `bhkSphereShape`, `bhkBoxShape`, `bhkCapsuleShape`, `bhkConvexVerticesShape` | First uint32 of the shape |
| `bhkNiTriStripsShape` | First uint32 of the shape, for all its strips blocks |
| `bhkPackedNiTriStripsShape` | The sub-shape each triangle is in |
| `bhkCompressedMeshShape` | The chunk material table, per chunk and per big triangle |

A material index past the end of the table gives geometry with no material. The geometry is
kept. `NiTriStripsData`'s Material CRC is not a surface and is skipped. Turning the value
into a `MATT` record needs the plugin. See [material types](/formats/material-type.md).

Real data check: in Tamriel cell (6, -2), every shape's material resolves to a `MATT`.
`mineoreiron04.nif` gives one `MaterialDirt` shape and one `MaterialStone` shape, so the
per-material split works on real data.

## Not done

- MOPP bytecode is not run. The child geometry is used instead.
- Welding data is checked and skipped. Nothing uses it.

`openskycli collision` checks every model of an exterior cell (see [CLI](/tools/cli.md)).
