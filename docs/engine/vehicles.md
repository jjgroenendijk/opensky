---
type: Subsystem
title: Vehicles
description: How a reference rides another - a cart towed by a horse, a rider on a cart or on a horse - and how the rest of the engine sees the rider.
tags: [engine, papyrus, actors]
---

# Vehicles

A vehicle is a reference that carries another reference. There are three kinds of link:

- A cart towed by a horse: `TetherToHorse(horse)` on the cart.
- A rider on a vehicle: `SetVehicle(vehicle)` on an actor. `SetVehicle(None)` takes the actor
  off again.
- A rider on a horse: a placed actor whose `ACHR` has an `XHOR` field
  ([placed references](/formats/placed-references.md)) rides that horse while its package's "Ride
  Horse if possible?" input is true ([package schedules](/engine/package-schedules.md)).

Sources: <https://ck.uesp.net/wiki/SetVehicle_-_Actor> and
<https://ck.uesp.net/wiki/TetherToHorse_-_ObjectReference>.

Each frame, after the idles and the packages, the vehicle pass computes every follower's pose from
its carrier's live pose. A chain works through the same pass: a rider follows the cart, and the
cart follows the horse. A link that would make a loop is refused. A chain deeper than 8 links gives
no pose, because only a loop in plugin or script data can make one.

## Towing

In the game, a towed cart is a physics body pulled by the horse. OpenSky does not simulate it. It
moves the cart as a trailer instead:

- The link keeps the horizontal distance from the cart's origin to the horse's origin.
- Each frame the cart moves along the line from where it was toward the horse, until it is that
  distance behind the horse. So the cart trails the horse's path and cuts corners, and a horse
  that turns on the spot does not swing the cart sideways.
- The cart turns by the change of its heading toward the horse.
- The cart's origin rests on the ground, and it tilts with the slope between itself and the
  horse. The prisoner carriage's model bounds start at z 0, so its origin is its lowest point.
  Plugins place carts a little above the terrain (`Cart1` sits 11.5 units up) and the game's
  physics settles them; OpenSky drops the origin onto the ground instead.
- The ground is the highest of the terrain and the static collision below a point 128 units
  above the cart or the horse, so a bridge or a paved road counts and a roof above does not.
  The carts and horses in a link are not ground. Without ground the cart keeps its height
  relative to the horse.

[WARNING] The trailer rule approximates the game's physics. It is not taken from an open spec.

## Riders

`SetVehicle` puts the rider's root on the vehicle's root. The rider's seat idle then moves the body
into its seat. In the cart idles, such as `IdleCartPrisonerCIdle`, the root bone has no offset and
the `NPC COM` bone carries the seat, for example (-33.5, -199.6, 138.8) for seat A, in the cart's
frame. This was read from the clips on the install.

A seat idle holds: its state in `0_master.hkx` plays a looping clip (`m_mode` 1), so the rider stays
seated until another idle, such as a cart exit, replaces it ([idle runtime](/engine/idle-runtime.md)).

The player follows the same rule. The player's root sits on the vehicle's root. While the player
plays a seat idle, the first-person eye goes to the clip's `NPC Head [Head]` bone, so the view sits
where that seat's head is. Without an idle, the eye sits the standing eye height above the vehicle's
root.

A horse rider's root sits on the horse's `SaddleBone`, a node of
`meshes\actors\horse\character assets\skeleton.nif` (read on the install). The bone comes from the
horse's live pose every frame, so the rider moves with the horse's gait. Until the horse's skeleton
loads, the rider sits on the horse's root.

The horse walks the rider's package, so it is the horse that enters triggers. The rider plays the
clips in `meshes\actors\character\animations\horse_rider\`: `idle.hkx` while the horse stands, and
`walkforward.hkx` or `runforward.hkx` as the horse walks or runs. [WARNING] The walk and run names
follow the horse's own folder; `idle.hkx` was seen on the install. A clip that does not load leaves
the rider in the clip it plays.

## Where the rest of the engine sees a rider

A rider's vehicle pose is its live pose. Every system that asks where an actor is reads it: the
dialogue camera and the speaker's position, the AI packages, combat, perception, and magic. So a
rider talks from its seat, not from where it was placed.

## Drawing

A follower that is not the player is drawn with a delta matrix: its live pose times the inverse of
the placement the cell build drew. The renderer computes it, because only the built scene knows that
placement. The world state is not enough: a walk or a cell crossing writes a new pose there before the
cell is rebuilt with it. The renderer applies the delta on top of the other instance deltas, and a
vehicle delta wins. The cell build marks every follower as simulated, so its draw instance keeps its
FormID.

The player is not drawn this way. The player's feet are placed at the live pose each frame.

A follower is drawn by one cell. When its pose enters another loaded cell, it moves into that cell
and the old cell is rebuilt without it, so it does not vanish when the old cell unloads. For the
frames until the rebuild lands, the old cell still draws it, from its old placement.

## Leaving a vehicle

The cart exit idles, such as `IdleCartPassengerAExit`, lead to a state of the `Cart` machine in
`0_master.hkx`. The state sends `ExitCartBegin` when it starts and `ExitCartEnd` when it ends, and
it ends with its clip, which plays once (`m_mode` 0). OpenSky takes the rider off the vehicle on
`ExitCartEnd`, for any actor that plays such a state. [WARNING] The game's rule is not documented.
`MQ101` never calls `SetVehicle(None)` for its riders, so the game must end the link on its own,
and this event is the one the graph sends at that moment.

## Saving

The link is the world state component `vehicleLink`. It is not written to a save. The game allows
no save during the cart ride, so a save never holds one. When a follower leaves its carrier, its
last pose is kept as a transform override. The follower also stands there: the walk it made
before it got on no longer counts as where it is.

## Where OpenSky differs

- `Game.SetHudCartMode` and `Game.SetSittingRotation` do nothing yet. The HUD movie has a `CartMode`
  among its HUD modes, but OpenSky does not drive HUD modes yet. The second turns the player in the
  seat; the player keeps the view it had.
- The cart's wheels do not turn, and the cart does not roll sideways on uneven ground.
