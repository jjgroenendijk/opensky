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
* Drawing a moving body
* Player push and dropped items
* Streaming and persistence
* Panel seam
* Verification and budgets
* Current boundary

## Which bodies simulate

The [dynamics census](/formats/nif-collision.md) settled this on real data rather than on
what `nif.xml` allows. Vanilla exports most static geometry as `MO_SYS_BOX_STABILIZED` with
`MO_QUAL_INVALID` and zero mass, so the motion byte alone would make 1027 immovable bodies
dynamic. `NIFRigidBodyDynamics.isSimulated` is the discriminator: a *known* simulated motion
system **and** a positive finite mass. Four motion systems appear in the install at all —
box and sphere stabilized, box and sphere inertia — and an unknown byte degrades to static
rather than to nonsense.

**The split is on by default** since issue #392. `CellSceneBuilder.simulatesDynamicBodies`
still gates it, because a build that only wants the immutable set — `openskycli collision`,
`buildStaticCollision` — needs to be able to say so, and because a reference with no runtime
key contributes static shapes whatever the flag says. It shipped false through item 15.2:
the real-data probe had roughly half a farmhouse's clutter leaving the geometry it was
authored in and falling out of the world, and a barrel that sometimes sinks through a shelf
is a worse world than one where nothing moves. Both faults are fixed and measured; the
[verification section](#verification-and-budgets) has the numbers.

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
it. Three rules make that sign trustworthy, and each of them replaced one that real data
disproved (issue #392).

**A surface faces the way it is wound, not the way the body lies.** `DynamicSurfaceOrientation`
takes a decoded triangle soup's normal straight from its winding, which vanilla authors front
face outward — confirmed over a whole interior's architecture and furniture. The rule this
replaced oriented the normal toward the body's centre of mass, on the premise that a convex
body resting on a surface has its centre on the outside of it. Real clutter does not honour
that premise: the probe found a vanilla model whose decoded centre of mass sits *below every
vertex of its own collider*, so it read the shelf it stood on as facing down, was driven
through the shelf, and accelerated out of the world. Any body thin enough to sink past its own
half-thickness flips the same way. A `bhkBoxShape` and a `bhkConvexVerticesShape` are the
exception: their triangle connectivity is derived by this engine rather than authored, so they
carry no winding worth trusting and are oriented away from an interior point instead — the
box's own origin, and the hull's point-cloud centroid, both of which are exact for a convex
shape.

**The nearest surface of a shape decides, in both directions.** Ranking by depth picks the far
face of anything a sample is inside, which expels clutter authored just inside a shelf top
downward through the shelf. Ranking by distance is only half of it: a near face that reports
"outside" has to *veto* a far one that reports "deep inside", or a shape answers as a set of
loose faces rather than as a solid. Without the veto a body hovering three units over a shelf
board found the board's underside twenty units away, was told it was twenty units inside the
board, and was pushed down through it. `DynamicSurfaceTriangle.surface` therefore returns the
distance whether or not there is a penetration, and the caller keeps the nearest answer of
either kind.

**A triangle is prepared once, not once per sample.** `DynamicSurfaceTriangle` holds the cross
product, the normalisation, the facing decision and the bounds, because a step asks the same
triangle about every sample of every nearby body. Its per-sample query then dismisses a
triangle on a dot product — the distance to the triangle's *plane* is a lower bound on the
distance to the triangle, so one that cannot beat the incumbent never reaches the
closest-point query. The pruning is exact.

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
  is not dragged by a triangle in the room below. It is capped per body at that body's own
  reach (`recoveryDepth(of:)`): a sample cannot be meaningfully further inside a surface than
  the body it belongs to is big, and the bound inflates the box every candidate triangle is
  tested against, so a flat 48 units around a tankard let nearly half a room's triangles
  through to the exact query. Scaling it to the body halved the step.

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
5. A body under both sleep thresholds for `sleepStepCount` steps stops being integrated. An
   impulse wakes it, and so does contact from a body that is still *moving*, which is what
   makes a shoved crate knock over the one beside it.

Points 4 and 5 each carry a rule that real data forced (issue #392).

**One penetration is corrected once.** The corrections are accumulated per body and each
contact is measured against what its body has already been moved. A sample generates a
contact per placed shape it is near, so a hull corner resting in a shelf routinely produces a
dozen contacts carrying the same normal and the same depth; applying each in turn moved the
body a dozen times the penetration it actually had. The probe caught a crate leaving a shelf
at six units a substep and a second shot 118 units through the farmhouse floor in a single
step, after which both fell out of the world. `maximumCorrectionDistance` (1.5 units) then
bounds what one substep may recover, so clutter vanilla authored deep inside its shelf climbs
out over several steps rather than being launched. Recovery is paced, not lost.

**Sleep is measured with hysteresis, at the body's own scale, and disturbed only by motion.**
Three separate things, all of which the probe measured stuck:

* The angular threshold is derived per body rather than being a constant: it is the spin at
  which the outermost point of the collider travels at `sleepLinearSpeed`, because one
  angular speed does not mean the same motion on a bowl and on a dining table.
* A step under the thresholds counts toward sleep and a step over them counts back *down*
  rather than starting the tally over. A body at rest on real triangle-soup geometry
  twitches — its samples cross triangle edges, so the contact set is not identical from one
  substep to the next — and zeroing the tally on any twitch means a body at rest fifty-nine
  steps out of sixty never sleeps.
* Waking a neighbour tests the toucher's resting tally, not its velocity. A step begins by
  adding gravity to every awake body, so at the moment contacts resolve *every* awake body is
  moving at a twelfth of gravity whatever it is really doing; the tally is the same
  measurement taken at the end of the previous step, after contacts had cancelled that
  gravity. Testing velocity there made a settled pair alternate forever, one sleeping on step
  61 and woken on step 62, over and over. Nothing in that pair could ever be persisted,
  because a resting pose is only recorded the step a body falls asleep.

A sleeping body is also skipped by the impulse and the position correction. Velocity written
into a body that is not integrated is never spent; it sits there and fires the moment
something wakes the body for an unrelated reason.

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

## Drawing a moving body

A cell build bakes one world matrix per draw instance and a cell is rebuilt only when its
runtime state changes, which is the right answer for a world whose geometry is authored in
place and the reason `CellStreamerRuntimeState` says whole-cell rebuilds are the intended
v1. A simulated body breaks that assumption once per frame. Left alone, the simulation is
invisible: a shoved barrel collides, rolls and settles while its mesh stands where the
plugin put it, then jumps to the resting pose when the settle triggers a rebuild.

So the baked matrix stays and the *difference* is applied where instance transforms are
uploaded. `DynamicBody.instanceDelta(fromPlacedPosition:orientation:)` is the rigid
transform carrying the pose the build drew the reference at onto the pose the solver has it
at, and `delta * baked` is the live matrix for every mesh of that reference. Because the
delta is applied on the left of a matrix that already contains the reference's XSCL scale
and the mesh's own local transform, neither has to be recovered or even known.

`DynamicBodyWorld.instanceDeltas` collects them per frame, keyed by REFR FormID, and
`CellStreamer.advancePhysics` publishes the map through `onDynamicPosesChanged` to
`Renderer.dynamicInstanceDeltas`. `Renderer.drawn(_:)` performs the substitution in the two
places instance transforms reach the GPU — the scene pass and the shadow pass — so a moving
body's shadow travels with it. The culling AABB is carried through the same delta, so a body
that has left the bounds its build baked is still drawn.

Three properties keep the cost where it belongs:

* A `DrawInstance` carries `referenceFormID` only when a body owns it, and zero otherwise,
  which is every placement the world has ever had. An untagged instance costs one integer
  comparison and never touches the dictionary.
* A body resting exactly where it was placed is *absent* from the map rather than present
  with an identity, so settled clutter costs what static clutter costs and a world standing
  still publishes nothing.
* The draw group an instance belongs to is keyed by mesh and material, neither of which a
  move changes, so nothing regroups and no buffer is reallocated.

The player body took the other road — it rebuilds its draw groups whenever it moves
(`RendererPlayerBody`) — because skinned geometry is placed by its bone palette as well as
by its model matrix, and the palette is in rig space. Rigid clutter carries no such
constraint.

The placed pose the delta is measured against is refreshed on every `setCell`, not only when
a body is new. A rebuild that bakes a settled pose into the scene has to move the reference
point with it, or the object would be drawn displaced twice over; the same refresh is what
makes the panel's reset return a body to the pose the current build drew rather than to the
one the plugin authored.

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
  staying in it whatever its motion system says, a keyless reference keeping its static
  shapes, and a simulated reference tagging the draw instances it places while an
  unsimulated build of the same cell leaves them at zero.
* `DynamicNarrowphaseTests` — the rules issue #392 turned over, each pinned by the case that
  broke before it: a surface facing the way it is wound rather than the way the body lies, a
  box facing away from its own centre, a sample clear of a slab getting no contact from the
  slab's far face, redundant contacts correcting once rather than once per contact, the
  angular sleep threshold following the collider size, and a settled pair both sleeping.
* `DynamicBodyRenderPoseTests` — the delta carrying a scaled placement matrix onto the live
  pose, an unmoved body publishing nothing, the map keyed by REFR FormID, a rebuild that
  bakes the resting pose collapsing the delta and moving the reset target with it, and a
  draw instance carrying both its matrices and its culling bounds through a move.
* `RendererDynamicPoseTests` — pixel evidence through the real render loop: a tagged crate
  leaves the pixels its cell build baked and appears where the published delta puts it, in
  one instanced draw call, and its culling bounds travel with it.
* `MatrixMathTests` — `MatrixMath.eulerAngles(of:)` round-trips through the placement
  rotation, including the straight-up degeneracy, because a body integrates a quaternion and
  persists a Bethesda euler triple.

`DynamicBodyRealDataTests` is the env-gated probe (`make realtest
T='DynamicBodyRealDataTests/settlesAndPushesVanillaClutter()'`). It builds a vanilla
clutter-heavy interior with the routing flag on, simulates five seconds of world time, walks a
capsule into the settled result, and writes counts, per-body drops and timings to gitignored
`logs/dynamic-body-probe.log`.

It asserts item 15.2's acceptance rather than reporting it (issue #392):

| claim | measured against Chillfurrow Farm |
| --- | --- |
| every simulated reference comes to rest | 51 of 51 asleep inside five seconds |
| each comes to rest where it was authored | largest drop 137 units, gate at 512 |
| no non-finite pose, no mid-step reset | zero of each |
| a walked capsule shoves clutter | 8 of the 8 bodies walked into moved |
| average step within budget | 0.3-0.7 ms against 2.00 ms |

Before this the same cell had roughly half its references leaving the geometry they were
authored in and falling more than twenty thousand units, the rest sitting still without ever
sleeping, and a step costing 247 ms.

The capsule is walked into each of the first few bodies in key order rather than parked at the
average body position. The average is where the probe used to stand, and it only ever worked
because half the clutter was falling through the world: now that every reference settles where
it was authored, the centroid of a farmhouse's clutter is a point in mid-air and a capsule
there touches nothing.

**The perf gate needs an optimized build, which `make realtest-perf` builds.** A step is a few
hundred microseconds of tight `simd` arithmetic, and that is exactly the code Swift's `-Onone`
treats worst: the same run measures around twenty-four times slower unoptimized, so holding a
plain `make realtest` to 2 ms would be measuring the compiler rather than the engine. The
optimized run keeps the Debug *configuration*, because `@testable import` needs
`ENABLE_TESTABILITY` and Release turns it off; it overrides the optimization level, announces
itself to the test through the `OPENSKY_OPTIMIZED` compilation condition, and builds into its
own derived-data tree so it does not evict the ordinary Debug cache. A default `make realtest`
still gates the step, at the unoptimized ceiling — loose on purpose, because it exists to
catch a regression of this kind rather than to certify performance. That is the perf-gate rule
in [testing](/testing.md) applied to a budget the code now meets.

## Current boundary

Constraints are decoded but not solved, so nothing here articulates: ragdolls and joints are
item 15.6. Projectiles are 15.5 and actor-vs-actor collision beyond the existing player
capsule path is out of scope. Body-vs-body contact is vertex-against-convex in both
directions, which is enough for clutter piles and is not a full face-clipping manifold;
a tall stack settles rather than resting perfectly. The player capsule collides with moving
bodies through the shared collision query but is not itself part of the solve.
