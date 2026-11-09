---
type: Subsystem
title: Dynamic rigid bodies
description: Which Havok bodies simulate, the convex collider, the fixed-step integrator and
  contact solver, sleep, the player's shove, and how bodies stream and persist.
tags: [engine, world, physics, havok, collision, streaming]
---

# Dynamic rigid bodies

Movable clutter in loaded cells becomes simulated rigid bodies. They run on the player's 1/120 s
step, collide with the [static collision world](/engine/collision-world.md) and with each other,
are pushed by the player, and are saved where they come to rest.

Contacts, between two bodies as well, and shape sweeps are on the
[dynamic body contacts](/engine/dynamic-narrowphase.md) page, and drawing on the
[drawing moving bodies](/engine/dynamic-body-drawing.md) page. The same step also solves a
ragdoll's joints ([ragdoll joint solver](/engine/ragdoll-solver.md)).

## Which bodies simulate

The [rigid body census](/formats/nif-rigid-body.md) decided this from real data, not from what
`nif.xml` allows. Vanilla exports most static geometry as `MO_SYS_BOX_STABILIZED` with
`MO_QUAL_INVALID` and zero mass. So the motion byte alone would make 1027 fixed bodies move. A body
simulates only with a known simulated motion system and a positive, finite mass. Four motion systems
appear in the install: box and sphere stabilized, and box and sphere inertia. An unknown byte
becomes static.

The cell build sends each player-solid `bhkRigidBody` to one of two places:

| Condition | Goes to |
| --- | --- |
| Simulated, the reference has a `ReferenceKey`, no joint binds it, and a convex volume survives | The cell's dynamic bodies |
| Anything else | The static collision set |

Four rules keep this from taking geometry out of the world:

- A body with no runtime key stays static. So the collision-only build (`openskycli collision`)
  reports the same shapes it always did. A build flag can also turn the split off for such tools.
- Only the simulated bodies of a model leave the static set. A model often mixes the two: a shelf
  whose board is fixed and whose contents are not. Moving the whole model would take the shelf.
- A model whose bodies are bound by joints stays static. A hanging rack with its joint ignored
  would fall out of the world.
- A static (`STAT`) base never simulates, even where its mesh has a simulated body, such as
  wall-mounted antlers. The Creation Kit's clutter tutorial says statics "cannot be moved,
  interacted with, or otherwise influenced by the player"
  ([source](https://ck.uesp.net/wiki/Bethesda_Tutorial_Clutter)). A script's `SetMotionType`
  still wins.

A reference becomes one rigid body, because it has one key, one placement, and one transform to
save. Its simulated bodies are welded: masses add, the center of mass is their mass-weighted mean,
and every shape joins the collider.

Units convert once, when the body is defined. Lengths are Skyrim units, time is seconds, mass is
kilograms, and gravity is the walk controller's. A Havok field in meters converts by the Havok
scale factor, and the inertia tensor, which carries length squared, by its square. A tensor that
does not invert cleanly is replaced by a solid box with the collider's size, because a bad tensor
makes a body spin without limit.

## The collider

A simulated body is always convex, so contacts can use closed-form math. There are two kinds:

| Kind | Covers |
| --- | --- |
| Radial: a segment and a radius | `bhkSphereShape` (the segment is a point) and `bhkCapsuleShape` |
| Hull: points and planes | `bhkBoxShape` and `bhkConvexVerticesShape` |

A dynamic body whose shape is a triangle mesh becomes that mesh's axis-aligned box. This is the one
lossy step. A concave collider means nothing to this solver, and a wrongly shaped body is better
than one that falls through a floor.

Hull planes come from the decoder's triangle connections. They are turned to face away from the
point cloud's center, because those connections do not promise a consistent winding. Repeated
faces (a hull repeats a face once per triangle on it) are merged. Fewer than four distinct planes
cannot enclose a volume, and give no body.

Every volume is expressed relative to the body's center of mass, which the solver integrates
around. The reference's own origin is recovered from it for saving and drawing.

The body also keeps its original shapes. Placed at the body's current pose, they are normal static
collision shapes. So the player capsule, the use-key ray, and shape sweeps see moving clutter with
the queries they already run.

## One step

One solver step is one fixed step of the walk controller, so the capsule and the clutter share a
clock. Inside a step:

1. Gravity and damping change the velocities, capped at the body's own limits, or at defaults when
   the file's are missing or unreasonable.
2. The step splits into substeps small enough that no body moves too far in one, up to a maximum
   count. Motion past what those substeps cover is thrown away. That is the guard against
   tunneling: a body cannot cross a wall it never had a substep inside.
3. Each substep moves the poses, finds contacts, and solves them with accumulated sequential
   impulses over a fixed number of passes. The normal impulse never goes negative. Friction is
   limited by the normal impulse so far. The static shapes near a body are looked up once per
   step, in a box widened by the step's travel. Each substep keeps the shapes its bounds overlap,
   and looks up again only when the body has left that box, so the contacts do not change.
4. Penetration that is left is pushed out of the positions, not the velocities. A first version
   used the textbook Baumgarte velocity bias. That leaves a resting body with an upward velocity
   fighting gravity forever, so it never falls below the sleep limit.
5. A body below both sleep limits for enough steps stops being integrated. An impulse wakes it, and
   so does contact from a body that is still moving. That is how a pushed crate knocks over the
   one beside it.

### One penetration is corrected once

Corrections are added up per body. Each contact is measured against how far its body has already
moved. A sample makes one contact per nearby placed shape, so a hull corner in a shelf often makes
a dozen contacts with the same normal and depth. Applying each in turn moved the body a dozen
times its real penetration: a crate left a shelf at six units per substep, and another was shot
118 units through a floor in one step. A limit of 1.5 units per substep also applies, so clutter
placed deep inside a shelf climbs out over several steps instead of being launched.

### Sleep

Three rules, each fixed a body that never slept:

- The angular limit is per body: the spin at which the collider's outer point moves at the linear
  sleep speed. One angular speed does not mean the same motion for a bowl and a table.
- A step under the limits counts toward sleep, and a step over them counts back down. It does not
  start over. A body resting on triangle meshes twitches, because its samples cross triangle edges.
  Starting over on each twitch means a body at rest 59 steps out of 60 never sleeps.
- Waking a neighbor tests the toucher's resting count, not its velocity. Each step adds gravity to
  every awake body first, so during contact solving every awake body seems to move. Testing
  velocity there made a settled pair take turns sleeping and waking forever. Nothing in that pair
  could be saved, because a resting pose is recorded only in the step a body falls asleep.

The impulse and position steps skip sleeping bodies. Velocity written into a body that is not
integrated would wait and fire when something wakes it.

### Determinism

Bodies live in an array sorted by `ReferenceKey`, not in a dictionary, whose order depends on
hashing. Contacts are made in body order and solved in list order for a fixed number of passes. So
the same inputs give bit-identical results.

A pose that becomes non-finite is reverted, its velocities are zeroed, and it is counted. A
non-zero count is a bug.

## The player's shove

The player capsule is a character controller with no mass, so the shove is modelled, not solved. A
body whose collider overlaps the capsule gets an impulse along the flat direction from the capsule
to the body. Its size comes from the player's horizontal speed, the body's mass, and an efficiency
of 0.175. A walking person braces, and does not pass on the whole stride. Only the part of the walk
that goes into the body counts, so walking away from a crate does not drag it.

The game then scales the push by the body's mass and collision layer (clean-room read of
`SkyrimSE.exe`, 2026-11-07). Masses are in kilograms, which Havok uses too:

| Body | Factor |
| --- | --- |
| Mass 0 or below, or 95 or more | 0, no push |
| Layer 6, projectile | 0 |
| Layer 10, props | 0.1 above 47.5 kg, else 3 |
| Layer 14, trap | 0.1 |
| Any other layer, such as clutter and weapons | 2 |

When the push before the factor would move the body faster than 1,000 Havok units per second, the
factor shrinks by the same ratio. The 0.175 is OpenSky's: with the clutter factor of 2 a body takes
0.35 of the player's momentum. The game's own contact impulse is not known.

The speed comes from how far the capsule moved since the last frame. A frame faster than a set
limit was a teleport, such as a door or a camera reset, and gives no shove.

## A body against a character

A body touching a character's capsule is handled by its layer and mass, as the game's character
controller does (clean-room read of `SkyrimSE.exe`, 2026-11-07):

| Body | Blocks the character | Moves the character |
| --- | --- | --- |
| Layer 4, 5, or 6 (clutter, weapon, projectile) under 95 kg | No | No |
| The same layers at 95 kg or more | Yes | Yes, by its velocity |
| Layer 10, props | Yes | No |
| Any other layer | Yes | Yes, by its velocity |

So the player walks through a bucket or a plate, and the shove above is the only thing that moves
it. A heavy crate stops the player. When it moves, the player standing on it rides along, and one
moving into the player pushes them. The carry is the whole velocity of a body under the feet, and
the part of another body's velocity that points at the capsule. NPCs walk with the same rule, and
the third-person camera uses it too. The use-key ray still sees every body.

A dropped item needs no special path. The next build places the spawned reference like any other,
and if its model has a simulated body, it falls and settles. A model without collision stays where
it was placed. The game does the same: it makes no default body for such a model (clean-room read
of `SkyrimSE.exe`, 2026-11-07; players also report it).

## Streaming

The streamer compares the loaded cells with the bodies once per frame. A new or rebuilt cell hands
over its placements. A cell that is gone has its bodies removed. So coverage changes, doors, and
world state rebuilds all work without knowing about physics. Cells are visited in a fixed order.

A body has two cell identities:

- The placing cell never changes. It is the scene and world state bucket that wrote the `REFR`.
- The occupied cell is the exterior cell holding the live reference origin. It is recomputed after
  each step with the grid's floor rule. Interiors keep one identity.

Removing a cell retires the bodies that occupy it. So a barrel that rolled into a loaded neighbor
keeps moving after its placing cell unloads, and disappears when the neighbor unloads. A body that
is already known keeps its live pose and velocity through a rebuild, so a world state change
unrelated to physics cannot teleport it.

## Saving

Saving uses the existing transform component. In the step a body falls asleep, its resting pose is
recorded and written to the world state, under the placing cell, even if that cell is no longer
loaded. The transform is in world space, so the next build of the placing cell draws the reference
at its resting pose without changing its plugin cell. A body still moving when its cell unloads
keeps its last resting pose, not a pose in the air. A crate should not be found in mid-air after a
reload.

This write rebuilds no cell. The body already draws at its resting pose through its
[draw delta](/engine/dynamic-body-drawing.md), so a rebuild would draw the same frame. A body that
falls asleep exactly where its build placed it writes nothing, because there is nothing to save. A
loaded room full of clutter at rest therefore causes no rebuild at all.

## Performance

A step is a few hundred microseconds of tight `simd` math, which is exactly what Swift's `-Onone`
handles worst: it runs about 24 times slower unoptimized. So the 2 ms step budget is checked by
`make test PLAN=Perf`, which builds with optimization. It keeps the Debug configuration, because
`@testable import` needs `ENABLE_TESTABILITY`, and uses its own derived data folder. A normal
`make test PLAN=RealData` checks the step against a loose limit, to catch a large regression
([testing](/testing.md)).
