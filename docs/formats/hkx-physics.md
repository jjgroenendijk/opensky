---
type: File Format
title: HKX Physics Classes
description: Member offsets of the Havok physics, ragdoll, and resource classes in Skyrim SE
  skeleton files, and how they were confirmed on the install.
tags: [format, havok, hkx, physics]
---

# HKX physics classes

A skeleton file such as `skeleton.hkx` holds more than bones. It also holds the ragdoll: one
rigid body per ragdoll bone, the joints between them, and a mapper between the ragdoll and the
animation rig. Some clip files hold resource and reference-frame classes beside the animation.

Reference: [ret2end/HKX2Library](https://github.com/ret2end/HKX2Library) (MIT), commit
`5156f4f2`, which lists every member of the Skyrim SE 64-bit classes with its offset. The
[class signatures](/formats/hkx-class-signatures.md) page confirms that this Havok version
matches. All integers are little-endian. Offsets are from the start of the object.

## Small types

| Type | Size | Layout |
| --- | --- | --- |
| `hkTransform` | 64 | Three rotation columns, then the translation, each a 16-byte vector |
| `hkQsTransform` | 48 | Translation, rotation quaternion, scale |
| `hkHalf` | 2 | The upper 16 bits of a 32-bit float |

The install confirms `hkHalf`: every `m_gravityFactor` reads `0x3F80`, which is the top half of
1.0.

## Rigid bodies and joints

`hkpRigidBody`, size 720. OpenSky reads only what a ragdoll needs:

| Offset | Member |
| --- | --- |
| 0x20 | `m_collidable.m_shape` (pointer) |
| 0x4C | `m_collidable.m_broadPhaseHandle.m_collisionFilterInfo` |
| 0xB0 | `m_name` |
| 0xD0 | `m_material.m_responseType` |
| 0xD4, 0xD8 | `m_material.m_friction`, `m_material.m_restitution` |
| 0x160 | `m_motion.m_type` |
| 0x170 | `m_motion.m_motionState.m_transform` (`hkTransform`) |
| 0x1F0 | `m_motion.m_motionState.m_sweptTransform.m_centerOfMassLocal` |
| 0x214, 0x216 | `m_linearDamping`, `m_angularDamping` (`hkHalf`) |
| 0x220 | `m_motion.m_inertiaAndMassInv`: the inverse inertia diagonal, then the inverse mass |
| 0x282 | `m_motion.m_gravityFactor` (`hkHalf`) |

`hkpConstraintInstance`, size 112: `m_data` at 0x18, `m_entities[0]` and `m_entities[1]` at 0x28
and 0x30, `m_priority` at 0x38, `m_name` at 0x50.

A constraint data object is a list of atoms. Each atom starts with its `uint16` type. Both joint
classes start with `hkpSetLocalTransformsConstraintAtom` at 0x20, which holds `m_transformA` at
0x30 and `m_transformB` at 0x70: the joint pivot in each body's space.

| Class | Size | Member offsets |
| --- | --- | --- |
| `hkpRagdollConstraintData` | 384 | Motors 0x100, 0x108, 0x110; friction torque 0x128; twist limit enabled 0x12E, angles 0x134; cone limit 0x142, 0x148; plane limit 0x156, 0x15C |
| `hkpLimitedHingeConstraintData` | 272 | Motor 0xD0; friction torque 0xE0; limit enabled 0xE6, angles 0xE8 |
| `hkpPositionConstraintMotor` | 48 | `m_minForce` 0x18, `m_maxForce` 0x1C, `m_tau` 0x20, `m_damping` 0x24, recovery velocities 0x28 and 0x2C |

An angle limit is an enabled byte, then the minimum and maximum angle in radians.

## Shapes

Every convex shape starts with `m_userData` at 0x10, `m_type` at 0x18, and `m_radius` at 0x20.

| Class | Size | Members |
| --- | --- | --- |
| `hkpCapsuleShape` | 80 | `m_vertexA` 0x30, `m_vertexB` 0x40 |
| `hkpBoxShape` | 64 | `m_halfExtents` 0x30 |
| `hkpConvexTranslateShape` | 80 | Child 0x30, `m_translation` 0x40 |
| `hkpConvexTransformShape` | 128 | Child 0x30, `m_transform` 0x40 (`hkTransform`) |
| `hkpConvexVerticesShape` | 144 | AABB half extents 0x30, centre 0x40, rotated vertices 0x50, count 0x60, planes 0x78, connectivity 0x88 |
| `hkpConvexVerticesConnectivity` | 48 | `m_vertexIndices` 0x10, `m_numVerticesPerFace` 0x20 |
| `hkpListShape` | 144 | `m_childInfo` 0x30, AABB half extents 0x50, centre 0x60 |
| `hkpMoppBvTreeShape` | 112 | `m_code` 0x28, child 0x58 |
| `hkpMoppCode` | 64 | `m_info.m_offset` 0x10, `m_data` 0x20, `m_buildType` 0x30 |
| `hkpShapeInfo` | 128 | `m_shape` 0x10, `m_isHierarchicalCompound` 0x18, `m_childShapeNames` 0x20 |

`hkpConvexVerticesShape` stores its vertices rotated: four vertices share three 16-byte vectors,
one for each axis.

## Ragdoll containers

| Class | Size | Members |
| --- | --- | --- |
| `hkaRagdollInstance` | 80 | Bodies 0x10, constraints 0x20, `m_boneToRigidBodyMap` 0x30, skeleton 0x40 |
| `hkaSkeletonMapper` | 144 | Skeletons A and B 0x10 and 0x18; simple mappings 0x20; chain mappings 0x30; unmapped bones 0x40; `m_keepUnmappedLocal` 0x80; `m_mappingType` 0x84 |
| `hkpPhysicsData` | 40 | `m_systems` 0x18 |
| `hkpPhysicsSystem` | 104 | Bodies 0x10, constraints 0x20, `m_name` 0x50, `m_active` 0x60 |

## Resource and clip classes

| Class | Size | Members |
| --- | --- | --- |
| `hkMemoryResourceContainer` | 64 | `m_name` 0x10, handles 0x20, children 0x30 |
| `hkMemoryResourceHandle` | 48 | `m_variant` 0x10, `m_name` 0x18 |
| `hkaDefaultAnimatedReferenceFrame` | 80 | `m_up` 0x10, `m_forward` 0x20, `m_duration` 0x30, samples 0x38 |
| `hkaInterleavedUncompressedAnimation` | 88 | `m_duration` 0x14, track counts 0x18 and 0x1C, `m_transforms` 0x38, `m_floats` 0x48 |

## Confirmed on the install

A real-data sweep decodes every physics object in every `.hkx` of the vanilla archives and
checks it:

- Every transform is finite, and its rotation keeps lengths.
- Every dynamic body has a mass above 0. A keyframed body (motion type 4) or a fixed body
  (motion type 5) may have mass 0, because forces never move it. The install has such bodies.
- Every convex vertex lies inside the shape's box, within 5 % of its largest half extent or
  0.01 units, whichever is larger. The stored box is rounded, so an exact test fails.
- Every pointer resolves to an object of the class the member expects.
- Every object of one joint class has the same list of atom types.
- Every gravity factor is 1.

The sweep finds no fault.
