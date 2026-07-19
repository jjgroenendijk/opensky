---
type: File Format
title: NIF Havok collision
description: Skyrim SE bhk collision graph layouts and clean engine geometry conversion.
tags: [format, nif, havok, collision, geometry]
timestamp: 2026-07-19T00:00:00Z
---

# NIF Havok collision

Static Skyrim NIFs attach Havok data to scene objects through a collision-object ref.
OpenSky follows each `bhkCollisionObject` root into rigid-body metadata + shape graph,
then emits engine-unit triangle soups or convex primitives. Disk refs, padding, MOPP
bytecode, material tables, quantized chunks stay inside `Formats/NIF/`.

Primary spec: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml),
types `bhkNiCollisionObject`, `bhkWorldObject`, `bhkEntity`,
`bhkRigidBodyCInfo2010`, shape types below, `bhkCMSChunk`, `bhkCMSBigTri`,
`bhkQsTransform`, `hkPackedNiTriStripsData`, `NiTriStripsData`. Compressed-chunk
dequantization + strip interpretation cross-checked against open-source
[PyNifly/nifly](https://github.com/BadDogSkyrim/PyNifly/blob/main/NiflyDLL/NiflyWrapper.cpp).
Impl: `opensky/Formats/NIF/NIFCollision*.swift`.

## Units + transforms

Havok stores metres; renderer/ESM use Skyrim units. Every Havok position, translation,
half extent, and radius multiplies by `69.99125` engine units/metre. Rotations + per-shape
scale stay unitless. Matrix convention remains column-vector `parent * local`.

Transform composition:

1. Scene traversal records target `NiAVObject` model transform.
2. `bhkRigidBodyT` appends serialized `bhkRigidBodyCInfo2010` translation + quaternion;
   plain `bhkRigidBody` does not.
3. `bhkTransformShape`/`bhkConvexTransformShape` append their `Matrix44`.
4. Compressed chunk optional `bhkQsTransform` acts on dequantized chunk vertices.

Synthetic transform tests cover non-zero target, rigid-body, both wrappers, and chunk
transform. Real Whiterun probe validates scale: `mineoreiron04.nif` collision bounds differ
from render bounds by about 1-2 units per face. City-wall collision follows render X/Y
footprints while extending above visible geometry, consistent with deliberate blockers.

## Root + rigid body

Resolved SSE field order:

| block | fields consumed |
| --- | --- |
| `bhkCollisionObject` | target ref, uint16 object flags, rigid-body ref |
| `bhkRigidBody`/`T` | shape ref, `HavokFilter`, 20-byte world-info tail, entity response + callback bytes, `bhkRigidBodyCInfo2010` filter/response/transform prefix, motion system |
| `HavokFilter` | uint8 layer, uint8 flags, uint16 group |

Engine body preserves object flags, both serialized filters, both response types, motion
system, target ref, composed transform, shapes. Player-solid policy requires both layers
outside `SKYL_TRIGGER` (12) + `SKYL_NONCOLLIDABLE` (15), neither filter's
`No Collision` bit (`0x40`), both responses equal `RESPONSE_SIMPLE_CONTACT` (`1`). Other
bodies remain decoded + counted but query consumers filter them.

## Shape graph

| block | conversion |
| --- | --- |
| `bhkMoppBvTreeShape` | follow child; skip MOPP acceleration bytecode |
| `bhkListShape` | recurse over child refs |
| `bhkTransformShape`, `bhkConvexTransformShape` | compose `Matrix44`, recurse |
| `bhkCompressedMeshShape` | read shape scale + data ref; emit big-triangle + per-chunk soups |
| `bhkPackedNiTriStripsShape` | read scale + `hkPackedNiTriStripsData`; emit indexed soup |
| `bhkNiTriStripsShape` | read scale + each `NiTriStripsData`; emit indexed soups |
| `bhkConvexVerticesShape` | preserve vertex cloud as convex primitive |
| `bhkBoxShape` | preserve half extents |
| `bhkSphereShape` | preserve radius |
| `bhkCapsuleShape` | preserve endpoints + max of serialized radii |

Reachable unknown shape types are counted by block type. One malformed collision root adds
a block-indexed failure; sibling roots continue decoding. Recursion depth caps at 64;
active-path set rejects cycles; every ref, count, vertex index, strip partition, transform
index, and declared triangle total validates before allocation/output.

## Compressed mesh

`bhkCompressedMeshShapeData` opens with compression metadata + AABB, then counted material
arrays, chunk-material records, named-material count, 32-byte transforms, big vertices,
12-byte big triangles, chunks, trailing convex-piece count.

Big vertices are float4 XYZ, multiplied by shape scale + unit scale. Big triangles carry
three uint16 indices, material index, welding info. Each chunk holds translation, material,
chunk reference, transform index, flattened uint16 XYZ component array, index array, strip
lengths, welding array. Vanilla standalone chunks use reference `0xffff`; cross-chunk refs
remain reported unsupported. Vertex reconstruction:

`point = chunkTranslation + SIMD3(uint16XYZ) / 1000`

Optional chunk transform follows, then shape scale + unit scale. Strip triangles alternate
winding; indices after all strips are independent triples. Synthetic fixture combines one
big triangle, one 4-index strip, one trailing triangle, quantized translation, transform.

## Alternate triangle collections

`hkPackedNiTriStripsData` supplies welded uint16 triangle triples, float3 or float16
vertices, then fixed-size sub-shape rows. `NiTriStripsData` uses legacy `NiGeometryData`
prefix; decoder skips optional normals/tangents/colors/UVs by validated flags, then expands
each strip with alternating winding. Declared triangle count must match emitted triangles.

## Production probe

`openskycli collision` resolves every unique model used by target exterior cell, loads via
VFS, reports roots/bodies/shapes/triangles, filtered bodies, unsupported reachable types,
decode failures, collision bounds, render bounds. It then uses production placement +
[collision world](/engine/collision-world.md) for requested radius grid. Non-zero exit on
any load/decode/unsupported/empty-root failure.

Tamriel `(6,-2)` probe on 2026-07-19: 9 unique vanilla models; 7 collision-bearing;
12 roots/bodies, 13 shapes, 583 triangles; 0 filtered bodies, 0 unsupported reachable
blocks, 0 decode failures. Both LOD-only building models correctly carry no collision.

## Current boundary

Decoder does not execute MOPP bytecode; MOPP child geometry is authoritative. Per-cell
spatial index lives above format layer in [collision world](/engine/collision-world.md).
Collision materials/welding metadata are validated/skipped because player queries currently
need geometry + solidity only.
