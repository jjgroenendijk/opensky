---
type: File Format
title: NIF Havok collision
description: Skyrim SE bhk collision graph layouts, rigid-body dynamics and constraints,
  and clean engine geometry conversion.
tags: [format, nif, havok, collision, geometry, physics, ragdoll]
timestamp: 2026-08-06T00:00:00Z
---

# NIF Havok collision

Skyrim NIFs attach Havok data to scene objects through a collision-object ref. OpenSky
follows each collision-object root into rigid-body metadata + shape graph, then emits
engine-unit triangle soups or convex primitives. Disk refs, padding, MOPP bytecode,
material tables, quantized chunks stay inside `Formats/NIF/`.

Primary spec: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml),
types `bhkNiCollisionObject`, `bhkWorldObject`, `bhkEntity`,
`bhkRigidBodyCInfo2010`, `bhkConstraint` and its per-type CInfo structs, shape types
below, `bhkCMSChunk`, `bhkCMSBigTri`,
`bhkQsTransform`, `hkPackedNiTriStripsData`, `NiTriStripsData`. Compressed-chunk
dequantization + strip interpretation cross-checked against open-source
[PyNifly/nifly](https://github.com/BadDogSkyrim/PyNifly/blob/main/NiflyDLL/NiflyWrapper.cpp).
Impl: `opensky/Engine/Formats/NIF/NIFCollision*.swift`,
`NIFRigidBody*.swift`, `NIFConstraintDecoder.swift`, `NIFDynamicsCensus.swift`.

## Contents

* Units + transforms
* Root + rigid body
* Rigid-body dynamics
* Constraints
* Ragdoll carriers
* Shape graph
* Compressed mesh
* Alternate triangle collections
* Production probe
* Dynamics census
* Current boundary
* Surface material

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
| `bhkBlendCollisionObject` | the same three fields; two trailing blend-gain floats unread |
| `bhkRigidBody`/`T` | shape ref, `HavokFilter`, 20-byte world-info tail, entity response + callback bytes, the whole `bhkRigidBodyCInfo2010`, constraint refs, uint16 body flags |
| `HavokFilter` | uint8 layer, uint8 flags, uint16 group |

Engine body preserves object flags, both serialized filters, both response types, the
inertial tail, joints, body flags, target ref and name, composed transform, and shapes.
Only `bhkRigidBodyT` applies its serialized translation and rotation; a plain
`bhkRigidBody` stores the same fields and ignores them.
Player-solid policy requires both layers
outside `SKYL_TRIGGER` (12) + `SKYL_NONCOLLIDABLE` (15), neither filter's
`No Collision` bit (`0x40`), both responses equal `RESPONSE_SIMPLE_CONTACT` (`1`). Other
bodies remain decoded + counted but query consumers filter them.

`isTriggerVolume` is the separate, narrower predicate for `SKYL_TRIGGER` (12) on either
filter. It is not the negation of `isPlayerSolid` — layer 15, the `No Collision` bit, and a
non-simple response also fail solidity without naming a trigger. A layer-12 body is no
longer discarded once the solid build rejects it: it routes to the per-cell trigger set in
[static collision world](/engine/collision-world.md), which places it and answers capsule
overlap for `OnTriggerEnter`/`OnTriggerLeave`.

## Rigid-body dynamics

Skyrim streams take the `bhkRigidBodyCInfo2010` branch; the `550_660` and `2014` variants
belong to pre-Skyrim and Fallout 4 and are not read. Field order after the response and
callback bytes, all little-endian:

| field | bytes | notes |
| --- | --- | --- |
| translation, rotation | 16 + 16 | `Vector4` + `hkQuaternion`; the `T` transform |
| linear, angular velocity | 16 + 16 | `Vector4`, W unused |
| inertia tensor | 48 | `hkMatrix3`: three rows of four floats, fourth unused |
| center of mass | 16 | `Vector4`, W unused |
| mass, linear damping, angular damping | 4 each | |
| time factor, gravity factor | 4 each | |
| friction, rolling friction multiplier, restitution | 4 each | |
| max linear velocity, max angular velocity, penetration depth | 4 each | |
| motion system, deactivator, solver deactivation, quality | 1 each | `hkMotionType`, `hkDeactivatorType`, `hkSolverDeactivation`, `hkQualityType` |
| auto remove level, response modifier flags, shape keys, force-collided flag | 1 each | unread |
| unused tail | 12 | |
| constraint count + refs | 4 + 4 each | count capped at 256 and against block size |
| body flags | 2 | uint16 for BS stream >= 76; bit 1 = responds to wind |

Units are mixed deliberately and `NIFRigidBodyDynamics` says which each field is. Positions
— the center of mass, like every constraint pivot — convert to engine units through the
same `69.99125` factor. Mass in kilograms, inertia in kg m^2, the velocity ceilings in
m/s and rad/s, and damping as a per-second fraction all stay in the file's own SI units,
because the integrator picks its own working units and a half-converted body is worse than
an unconverted one. The inertia tensor is stored in rows and transposed on read, so it
applies to column vectors like every other rotation here.

The four enum bytes are kept raw as well as named, so an unknown or modded value survives
to the census instead of being clamped. `NIFRigidBodyDynamics.isSimulated` is the
conservative predicate: a *known* simulated motion system with a positive finite mass. The
census below is why it also tests the mass — the motion byte alone does not separate
movable from static in shipped data.

## Constraints

A `bhkRigidBody` lists refs to the joints it takes part in. A joint binds two bodies and
both of them list it, so the same block appears twice in a model;
`NIFCollisionModel.constraints` is the de-duplicated view and `boneNames(of:)` resolves
each end's `Ptr` back to the target node name.

Every constraint block opens with `bhkConstraintCInfo` — entity count (hardcoded 2, read
and discarded), two entity pointers, `ConstraintPriority` — then the per-type payload in
the Fallout 3 and later field order (`since="20.2.0.7"`), which is the branch Skyrim takes.
The Oblivion-era orders in `nif.xml` are deliberately not implemented.

| block | payload |
| --- | --- |
| `bhkBallAndSocketConstraint` | pivot A, pivot B |
| `bhkStiffSpringConstraint` | pivot A, pivot B, length |
| `bhkHingeConstraint` | per body: axis, two perpendicular axes, pivot |
| `bhkLimitedHingeConstraint` | the same two frames, then min angle, max angle, max friction, motor |
| `bhkPrismaticConstraint` | per body: sliding axis, rotation axis, plane normal, pivot; then min distance, max distance, friction, motor |
| `bhkRagdollConstraint` | per body: twist axis, plane normal, motor axis, pivot; then cone max, plane min/max, twist min/max, max friction, motor |
| `bhkMalleableConstraint` | wrapped `hkConstraintType`, a repeated constraint info, the wrapped payload, strength |

Each frame's vectors are `Vector4` with an unused W. Axes are unit-length and unitless;
pivots, lengths and prismatic distances are positions and convert to engine units; angles
are radians. A ragdoll's cone *minimum* angle is not stored — `nif.xml` records it as the
negation of the maximum.

`bhkConstraintMotorCInfo` is a leading `hkMotorType` byte selecting one of three payloads:
position (six floats plus an enabled flag), velocity (four floats plus two flags), spring
damper (four floats plus a flag). Type 0 stores nothing further. An unknown motor type
throws rather than guessing a payload length, because the rest of the block would be
unreadable either way.

Malleable's repeated constraint info is skipped: the outer block already bound the same two
bodies, and honoring a disagreeing copy would leave two answers for one joint.
`NIFConstraintData.unwrapped` reaches the joint under any number of wrappers.

A joint that fails to decode costs only that joint — the body and its sibling joints
survive, because a ragdoll missing one limb is more useful than no ragdoll. A constraint
*class* the decoder does not read is tallied in `unsupportedReachableBlocks`; malformed
bytes in a class it does read are recorded as a decode failure and deliberately leave that
tally alone, so "unsupported" keeps meaning missing coverage.

## Ragdoll carriers

There is no dedicated ragdoll container class in a Skyrim skeleton NIF. The per-bone bodies
hang off `bhkBlendCollisionObject`, which inherits `bhkCollisionObject` and appends two
blend-gain floats, and the bone mapping is simply the name of the `NiNode` each carrier
targets. Scene traversal records that name next to the transform, so
`NIFCollisionBody.targetName` is the bone and `NIFCollisionModel.boneNames(of:)` turns a
joint's entity pointers into the bone pair it binds. Confirmed against the install by the
census below, not assumed: 1193 of the 1196 skeleton bodies swept hang off
`bhkBlendCollisionObject`, and all 1136 skeleton joints name a bone on both ends.

## Shape graph

| block | conversion |
| --- | --- |
| `bhkMoppBvTreeShape` | follow child; skip MOPP acceleration bytecode |
| `bhkListShape` | recurse over child refs |
| `bhkTransformShape`, `bhkConvexTransformShape` | compose `Matrix44`, recurse |
| `bhkCompressedMeshShape` | read shape scale + data ref; emit big-triangle + per-chunk soups |
| `bhkPackedNiTriStripsShape` | read scale + `hkPackedNiTriStripsData`; emit indexed soup |
| `bhkNiTriStripsShape` | read scale + each `NiTriStripsData`; emit indexed soups |
| `bhkConvexVerticesShape` | read vertices + half-space planes; derive hull faces once/model |
| `bhkBoxShape` | preserve half extents |
| `bhkSphereShape` | preserve radius |
| `bhkCapsuleShape` | preserve endpoints + max of serialized radii |

Reachable unknown shape types are counted by block type. One malformed collision root adds
a block-indexed failure; sibling roots continue decoding. Shape-graph depth caps at 64;
active-path set rejects cycles; every ref, count, vertex index, strip partition, transform
index, and declared triangle total validates before allocation/output. The shape walk and
the scene-target walk both descend through the shared explicit work stack described in
[NIF](/formats/nif.md), so depth costs heap rather than call frames (issue #388).

Convex plane XYZ is unitless exterior normal; W is signed plane distance and receives Havok
unit conversion. Face derivation groups vertices on each serialized half-space, orders each
face around its centroid, then triangulates once in decoded model cache. Placed REFRs share
those clean engine indices; no point-triple search runs during cell composition.

## Compressed mesh

`bhkCompressedMeshShapeData` opens with compression metadata + AABB, then counted material
arrays, chunk-material records, named-material count, 32-byte transforms, big vertices,
12-byte big triangles, chunks, trailing convex-piece count.

Big vertices are float4 XYZ, multiplied by shape scale + unit scale. Big triangles carry
three uint16 indices, material index, welding info. Each chunk holds translation, material,
chunk reference, transform index, flattened uint16 XYZ component array, index array, strip
lengths, welding array. Both material fields index the chunk-material table, so a mesh whose
chunk is snow and whose big triangles are stone emits two soups rather than one; an index
past the end of the table leaves the geometry with no material rather than dropping it.
Vanilla standalone chunks use reference `0xffff`; cross-chunk refs remain reported
unsupported. Vertex reconstruction:

`point = chunkTranslation + SIMD3(uint16XYZ) / 1000`

Optional chunk transform follows, then shape scale + unit scale. Strip triangles alternate
winding; indices after all strips are independent triples. Synthetic fixture combines one
big triangle, one 4-index strip, one trailing triangle, quantized translation, transform.

## Alternate triangle collections

`hkPackedNiTriStripsData` supplies welded uint16 triangle triples, float3 or float16
vertices, then fixed-size sub-shape rows (`hkSubPartData`: Havok filter, vertex count,
material). The sub-shapes partition the vertex array, so the decoder assigns each triangle
to the sub-shape its first vertex falls in and emits one soup per sub-shape that owns any.
`NiTriStripsData` uses legacy `NiGeometryData` prefix; decoder skips optional
normals/tangents/colors/UVs by validated flags, then expands
each strip with alternating winding. Declared triangle count must match emitted triangles.

The prefix in field order, since one wrong width silently walks every later field
(`nif.xml` `NiGeometryData` -> `NiTriBasedGeomData` -> `NiTriStripsData`):

| field | width | note |
| --- | --- | --- |
| Group ID | uint32 | |
| Num Vertices | uint16 | |
| Keep Flags, Compress Flags | byte each | |
| Has Vertices | byte | zero here is malformed for a collision shape |
| Vertices | 12 bytes each | |
| BS Vector Flags | uint16 | bit 0 = one UV set, bit 12 = tangents |
| Material CRC | uint32 | a render material name, not a Havok surface |
| Has Normals | byte | normals 12 bytes each, then tangents + bitangents 24 each |
| Bounding sphere | 16 bytes | `NiBound`: center + radius |
| Has Vertex Colors | byte | colors 16 bytes each |
| UV set | 8 bytes each | present once when bit 0 is set |
| Consistency Flags | uint16 | a `ConsistencyType` enum, **not** a uint32 |
| Additional Data | ref | |
| Num Triangles | uint16 | |
| Num Strips, strip lengths | uint16 each | |
| Has Points | byte | |
| Points | uint16 each | `sum(strip lengths)` of them |

Reading Consistency Flags four bytes wide put the strip table two bytes late, which cost the
three vanilla meshes that use `bhkNiTriStripsShape` their collision root
(`clutter\coffins\nordiccoffinstatic03`, `clutter\goatskin\goatpeltstatic`,
`clutter\nightmother\nmbody01` — issue #376). They are the only blocks in the install that
reach this decoder at all, so no other asset covered the mistake and the census sweep is what
surfaced it. The synthetic fixture had the same width, so the unit tests agreed with the bug;
`NIFCollisionFixture.niTriStripsDataFullPrefix()` now builds a block carrying every optional
array, which is the shape the vanilla blocks have.

## Production probe

`openskycli collision` resolves every unique model used by target exterior cell, loads via
VFS, reports roots/bodies/shapes/triangles, filtered bodies, unsupported reachable types,
decode failures, per-model surface materials, collision bounds, render bounds. It then uses
production placement +
[collision world](/engine/collision-world.md) for requested radius grid. Non-zero exit on
any load/decode/unsupported/empty-root failure.

Tamriel `(6,-2)` probe on 2026-07-19: 9 unique vanilla models; 7 collision-bearing;
12 roots/bodies, 13 shapes, 583 triangles; 0 filtered bodies, 0 unsupported reachable
blocks, 0 decode failures. Both LOD-only building models correctly carry no collision.

Re-run on 2026-08-05 with materials decoded: every shape on all seven collision-bearing
models names a Havok material that resolves to a real `MATT`, none unresolved. Six of the
seven are `MaterialStone` throughout; `mineoreiron04.nif` comes out as one `MaterialDirt`
shape plus one `MaterialStone` shape, which is the compressed-mesh per-material split
working on real data rather than only on a fixture.

## Dynamics census

`NIFDynamicsCensusRealDataTests` sweeps three populations against the user's own install
and writes counts, names, and paths to gitignored `logs/nif-dynamics-census.log`. Run with
`make realtest T='NIFDynamicsCensusRealDataTests/censusesHavokDynamics()'`. Headline
numbers, 2026-08-06, six Tamriel cells around `(6,-2)` plus every `meshes\clutter\` mesh
and every actor skeleton:

| sweep | models | bodies | simulated | joints |
| --- | --- | --- | --- | --- |
| exterior cell models | 54 | 44 | 0 | 0 |
| clutter meshes | 1746 | 1781 | 754 | 146 |
| actor skeletons | 72 | 1196 | 1193 | 1136 |

Four findings that fix decisions above this layer:

* **The motion byte does not separate movable from static.** Every exterior body and 975 of
  the clutter bodies read `MO_SYS_BOX_STABILIZED` with `MO_QUAL_INVALID` and zero mass —
  the vanilla exporter's default, not a statement of intent. Mass and collision layer are
  the discriminators; a consumer that trusts the motion system alone treats 1027 immovable
  bodies as dynamic.
* **Four motion systems appear at all**: box and sphere stabilized, box and sphere inertia.
  Nothing in the sweep uses `MO_SYS_DYNAMIC`, `MO_SYS_KEYFRAMED`, `MO_SYS_FIXED`,
  `MO_SYS_THIN_BOX`, or `MO_SYS_CHARACTER`.
* **Masses are plausible and bounded.** Clutter runs 0.1 to 700 kg over 754 bodies
  (mean 13.9); skeleton bodies run 0.2 to 750 kg over 1193 (mean 20.0). Both distributions
  peak in the 1-10 kg decade, which is the direct evidence that the inertial tail is being
  read at the right offset.
* **Two constraint classes carry the ragdolls**, and only two: 624 `bhkRagdollConstraint`
  and 512 `bhkLimitedHingeConstraint` across 751 distinct bone pairs, zero unbound ends.
  The pairs are anatomically coherent — `Bip01 L Calf -> Bip01 L Thigh` and
  `Bip01 L Forearm -> Bip01 L UpperArm` are limited hinges, shoulders and hips are ragdoll
  cones. Clutter adds 141 limited hinges, 3 hinges, and 2 ragdolls on hanging props.
  `bhkBallAndSocketConstraint`, `bhkStiffSpringConstraint`, `bhkPrismaticConstraint`, and
  `bhkMalleableConstraint` decode but appear nowhere in the sweep.

Three clutter meshes fail to decode, all in triangle-strip geometry that predates this
work and none of it rigid-body or constraint data:
`nordiccoffinstatic03.nif`, `goatpeltstatic.nif`, `nmbody01.nif` (issue #376).

## Current boundary

Decoder does not execute MOPP bytecode; MOPP child geometry is authoritative. Per-cell
spatial index lives above format layer in [collision world](/engine/collision-world.md).
Welding metadata is still validated and skipped: nothing consumes it.

The rigid-body dynamics fields are consumed by
[dynamic rigid bodies](/engine/dynamic-bodies.md) (item 15.2), which is also where the
census's mass-not-motion-byte finding is acted on. The constraints are decoded but not
solved: instantiating a ragdoll from these joints is item 15.6. `bhkBreakableConstraint` and
`bhkBallSocketConstraintChain` are the two constraint classes still unread — neither
appears in the census, and both would be tallied as unsupported if a mod introduced one.
The rigid body's auto-remove level, response modifier flags, contact-point shape key count,
and force-collided flag are skipped: nothing consumes them.

## Surface material

Every shape kind carries a `SkyrimHavokMaterial` and `NIFCollisionShape.material` keeps it
raw (issue #358). One shape means one material — where a block stores several, the decoder
emits one shape per material rather than a per-triangle table, because those blocks already
partition their geometry that way. Where each kind stores it:

| block | material source |
| --- | --- |
| `bhkSphereShape`, `bhkBoxShape`, `bhkCapsuleShape`, `bhkConvexVerticesShape` | first uint32 of the shape |
| `bhkNiTriStripsShape` | first uint32 of the shape, shared by every strips block under it |
| `bhkPackedNiTriStripsShape` | the `hkSubPartData` sub-shape each triangle falls in |
| `bhkCompressedMeshShape` | the chunk-material table, indexed per chunk and per big triangle |

`NiTriStripsData`'s own material CRC is a render material name, not a Havok surface, and
stays skipped. Resolving a value to a `MATT` record is not a NIF concern — that needs the
plugin, and belongs to [material types](/formats/material-type.md).
