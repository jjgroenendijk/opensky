---
type: Subsystem
title: Dynamic rigid bodies
description: Fixed-step rigid-body simulation for movable clutter - which bodies simulate,
  the convex collider, the integrator and contact solver, shape sweeps, the player's shove,
  and the streaming and persistence lifecycle.
tags: [engine, world, physics, havok, collision, streaming]
timestamp: 2026-08-06T00:00:00Z
---

# Dynamic rigid bodies

Milestone 15 item 15.2 turns the Havok data item 15.1 decoded into motion. Movable clutter
in resident cells becomes simulated rigid bodies on the same 1/120 fixed step the player
capsule already runs on, collides against the immutable
[static collision world](/engine/collision-world.md) and against each other, is pushed by a
walking player, and persists where it comes to rest.

## Contents

* Which bodies simulate
* The collider
* Narrowphase
* Integration and contact solving
* Shape sweeps
* Player push and dropped items
* Streaming and persistence
* Panel seam
* Verification and budgets
* What is not done yet
* Current boundary

## Which bodies simulate

The [dynamics census](/formats/nif-collision.md) settled this on real data rather than on
what `nif.xml` allows. Vanilla exports most static geometry as `MO_SYS_BOX_STABILIZED` with
`MO_QUAL_INVALID` and zero mass, so the motion byte alone would make 1027 immovable bodies
dynamic. `NIFRigidBodyDynamics.isSimulated` is the discriminator: a *known* simulated motion
system **and** a positive finite mass. Four motion systems appear in the install at all —
box and sphere stabilized, box and sphere inertia — and an unknown byte degrades to static
rather than to nonsense.

**The split is off by default.** `CellSceneBuilder.simulatesDynamicBodies` gates it, and
production leaves it false — see [what is not done yet](#what-is-not-done-yet). With the flag
off the immutable collision set is exactly what it was before this item, so nothing about the
world a player walks through changed. The unit tests and the real-data probe turn it on.

`CellSceneBuilder.buildCollisionProducts` runs the split during the cell build. Each
player-solid `bhkRigidBody` goes to exactly one of two places:

| condition | destination |
| --- | --- |
| `isSimulated`, the reference has a `ReferenceKey`, no joint binds it, and a convex volume survives | `CellScene.dynamicBodies` |
| anything else | `StaticCollisionSet`, exactly as before |

Three rules keep that table from taking geometry away from the world:

* A body with no runtime key stays static rather than disappearing, which keeps the
  collision-only build path (`openskycli collision`, `buildStaticCollision`) reporting the
  same shapes it always did.
* Only the *simulated* bodies of a model leave the static set. A model routinely mixes the
  two — a shelf whose plank is fixed and whose contents are not — and routing the whole model
  because one body was movable takes the shelf away with it.
* A model whose bodies are bound by joints stays static wholesale. Nothing solves a
  constraint until item 15.6, and the probe showed the alternative: a hanging rack whose
  joint is ignored simply falls, and keeps falling out of the world.

A reference becomes **one** rigid body, not one per decoded `bhkRigidBody`. A reference has a
single `ReferenceKey`, a single drawn placement and a single `.transform` component to
persist into, so a model's simulated bodies are welded — masses add, the centre of mass is
their mass-weighted mean, every shape joins the collider. A body is never in both sets, so
nothing is collided twice.

Units convert once, at `DynamicBodyDefinition`. Lengths are Skyrim units, time is seconds,
mass is kilograms; gravity is `WalkController.gravity`. A metre-denominated Havok field
converts by `NIFCollisionModel.havokToEngineScale` and the inertia tensor, carrying length
squared, by its square. A tensor that will not invert cleanly falls back to a solid box with
the collider's own extents, because a bad tensor makes a body spin without bound.

## The collider

A simulated body is always convex, which is what lets contact generation stay closed-form.
`DynamicCollisionVolume` has two cases:

| case | covers |
| --- | --- |
| `radial(first, second, radius)` | `bhkSphereShape` (the segment is a point) and `bhkCapsuleShape` |
| `hull(points, planes)` | `bhkBoxShape` and `bhkConvexVerticesShape` |

A dynamic body whose shape is a triangle soup degrades to that soup's axis-aligned box.
That is the one lossy conversion in the layer: a concave collider has no meaning to this
solver, and a wrong-shaped body is better than an unsimulated one falling through a floor.

Hull planes come from the decoder's derived triangle connectivity, oriented outward against
the point cloud's own centroid because that connectivity does not promise a consistent
winding. Duplicate faces — a decoded hull repeats a face once per triangle sharing it — are
collapsed. Fewer than four distinct planes cannot bound a volume and produce no body.

Every volume is re-expressed against the body's centre of mass, which is the origin the
solver integrates about. `DynamicBody.originPosition` recovers the reference's own origin,
which is what a transform override records and what a draw call places the mesh by.

The body also keeps its shapes undigested (`DynamicBodyColliderShape`). Composed with the
body's current pose they are ordinary `StaticCollisionShape` values, so the player capsule,
the interaction ray, and a shape sweep all see moving clutter through the query they already
run — a dynamic body is not a second kind of thing to every consumer above this layer.

## Narrowphase

Every contact comes from one *sample point plus a skin radius* on one body, tested against
the other surface. A hull's samples are its vertices and a radial volume's are its two
segment ends; the question asked of the other surface is only ever "how deep is this sphere
inside you". `DynamicCollisionVolume.penetration` answers it for a convex volume — the least
separated face plane for a hull, the closest point on the segment for a radial one.

Against a triangle the answer has to be *signed*. An unsigned distance flips the push
direction the moment a corner passes through a floor, which sends the body further through
it. The sign comes from the triangle's own plane oriented toward the body's centre of mass as
it was *before* the substep moved it — the pre-substep centre is the point that had not
crossed the surface yet, and using the current one lets a body that has just dipped below a
floor orient that floor downward and be expelled through it.

Among the triangles of one shape the **nearest** surface wins, not the deepest. Ranking by
depth picks the far face of anything a sample is inside, which expels clutter authored just
inside a shelf top downward through the shelf.

The triangle work runs in the shape's own local space. A placed shape carries far more
vertices than a body carries samples, so pushing a handful of samples through one inverse
matrix beats pushing every triangle through the forward one; the placement is rigid times a
uniform scale, so lengths convert back exactly.

Two constants bound the result:

* `contactMargin` (1.5 units) is added to every sample's skin. A hull vertex has no skin of
  its own, so without a margin a resting box would only generate contacts while already
  interpenetrating, and would jitter between touching and free.
* `recoveryDepth` (48 units) is how far behind a surface a contact is still believed. Past
  it the sample belongs to different geometry, so a body standing above a floor in one room
  is not dragged by a triangle in the room below.

## Integration and contact solving

One `DynamicBodySolver.step` is one `WalkController.fixedTimeStep` tick, so the capsule and
the clutter around it advance on the same clock. Inside a step:

1. Gravity and damping go into the velocities, clamped to the body's own ceilings (or to
   `DynamicBodyDefinition.defaultMaximum*Speed` where the file's are absent or implausible).
2. The step splits into substeps small enough that no body moves further than
   `substepDistance(of:)` in one of them, capped at `maximumSubstepCount`. Motion past what
   those substeps cover is discarded. **That is the tunneling guard**: a body cannot cross a
   wall it never got a substep inside.
3. Each substep integrates the pose, gathers contacts, and resolves them with accumulated
   sequential impulses over `iterationCount` passes — normal impulse kept non-negative,
   friction clamped against whatever normal impulse has accumulated.
4. Leftover penetration is pushed out of the **positions**, not the velocities. The textbook
   Baumgarte velocity bias is what a first draft used, and it leaves a resting body with a
   standing upward velocity fighting gravity forever, so the body never falls under the
   sleep threshold. Moving the correction to position keeps the recovery and lets a settled
   body actually stop.
5. A body under both sleep thresholds for `sleepStepCount` consecutive steps stops being
   integrated. An impulse wakes it, and so does contact from a body that is still awake,
   which is what makes a shoved crate knock over the one beside it.

Determinism is a requirement rather than an accident. Bodies live in an array sorted by
`ReferenceKey` — not a dictionary, whose iteration order depends on hashing — contacts are
generated in body order, and the solver iterates them in list order for a fixed iteration
count. Identical inputs produce bit-identical trajectories, which the stress test asserts by
running the same scene twice and comparing poses exactly.

A pose that integrates to a non-finite value is reverted and the body's velocities are
zeroed, tallied in `DynamicStepStats.recoveredBodyCount`. That count is always zero on
well-formed input; a non-zero value is a bug, not a tolerance.

## Shape sweeps

`ShapeSweeper.firstHit` casts a sphere or a capsule along a straight path against placed
collision geometry — the query [hit volumes](/engine/collision-world.md) (15.4) and
projectiles (15.5) need, and the one the tunneling guard is checked against. It reuses the
narrowphase above rather than introducing a second one: an overlap test at sampled travel
distances, then a bisection onto the first touching distance. The growth that turns a swept
sphere into a static query is exact for spheres and capsules and conservative for triangles
and hulls, so a sweep may report a hit marginally early and never late — the safe direction
for both consumers. Ties break exactly as `InteractionRaycaster` breaks them: nearest first,
then the lower reference FormID.

## Player push and dropped items

The player capsule is a character controller with no mass, so the shove is modelled rather
than solved. `DynamicBodyWorld.push` gives a body whose collider overlaps the capsule an
impulse along the horizontal direction from the capsule axis to the body, sized by the
player's own horizontal speed, the body's mass, and `pushEfficiency` (0.35 — a walking actor
braces rather than transferring its whole stride, and a value of one makes light clutter
fly). Only the component of the walk that is *into* the body counts, so walking away from a
crate does not drag it.

The velocity is derived in `CellStreamerPhysics` from how far the capsule moved since the
last frame, so no signature downstream had to grow one. A frame that moved faster than
`maximumPushSpeed` was a teleport — a door transition or a camera reseed — and contributes
no shove.

A dropped inventory item needs no special path. `WorldItemRuntime.drop` writes a
`ReferenceSpawnState`, the next build of that cell places it like any other reference, and
if its model carries a simulated body it joins the dynamic world and settles.
`WorldItemRuntime.dropHeight` is therefore now the *release* pose rather than the resting
one; it remains the resting pose for an item whose mesh carries no dynamic body, which is
why it was not removed.

## Streaming and persistence

`CellStreamer` reconciles rather than being pushed at. Once per frame the resident cells are
compared against what `DynamicBodyWorld` already holds: a cell whose scene is new or has
been rebuilt hands over its placements, and a cell that is gone has its bodies dropped. A
coverage transition, a door transition, and a world-state rebuild therefore all get the
right answer without any of them knowing physics exists. Cells are visited in a stable
order, so two runs of a session install bodies identically.

A body already registered under the same key keeps its live pose and velocity through a
rebuild: a runtime-state write unrelated to physics must not teleport a crate back to where
the plugin put it.

Persistence is the existing `.transform` component and nothing new. The step a body falls
asleep, its resting pose is recorded; `drainSettledTransforms` hands those to the streamer's
`onBodySettled`, which the app wires to `WorldStateStore.set`. A save records it, and the
next build of that cell places the object there. A body still moving when its cell unloads
keeps its last written resting pose rather than its mid-flight one, because a crate should
not be found in mid-air after a reload.

## Panel seam

`PhysicsControlProviding` is the bridge for `World > Combat & Physics`: one `Equatable`
`DynamicBodyStatsSnapshot` out — body, active, sleeping, contact and substep counts —
plus `setPhysicsFrozen(_:)` and `resetDynamicBodies()`. `GameViewController` conforms it.
The panel itself ships with the milestone gate, item 15.9; the seam is specified and
conformed here so the simulation is inspectable the moment the panel exists.

## Verification and budgets

Synthetic suites, no game asset:

* `DynamicBodySolverTests` — a dropped box settles on a floor and sleeps; an impulse wakes
  it; a sleeping body's pose does not move at all afterwards; a body launched at 6000
  units/s is stopped by a wall instead of tunneling; a 36-body scene dropped from staggered
  heights runs 5 seconds of world time, stays finite, keeps every body above the floor, and
  produces bit-identical poses across two runs; a shoved body pushes its neighbour.
* `DynamicCollisionVolumeTests` — what each decoded geometry becomes, outward-facing hull
  planes, the least-separated-face answer, the triangle-soup box degradation, degenerate
  shapes producing no volume, and translation and rotation keeping the planes with the
  points.
* `ShapeSweepTests` — a clear sweep, a sphere cast stopping short of a wall by its radius, a
  capsule blocked by geometry only its far end reaches, an already-overlapping start, the
  lower-FormID tie-break, and rejected implausible queries.
* `DynamicBodyWorldTests` — key ordering, cell lifecycle, a rebuild keeping a live pose, the
  once-only settled-transform drain, freeze, reset, the shove and its direction test, and a
  body presenting its shapes to the ordinary collision query.
* `CellStreamerPhysicsTests` — bodies following residency, a rebuild not resetting a fallen
  body, and the collision query unioning static shapes with moving bodies while the solver
  is handed only the static half.
* `CellSceneBuilderDynamicBodyTests` — a movable body leaving the static set, a massless one
  staying in it whatever its motion system says, and a keyless reference keeping its static
  shapes.
* `MatrixMathTests` — `MatrixMath.eulerAngles(of:)` round-trips through the placement
  rotation, including the straight-up degeneracy, because a body integrates a quaternion and
  persists a Bethesda euler triple.

`DynamicBodyRealDataTests` is the env-gated probe (`make realtest
T='DynamicBodyRealDataTests/settlesAndPushesVanillaClutter()'`). It builds a vanilla
clutter-heavy interior with the routing flag on, simulates five seconds of world time, shoves
the result with a player capsule, and writes counts, per-body drops and timings to gitignored
`logs/dynamic-body-probe.log`.

It asserts what holds: no non-finite pose, no body needing a mid-step reset, bodies do come to
rest, and the shove moves things. The eventual perf budget — **average physics step <= 2.0 ms**
against the 8.33 ms a 1/120 step has — and the settle rate are *reported* rather than
asserted, because the measured values are far outside them and gating on a budget the code
cannot meet would turn the pre-push gate red rather than informative. That is the perf-gate
rule in [testing](/testing.md) applied honestly; the shortfall is under
[what is not done yet](#what-is-not-done-yet).

## What is not done yet

Two of item 15.2's acceptance criteria are **not met**, which is why
`CellSceneBuilder.simulatesDynamicBodies` defaults to false. Both were found by the real-data
probe and neither is visible from the synthetic suites, which all pass.

* **Clutter that does not settle.** In Chillfurrow Farm, 51 references simulate and roughly
  half never come to rest: they leave the geometry they were authored inside and fall out of
  the world. Vanilla authors clutter *intersecting* the shelf it stands on — the probe's
  downward sweep reports `overlapping` for nearly every body — and the expulsion of a deeply
  embedded sample out of a partitioned triangle soup is not yet reliable. Three narrowphase
  rules were corrected while chasing it (the pre-substep orientation reference, nearest-face
  ranking, and keeping a model's non-simulated bodies static); none of them closed it.
* **Step cost.** The same cell measures roughly 230 ms per fixed step against the 2 ms budget
  the frame can afford — two orders of magnitude out. Two structural wins are already in
  (samples taken once per substep, triangle work in shape-local space) and were not enough.
  The remaining cost is the sample-versus-triangle product itself, which needs a real
  broadphase per body rather than a per-cell BVH query plus a linear scan.

Routing by default would trade a world where a barrel is reliably solid for one where it
sometimes sinks through a shelf, so the flag stays off until both are fixed. Both are tracked
as issue #392, which carries the measurements and the next step for each. Everything else
in this page — the solver, the colliders, the sweeps, the registry, the streaming and
persistence lifecycle, the panel seam — is complete and covered by the synthetic suites.

## Current boundary

Constraints are decoded but not solved, so nothing here articulates: ragdolls and joints are
item 15.6. Projectiles are 15.5 and actor-vs-actor collision beyond the existing player
capsule path is out of scope. Body-vs-body contact is vertex-against-convex in both
directions, which is enough for clutter piles and is not a full face-clipping manifold;
a tall stack settles rather than resting perfectly. The player capsule collides with moving
bodies through the shared collision query but is not itself part of the solve.
