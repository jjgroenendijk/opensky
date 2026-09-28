---
type: Subsystem
title: Ragdoll joint solver
description: How a skeleton NIF becomes a ragdoll, what the Havok constraint angles are read
  as, why the joint solver uses sequential impulses, which bones collide with each other, and
  how a ragdoll comes to rest.
tags: [engine, physics, havok, ragdoll, nif]
---

# Ragdoll joint solver

This page covers the physics of a ragdoll. Death, the hand-off from animation, and saving are on
the [death and ragdoll](/engine/ragdoll.md) page. The joints run inside the same fixed step as
[dynamic rigid bodies](/engine/dynamic-bodies.md). A step that receives joints treats its bodies
as one ragdoll.

## Building a ragdoll

A skeleton NIF has no ragdoll container class. It has `bhkRigidBody` blocks, each under a
`bhkBlendCollisionObject` that targets a named `NiNode`, and constraint blocks that join pairs
of them ([NIF rigid bodies](/formats/nif-rigid-bodies.md)). The ragdoll is built from these:

- Each body that can be simulated becomes one dynamic body, matched to an animation bone by
  name. The `NiNode` name is spelled exactly like the `hkaSkeleton` bone, for example
  `NPC L Calf [LClf]`.
- Each constraint becomes one joint. Both pivots and axes move from the entity's own space,
  through the body's transform, into the body's center-of-mass frame. That is the frame every
  impulse is measured in.
- Each bone keeps its bind pose matrix: where the skeleton draws it with no animation. Then
  `animatedBoneMatrix * bindInverse` is the rigid move from the bind pose to the animated pose.
  The hand-off uses this product, and writing a bone back uses its inverse.

Nothing is dropped silently. A body whose target is not a bone, a body with no mass, a joint
whose end is not in the set, and a constraint class with no limit model are all listed as
skipped. The vanilla humanoid skips nothing: 18 bones and 17 joints.

## Reading the constraint angles

`bhkRagdollConstraint` stores five angles and `bhkLimitedHingeConstraint` two. Havok does not
publish what it does with them, so these readings are stated, not assumed:

| Field | Read as | Confidence |
| --- | --- | --- |
| `coneMaxAngle` | Largest angle between the two bodies' twist axes | Firm. That is what a cone limit means |
| `planeMinAngle`, `planeMaxAngle` | Signed limit on the twist axis leaving body A's plane | Could mean something else |
| `twistMinAngle`, `twistMaxAngle` | Limit on the roll around the shared twist axis | Firm |
| `minAngle`, `maxAngle` (hinge) | Limit on the hinge's rotation, measured like twist | Firm |
| `maxFriction` | A rate: the part of the joint's relative spin removed per second | A modelling choice |

Two readings were settled by measuring the vanilla humanoid at its bind pose.

The roll direction: the angle runs from body B's reference axis to body A's. In that direction,
all four hinge kinds in the skeleton sit inside their ranges: knee -0.054 in `[-1.920, 0]`,
ankle -0.498 in `[-0.596, 0.063]`, elbow +0.019 in `[0, 1.920]`, wrist -0.060 in
`[-0.087, 0.349]`. The other direction puts three of the four outside, the ankle by 0.44
radians. A standing skeleton would then fight its own ankle limit before anything moved. The
vanilla cones all have symmetric twist ranges, so they cannot tell the directions apart. They
follow the hinges.

The unit of `maxFriction`: the humanoid has only two values across 17 joints, 10.0 on every cone
and 0.01 on every hinge. That is too little to find a unit from. OpenSky reads it as a rate. This
is safe: friction only removes energy, so a wrong scale makes a corpse stiff or floppy, but never
unstable.

The bind pose is otherwise very nearly satisfied, which shows the frame mapping is right. Every
cone and plane angle is under 0.08 radians. The pivots match exactly on 14 of the 17 joints. The
other three have built-in slack, the same on left and right: knees 4.3 units, elbows 2.6, neck
1.4. That is in the data, not a decode error.

## The solver

The solver uses sequential impulses. Each substep visits each joint a fixed number of times. A
visit computes the joint's current error, solves for the impulse that removes the rate of that
error, and applies it to both bodies. Drift that is left over is then removed from the positions
and orientations, not from the velocities.

The rejected option was position-based dynamics (XPBD). It moves positions onto the constraints
directly and reads velocities back from the move. It handles stiff chains well with few
iterations, which is a real advantage for an 18-bone ragdoll. It lost on one point: the contact
solver already uses sequential impulses with position recovery for penetration. A ragdoll bone
touches the floor and is jointed to its neighbor in the same substep. Two solver families on one
body's velocities undo part of each other's work every iteration. Using the contact solver's
family makes the two passes work together, with one set of tuning constants.

Four rules keep it bounded. Each one came from a measurement:

- No restoring bias on a limit. A first version pushed the error's rate to a negative multiple of
  the error (the textbook Baumgarte term), so a violated limit recovered through velocity. The
  contact solver already refuses this for penetration. The velocity it writes is energy the joint
  invents: a vanilla humanoid sped up from 20 to 52 units a second over 30 seconds, and one ankle
  limit's error grew from 0.27 to 1.77 radians. Moving recovery into the position step fixed it.
- Position corrections add up, and are applied once. They take several passes over the joints,
  because a correction moves one link per pass and a humanoid is six links from pelvis to hand.
  With one pass the knees stayed seven units apart. But applying each pass separately spends the
  whole correction budget several times in one substep. That is a teleport, and a teleport does
  work against gravity. So: add up, clamp once, apply once.
- Contacts and joints are one velocity solve. Normal clutter still uses four contact iterations.
  A ragdoll uses sixteen combined iterations, and swaps whether contacts or joints go first each
  time. Their impulses are kept for the whole substep, so the floor and the chain converge
  together. Position recovery fixes joint drift first and floor penetration last, so it cannot
  cause the next substep's contact.
- Every impulse is checked to be finite, and every effective mass is checked for size before any
  division. A degenerate joint adds nothing instead of a NaN.

Joints are visited in list order, for a fixed number of iterations, with no early exit except on
the joint's own numbers. So two identical runs give bit-identical poses.

## Self-collision

A ragdoll's bones collide with each other only in the pairs the skeleton's own Havok biped
filter allows.

A vanilla humanoid is 18 capsules with radii up to 18 units, on bones about 20 units long. So
neighbors overlap heavily by design: at the joints, but also left thigh against right thigh at
the pelvis, and upper arm against spine at the shoulder. At the bind pose, 24 of the 153 pairs
already overlap, the deepest by 12 units. With every pair on, a corpse lying still carried 30 to
45 contacts and shook forever. With every pair off, a limb can pass through the torso.

### What the file says

nif.xml's `CollisionFilterFlags` is a bit field over the one flags byte of `HavokFilter`: bits 0
to 4 are a `BipedPart`, bit 5 is `MOPP Scaled`, bit 6 is `No Collision`, bit 7 is
`Linked Group`. The part number is meaningful "only if the Layer is 8 (or 32/33 for Skyrim and
later)": `SKYL_BIPED`, `SKYL_DEADBIP`, `SKYL_BIPED_NO_CC`
([nif.xml](https://github.com/niftools/nifxml/blob/develop/nif.xml)).

The vanilla humanoid confirms this. All 18 bodies are on layer 8, in group 0, with no
`No Collision` bit, and both copies of the filter agree. Every part number matches the right
`BipedPart` name:

| Bone | Part | Bone | Part |
| --- | --- | --- | --- |
| `NPC Neck` | 0 `P_OTHER` | `NPC L Thigh` | 8 `P_L_THIGH` |
| `NPC Head` | 1 `P_HEAD` | `NPC L Calf` | 9 `P_L_CALF` |
| `NPC COM` | 2 `P_BODY` | `NPC L Foot` | 10 `P_L_FOOT` |
| `NPC Spine` | 2 `P_BODY` | `NPC R UpperArm` | 11 `P_R_UPPER_ARM` |
| `NPC Spine1` | 3 `P_SPINE1` | `NPC R Forearm` | 12 `P_R_FOREARM` |
| `NPC Spine2` | 4 `P_SPINE2` | `NPC R Hand` | 13 `P_R_HAND` |
| `NPC L UpperArm` | 5 `P_L_UPPER_ARM` | `NPC R Thigh` | 14 `P_R_THIGH` |
| `NPC L Forearm` | 6 `P_L_FOREARM` | `NPC R Calf` | 15 `P_R_CALF` |
| `NPC L Hand` | 7 `P_L_HAND` | `NPC R Foot` | 16 `P_R_FOOT` |

A mask read at the wrong width or offset could not match the anatomy like this by chance.

### Which pairs collide

Havok does not publish its biped pair table, so this rule is OpenSky's. A pair collides when all
four hold:

1. Both bodies have a part number. A body on another layer says nothing about biped collision.
2. Neither has `No Collision`.
3. The part numbers differ. Two bodies with one part are the same body part modelled twice.
   Vanilla does this: `NPC COM` and `NPC Spine` are both `P_BODY`, and they are the second
   deepest overlap.
4. The bodies are more than two joints apart in the ragdoll's joint graph. One joint holds two
   capsules together at a pivot, so they overlap there. Two joints is a pair held by a shared
   parent: the two thighs at the pelvis, upper arm and spine at the shoulder.

Rule 4 uses graph distance, not an anatomy table. It comes from the same file as the bodies, so a
skeleton that is not a biped (a dragon, a spider, a mod creature) works without anyone writing
down its anatomy.

On the vanilla humanoid, 116 of 153 pairs collide, and none of the 24 that overlap at the bind
pose are among them. So the arms cannot pass through the torso, and the solver never sees the
standing contacts.

The limit: a pair collides as whole capsules. A limb can still pass through a bone two joints
away, which on a humanoid is a forearm through its own shoulder. Ragdolls also do not collide
with each other.

## Coming to rest

With contacts and joints in one solve, every bone reaches the normal per-body sleep limits.

A ragdoll also has its own rest test. It asks what a viewer asks: has the body stopped going
anywhere? It checks the root's movement, not the noisiest bone. When the root moves less than a
set distance over a set time, all bones sleep together. So one bone on an uneven floor cannot
delay the save after the corpse has stopped. It cannot fire during a fall, because gravity moves
a falling body hundreds of units in that time. It also waits until every pivot is within 2 units
and every angle limit within 0.06 radians, so it cannot freeze a pose that is not finished.

A self-collision contact during a fall can leave a joint open at the moment the last bone stops.
So on reaching rest by either route, the ragdoll runs a final position-only joint projection
until every joint is inside half the rest limits. No velocity comes from that move. On the
vanilla humanoid this closed a left elbow from three units and six degrees open to 0.14 units and
1.7 degrees.

A sleeping ragdoll is not solved at all. So a settled corpse costs nothing and keeps its pose. An
impulse wakes it like any other dynamic body.
