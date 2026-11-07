---
type: Engine
title: Water volumes, currents, and floating bodies
description: Where water is, how a river or waterfall current pushes actors and loose objects,
  how loose objects float, and what dangerous water does.
tags: [engine, physics, water]
---

# Water volumes, currents, and floating bodies

Water is a set of boxes. Each box has a surface height and a list of currents. Swimming, the
current push, and floating all read these boxes. Every rule on this page comes from a clean-room
read of `SkyrimSE.exe` on 2026-11-07, unless it says otherwise.

Units: a Havok unit (H) is 69.9912 game units. A current is stored in H per second.

## Where the boxes come from

| Source | Box | Surface | Currents |
| --- | --- | --- | --- |
| Cell water | One cell, 4096 by 4096 units, from the cell's lowest land up to the water height | `XCLW`, or the worldspace default | The `WATR` `NAM0` linear and `NAM1` angular velocity, in world axes |
| Placed water | The root collision shape of the model, such as the 1024-unit box of `Water\Water1024.nif`, placed at the reference | The reference's z | The reference's `XWCU` list |
| Current planes | The box of the model's root collision, placed at the reference | None: no swimming, no floating | One plane current per `CurrentPlane` shape, from `XCVL` and `XCVR` |

Placed water is an `ACTI` with a `WNAM` water type. Rivers use it: `Water1024RiverFlowNE` names
`RiverWaterFlowNE`. The engine ignores the phantom's own offset in the NIF and uses only its
shape, so the box is centred on the reference. Only the part under the reference's z holds
water.

A cell with no land to measure gets a box 4096 units deep
([unverified values](/engine/unverified-values.md)).

Where boxes overlap, the highest surface wins for swimming. A loose body takes the forces of one
box per frame.

## Current lists

`XWCU` is a list of 16-byte vectors, and `XWCN` is its count. Each current takes three or four
vectors. The third vector's last float holds the current's kind as a 32-bit integer.

| Kind | Vectors | Where it applies |
| --- | --- | --- |
| 0 | 3 | The whole box. The first vector is the linear velocity, the second the angular one. |
| 1 | 3 | A vertical cylinder: the third vector holds the centre x and y and the radius. |
| 3 | 4 | A half-space: the third vector holds a point, the fourth the plane normal and a radius. A point counts when it lies on the side away from the normal and within the radius horizontally. |

Every vanilla river reference has `XWCN` 3: one kind 0 current whose linear velocity is the
water type's `NAM0`, such as (2.54, 1.35, 0) for `RiverWaterFlowNE`. The editor copies it from the
`WATR`. It is in world axes, so the reference's rotation does not turn it.

Kind 1 and 3 currents fade from the centre: s = (radius − distance) / radius. The strength is
s × (1 − a) + a, where a is the second vector's last float. Kind 0 currents add up; a shaped
current blends over what came before it by its strength. Kind 2 is not read; no vanilla data uses
it, and its length is not known, so reading stops there.

[WARNING] The centre, point, and radius of kind 1 and 3 currents are read as Havok units, like the
velocities. No vanilla reference stores one, so this is not checked
([unverified values](/engine/unverified-values.md)).

A non-zero last float in the first vector turns x into a speed around the centre and y into a
speed away from it.

### Current planes

Waterfall and creek meshes such as `FXCreekFlatLarge.nif` hold shapes named `CurrentPlane`, or
nodes of that name whose first child is a shape. Each one becomes a kind 3 current:

- the point is the shape's world position, raised by 0.5 H (35 units);
- the normal is the shape's local +z in world axes;
- the radius is the shape's world bound radius;
- the linear velocity is the reference's `XCVL`, turned by the shape's world rotation. A missing
  or zero `XCVL` reads as (0, 6, 0). The angular velocity is `XCVR`, not turned.

The game hides every `CurrentPlane` shape. A reference whose model has no root collision gets no
current. Where a current plane's box overlaps water, its plane currents blend over that water's
own currents. The angular velocity is stored but moves nothing.

## Actors in a current

An actor is in water when the water surface is above the bottom of its capsule. A current then
pushes it when one of these holds:

- it swims;
- it falls faster than 700 units per second;
- the current is faster than `fWaterKnockdownVelocity` (5) times its race size factor:
  `fWaterKnockdownSizeSmall` (0.6), `...Normal` (0.75), `...Large` (1.25), or `...VeryLarge` (1.5).

A race that swims and neither walks nor flies is never pushed. The race flags are `Swims`
(0x40), `Flies` (0x80), and `Walks` (0x100) of `RACE` `DATA`.

The push adds the current, times 69.9912, to the actor's own movement for that step. Below the
threshold the push is limited: the actor's own horizontal speed plus the current may not pass its
maximum speed, so a swimmer cannot outrun its own stroke by riding a current. The vertical part is
not limited. The angular current does not turn actors.

[WARNING] The maximum speed is the actor's swim speed while it swims and its run speed otherwise.
The game's exact choice is not known ([unverified values](/engine/unverified-values.md)).

A current faster than the knockdown speed also knocks the actor down once as it enters
([impulses](/engine/impulses.md)).

Not done yet:

- An NPC is pushed only while it walks a path. A standing NPC has no mover to push.
- A mount in the air is not pushed, because nothing tracks a mount's fall.

## Floating bodies

Each frame a loose body inside a box, near enough to the player, floats:

1. Skip a body more than 3213 units from the player, or more than 48 units above the surface.
2. From the body's world box, h = top − bottom and the fill f = (surface − (bottom + 0.25h)) /
   (0.6h). A body with f ≤ 0 is not in water.
3. The buoyancy B is the body material's `MATT` `BNAM`. It ramps in with the fill: 0 up to
   f = 0.5, B × (f − 0.5) × 4 up to 0.75, and full B above.
4. Gravity is cancelled, and B × mass × gravity pushes up. A body with B = 0 hangs still, and
   one with B < 0 sinks.
5. Damping: the vertical speed × e^(−4dt), except for a floating body near the surface that
   barely moves; the horizontal speed × e^(−2dt) above 2 H/s; the spin × e^(−0.75dt).
6. A current pulls each non-zero axis of the velocity toward it: v moves by (current − v) × dt.

So a cup dropped in a river comes up, then drifts downstream at the river's speed.

Not done yet:

- The game raises the point where buoyancy acts on a long body, which tips it.
- The vertical damping skips a body that floats at the surface and barely moves. The limits of
  that case are not known, so every body is damped.
- A ragdoll's bones float with a share per body part. Ragdolls do not float yet.

## Dangerous water

A `WATR` with flag 0x1 is dangerous. `IsInDangerousWater` is true for an actor whose feet are
under its surface; only the player's is tracked. Nothing splashes in dangerous water.
Nothing in the vanilla data hurts: every `WATR` `DATA` damage value is 0, and no game code that
applies it was found. The two dangerous types are `DLC2ApocryphaWater` and
`DLC2ApocryphaWaterSmall`.

## The vampire lord's cape

The only cloth the game simulates is the vampire lord's cape. It pins the 12 highest vertices
and keeps every triangle edge at its first length with a Verlet solver, then pushes the cloth out
of the body and calf capsules. OpenSky does not simulate it yet, because how the result combines
with skinning is not known.

## Checking it in the game

`openskycli game state impulses` shows `playerWater`: the surface, the current, and the push
of the last step, and whether the water is dangerous.
