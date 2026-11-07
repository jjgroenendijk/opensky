---
type: Subsystem
title: The game's cart tow rig
description: How the game joins a towed cart to its horse with physics bodies and constraints, and
  which parts OpenSky follows.
tags: [engine, physics, actors]
---

# The game's cart tow rig

In the game, `TetherToHorse` turns a cart into a set of physics bodies that the horse pulls. This
page records how, so the [vehicles](/engine/vehicles.md) page can say where OpenSky differs.

Source: a clean-room read of `SkyrimSE.exe` and of
`meshes\furniture\prisonercarriage\prisonercarriage01.nif` on the install, 2026-11-07. One Havok
unit is about 70 game units. Masses are in Havok kilograms.

## When the tether starts

`TetherToHorse(horse)` on the cart queues a task. The task does three things, in this order:

1. It moves the horse. The horse takes the cart's heading. It stands 200 units ahead of the cart's
   origin, on the cart's +Y axis, at its own height.
2. It sets the mass of every rigid body in the cart's model to 130.
3. It builds the hitch, described below.

## The cart's bodies

The model holds six bodies. All are dynamic, on the props layer.

| Body | Shape | Mass in the file |
| --- | --- | --- |
| Carriage, on the root node | 8 convex hulls | 12,000 |
| `FrontBar`, a beam across the front | 1 convex hull | 100 |
| Each of the 4 wheels | 1 convex hull of 72 points | 150 |

The back wheels have a radius of about 52 units, the front ones about 43.5.

Five constraints from the file join them:

- Each back wheel turns on a free hinge about the cart's X axis, on the carriage body.
- Each front wheel turns on a free hinge about X, on `FrontBar`.
- `FrontBar` turns on a hinge about the vertical axis, on the carriage body, 52.7 units up. The
  hinge stops at 40 degrees each way and has a very small friction. So `FrontBar` is a turntable
  that steers the front axle.

Nothing drives the wheels. They roll only because the ground holds them by friction.

## What the code adds

- An anti-tip push. When the carriage rolls more than about 45 degrees, or lies upside down, each
  physics step pushes it back upright about its forward axis.
- On every wheel: friction 100, small linear and angular damping, and an extra downward force of
  3.5 times gravity, so the wheels grip the ground.
- Small damping on `FrontBar`.
- A helper body: a small sphere, radius 4, that follows the horse's `HorseSpine2` bone every frame.
  It is driven by the animation, not by forces.
- The whole cart joins the horse's collision group, so the horse and the cart do not collide.
- The hitch: a joint from `FrontBar` to the helper. Its point on `FrontBar` is the tip of the
  shafts, about 210 units ahead of and 49 units above the turntable. The tip may slide about 52
  units along an axis close to vertical. It cannot move sideways or forward and back from the
  spine. Every rotation is free.

When the horse stops, the helper stops, and the hitch holds the shaft tip. No brake acts. The
cart loses its speed to wheel friction and damping.

## The harness and the shafts

The harness bones `HarnessLeftBone` and `HarnessRightBone` come from the horse's harness mesh,
`actors\horse\character assets\harness.nif`. They are not in the horse's skeleton. The game moves
them under the cart's `FrontHorseCarriage01` node, at (±50, 163, 13). So the harness is drawn
hanging from the shafts. This changes only the picture.

Each frame the game turns `FrontHorseCarriage01`, the shafts, from its own place toward a point 20
units below `HorseSpine2`. This also changes only the picture.

## What OpenSky follows

OpenSky does not build these bodies and joints. It moves the cart as a trailer instead
([vehicles](/engine/vehicles.md#towing)). From this rig it takes the horse's placement at the start
of the tether and the front axle's 40 degree limit.
