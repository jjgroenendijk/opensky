---
type: File Format
title: NIF rigid bodies and constraints
description: bhkRigidBodyCInfo2010 dynamics fields, Havok constraint layouts, ragdoll bodies in
  skeleton NIFs, and what vanilla data shows about them.
tags: [format, nif, havok, physics, ragdoll]
---

# NIF rigid bodies and constraints

A Havok rigid body in a NIF carries physics values: mass, inertia, friction, velocity limits.
It can also list constraints (joints) that tie it to another body. Ragdolls are built from
these. The collision shapes are on the [NIF collision](/formats/nif-collision.md) page.

Source: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml): types
`bhkRigidBodyCInfo2010`, `bhkConstraint`, and the per-type constraint info structs.

The runtime is on the [dynamic bodies](/engine/dynamic-bodies.md) and
[ragdoll](/engine/ragdoll.md) pages.

## bhkRigidBodyCInfo2010

Skyrim uses the `2010` variant. The `550_660` and `2014` variants are for older games and
Fallout 4 and are not read. Fields after the response and callback bytes, little-endian:

| Field | Bytes | Notes |
| --- | --- | --- |
| Translation, rotation | 16 + 16 | `Vector4` and `hkQuaternion`. Used only by `bhkRigidBodyT` |
| Linear, angular velocity | 16 + 16 | `Vector4`, W unused |
| Inertia tensor | 48 | `hkMatrix3`: three rows of four floats, the fourth unused |
| Center of mass | 16 | `Vector4`, W unused |
| Mass, linear damping, angular damping | 4 each | |
| Time factor, gravity factor | 4 each | |
| Friction, rolling friction multiplier, restitution | 4 each | |
| Max linear velocity, max angular velocity, penetration depth | 4 each | |
| Motion system, deactivator, solver deactivation, quality | 1 each | `hkMotionType`, `hkDeactivatorType`, `hkSolverDeactivation`, `hkQualityType` |
| Auto remove level, response modifier flags, shape keys, force collided | 1 each | Not read |
| Unused | 12 | |
| Constraint count, refs | 4, then 4 each | Count at most 256 and within the block |
| Body flags | 2 | uint16 when the BS stream is 76 or more. Bit 1: responds to wind |

Units are mixed on purpose:

- The center of mass is a position, so it is converted to engine units (times `69.99125`),
  like every constraint pivot.
- Mass (kg), inertia (kg m^2), velocity limits (m/s and rad/s), and damping (fraction per
  second) stay in SI units. The integrator chooses its own units. A body with half its values
  converted would be worse than one with none converted.
- The inertia tensor is stored in rows. OpenSky transposes it, so it works on column vectors
  like every other rotation.

The four enum bytes are kept raw as well as named. An unknown value survives.

## Movable or static

The motion system byte does not tell movable from static. In vanilla, every exterior body and
many clutter bodies say `MO_SYS_BOX_STABILIZED` with `MO_QUAL_INVALID` and mass 0. That is the
default of the vanilla export tool, not a real choice. So a body counts as simulated only when
its motion system is a known simulated type **and** its mass is positive and finite.

Only four motion systems appear in vanilla: box stabilized, sphere stabilized, box inertia, and
sphere inertia. None use `MO_SYS_DYNAMIC`, `MO_SYS_KEYFRAMED`, `MO_SYS_FIXED`,
`MO_SYS_THIN_BOX`, or `MO_SYS_CHARACTER`.

Vanilla masses are plausible. Clutter bodies range from 0.1 to 700 kg, skeleton bodies from 0.2
to 750 kg. Most are between 1 and 10 kg. This shows the fields are read at the right offsets.

## Constraints

A rigid body lists the joints it belongs to. A joint ties two bodies, and both list it. So the
same block appears twice in a model. OpenSky removes the duplicates. It resolves each end's
`Ptr` to the name of the target node.

Every constraint block starts with `bhkConstraintCInfo`: entity count (always 2, ignored), two
entity pointers, and a `ConstraintPriority`. The per-type data follows in the Fallout 3 and
later order (`since="20.2.0.7"`), which Skyrim uses. The older Oblivion orders in `nif.xml` are
not read.

| Block | Data |
| --- | --- |
| `bhkBallAndSocketConstraint` | Pivot A, pivot B |
| `bhkStiffSpringConstraint` | Pivot A, pivot B, length |
| `bhkHingeConstraint` | Per body: axis, two perpendicular axes, pivot |
| `bhkLimitedHingeConstraint` | The same two frames, then min angle, max angle, max friction, motor |
| `bhkPrismaticConstraint` | Per body: sliding axis, rotation axis, plane normal, pivot. Then min and max distance, friction, motor |
| `bhkRagdollConstraint` | Per body: twist axis, plane normal, motor axis, pivot. Then cone max, plane min and max, twist min and max, max friction, motor |
| `bhkMalleableConstraint` | Wrapped `hkConstraintType`, a repeated constraint info, the wrapped data, strength |

Vectors are `Vector4` with an unused W. Axes have no unit. Pivots, lengths, and prismatic
distances are positions and are converted. Angles are radians. A ragdoll's minimum cone angle
is not stored. `nif.xml` says it is the negative of the maximum.

`bhkConstraintMotorCInfo` starts with an `hkMotorType` byte:

| Type | Data |
| --- | --- |
| 0 | Nothing |
| Position | Six floats and an enabled flag |
| Velocity | Four floats and two flags |
| Spring damper | Four floats and a flag |

An unknown motor type is an error, because the size of the rest of the block is then unknown.

The repeated constraint info inside `bhkMalleableConstraint` is skipped. The outer block already
names the same two bodies, and a second copy that disagrees would give two answers for one
joint. OpenSky unwraps any number of malleable layers to reach the real joint.

A joint that fails to decode costs only that joint. The body and its other joints survive. A
ragdoll with one missing limb is more useful than no ragdoll. An unknown constraint class is
counted as unsupported. Broken bytes in a known class are counted as a decode failure instead,
so "unsupported" keeps meaning "not implemented".

`bhkBreakableConstraint` and `bhkBallSocketConstraintChain` are not read. Vanilla does not use
them.

## Ragdolls in skeleton NIFs

There is no special ragdoll container in a Skyrim skeleton NIF. Each bone's body hangs from a
`bhkBlendCollisionObject`. The bone is simply the name of the `NiNode` that the collision object
targets. So a joint's two entity pointers give the pair of bones it ties.

In vanilla skeletons, almost every body hangs from a `bhkBlendCollisionObject`, and every joint
names a bone at both ends.

Only two constraint classes build the vanilla ragdolls: `bhkRagdollConstraint` and
`bhkLimitedHingeConstraint`. The pairs make sense for a body. Knees and elbows
(`Bip01 L Calf -> Bip01 L Thigh`, `Bip01 L Forearm -> Bip01 L UpperArm`) are limited hinges.
Shoulders and hips are ragdoll cones. Some hanging clutter props also use limited hinges.
`bhkBallAndSocketConstraint`, `bhkStiffSpringConstraint`, `bhkPrismaticConstraint`, and
`bhkMalleableConstraint` decode, but vanilla does not use them.
