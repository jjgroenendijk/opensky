---
type: File Format
title: NIF rigid bodies and constraints
description: Skyrim SE bhkRigidBodyCInfo2010 dynamics, bhk constraint layouts, ragdoll
  carriers, and what the vanilla data shows about them.
tags: [format, nif, havok, physics, ragdoll, constraints]
---

# NIF rigid bodies and constraints

A `bhkRigidBody` holds the physics values of a body (mass, damping, friction) and links to
its joints (constraints). This page covers those values and the joint layouts. The
collision object, filters, and shapes are in [NIF Havok collision](/formats/nif-collision.md).
See [dynamic rigid bodies](/engine/dynamic-bodies.md) and [ragdoll](/engine/ragdoll.md) for
how they are simulated.

Source: NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml),
`bhkRigidBodyCInfo2010`, `bhkConstraint`, and the constraint info structs.

## Rigid body values

Skyrim uses `bhkRigidBodyCInfo2010`. The `550_660` and `2014` versions are for older games
and Fallout 4, and OpenSky does not read them. After the response and callback bytes, in
order, little-endian:

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
| Constraint count and refs | 4 + 4 each | Count at most 256, and must fit the block |
| Body flags | 2 | uint16 for BS stream 76 and later. Bit 1: responds to wind |

Units:

- Positions (center of mass, and every joint pivot) are converted with the `69.99125`
  factor, like collision.
- Mass (kg), inertia (kg m^2), velocity limits (m/s and rad/s), and damping (fraction per
  second) stay in SI units. The physics step chooses its own units, and a half-converted
  body is worse than an unconverted one.
- The inertia tensor is stored by rows. OpenSky transposes it, so it works on column
  vectors like every other rotation.

OpenSky keeps the four enum bytes raw as well as named, so a modded value is not lost.

## A body is simulated when it has mass

The motion system byte alone does not tell a moving body from a fixed one. Every exterior
body and about 1,000 clutter bodies say `MO_SYS_BOX_STABILIZED` with `MO_QUAL_INVALID` and
mass 0. This is the vanilla exporter's default, not a choice. So OpenSky treats a body as
simulated only when it has a known simulated motion system and a positive, finite mass.

Only four motion systems appear in vanilla: box and sphere stabilized, and box and sphere
inertia. `MO_SYS_DYNAMIC`, `MO_SYS_KEYFRAMED`, `MO_SYS_FIXED`, `MO_SYS_THIN_BOX`, and
`MO_SYS_CHARACTER` do not appear.

Masses are sensible. Clutter runs from 0.1 to 700 kg, and skeleton bodies from 0.2 to 750
kg. Both peak between 1 and 10 kg. This shows the values are read at the right offset.

## Constraints

A body lists refs to the joints it is part of. A joint links two bodies, and both list it,
so the same block appears twice in a model. OpenSky keeps each joint once, and maps each
end back to the name of its target node.

Every constraint starts with `bhkConstraintCInfo`: an entity count (always 2, read and
ignored), two entity pointers, and a priority. Then comes the data for the type, in the
Fallout 3 and later order (`since="20.2.0.7"`), which Skyrim uses. The older Oblivion
orders in `nif.xml` are not read.

| Block | Data |
| --- | --- |
| `bhkBallAndSocketConstraint` | Pivot A, pivot B |
| `bhkStiffSpringConstraint` | Pivot A, pivot B, length |
| `bhkHingeConstraint` | Per body: axis, two perpendicular axes, pivot |
| `bhkLimitedHingeConstraint` | The same two frames, then min angle, max angle, max friction, motor |
| `bhkPrismaticConstraint` | Per body: sliding axis, rotation axis, plane normal, pivot; then min distance, max distance, friction, motor |
| `bhkRagdollConstraint` | Per body: twist axis, plane normal, motor axis, pivot; then cone max, plane min and max, twist min and max, max friction, motor |
| `bhkMalleableConstraint` | Inner constraint type, a repeated constraint info, the inner data, strength |

Every frame vector is a `Vector4` with an unused W. Axes have no unit. Pivots, lengths, and
prismatic distances are positions and are converted. Angles are radians. A ragdoll cone has
no stored minimum; `nif.xml` says it is minus the maximum.

The motor (`bhkConstraintMotorCInfo`) starts with a type byte:

| Type | Data |
| --- | --- |
| 0 | Nothing |
| Position | 6 floats and an enabled flag |
| Velocity | 4 floats and two flags |
| Spring damper | 4 floats and a flag |

An unknown motor type is an error, because the rest of the block cannot be read.

The repeated constraint info inside `bhkMalleableConstraint` is skipped. The outer block
already names the two bodies, and a second copy that disagrees would give two answers.

A joint that fails to decode loses only that joint. The body and its other joints are
kept, because a ragdoll with one missing limb is better than none. A constraint class that
OpenSky does not read is counted as unsupported. `bhkBreakableConstraint` and
`bhkBallSocketConstraintChain` are not read. Neither appears in vanilla.

## Ragdolls

A Skyrim skeleton NIF has no ragdoll container. Each bone's body hangs on a
`bhkBlendCollisionObject`, and the bone is the name of the `NiNode` the object targets. In
vanilla, 1,193 of 1,196 skeleton bodies use `bhkBlendCollisionObject`, and all 1,136
skeleton joints name a bone at both ends.

Only two constraint classes hold the vanilla ragdolls: 624 `bhkRagdollConstraint` and 512
`bhkLimitedHingeConstraint`. The pairs make anatomical sense. `Bip01 L Calf -> Bip01 L
Thigh` and `Bip01 L Forearm -> Bip01 L UpperArm` are limited hinges. Shoulders and hips are
ragdoll cones. Clutter adds 141 limited hinges, 3 hinges, and 2 ragdolls on hanging props.
`bhkBallAndSocketConstraint`, `bhkStiffSpringConstraint`, `bhkPrismaticConstraint`, and
`bhkMalleableConstraint` do not appear in vanilla.

## Vanilla data

Six Tamriel cells around (6, -2), every mesh under `meshes\clutter\`, and every actor
skeleton:

| Group | Models | Bodies | Simulated | Joints |
| --- | --- | --- | --- | --- |
| Exterior cell models | 54 | 44 | 0 | 0 |
| Clutter meshes | 1746 | 1781 | 754 | 146 |
| Actor skeletons | 72 | 1196 | 1193 | 1136 |
