---
type: Subsystem
title: Vehicles
description: How a cart follows its horse and a rider follows the cart, as the opening of the game needs.
tags: [engine, papyrus, actors]
---

# Vehicles

A vehicle is a reference that carries another reference. The opening of the game has two
kinds. A cart is tethered to a horse, and the riders sit on the cart. The quest `MQ101`
sets both up in the fragment of stage 12.

Sources: <https://ck.uesp.net/wiki/SetVehicle_-_Actor> and
<https://ck.uesp.net/wiki/TetherToHorse_-_ObjectReference>. The behaviour below was
checked against the `MQ101` fragments in the user's install.

## Links

- `TetherToHorse(horse)` on the cart links the cart to the horse.
- `SetVehicle(cart)` on an actor links the actor to the cart. `SetVehicle(None)` takes
  the actor off again.

A link stores one offset: the follower's pose in the carrier's frame at the moment of the
link. Each frame the follower's pose is the carrier's live pose times that offset. So a
rider follows the cart, and the cart follows the horse, through one chain.

A link that would make a loop is refused. A chain deeper than 8 links gives no pose,
because only a loop in plugin or script data can make one.

## Drawing

A follower that is not the player is drawn with a delta matrix: its live pose times the
inverse of the pose the cell build drew. The renderer applies it on top of the other
instance deltas, and a vehicle delta wins. The cell build marks every follower as
simulated, so its draw instance keeps its FormID.

The player is not drawn this way. The player's feet are placed at the live pose each frame.

A follower is drawn by one cell. When its pose enters another loaded cell, it moves into that
cell and the old cell is rebuilt without it, so it does not vanish when the old cell unloads.
For the frames until the rebuild lands, the old cell still draws it.

## Riders

A placed actor whose `ACHR` has an `XHOR` field starts on that horse
([placed references](/formats/placed-references.md)). In the opening, General Tullius and
Hadvar ride ahead of the carts this way, and the gate triggers of `MQ101` stages 20 to 26
wait for their horses (`MQ101Horse`). A riding package seats the rider on the horse with a
vehicle link. The horse then walks the rider's package, so it is the horse that enters the
triggers.

[WARNING] The seat is 90 units above the horse's feet. This is an estimate: the game seats
the rider on the horse's saddle node, which OpenSky does not read yet. There is no riding
animation yet.

## Leaving a vehicle

The cart exit idles, such as `IdleCartPassengerAExit`, lead to a state of the `Cart` machine in
`0_master.hkx`. The state sends `ExitCartBegin` when it starts and `ExitCartEnd` when it ends,
and it ends with its clip ([idle runtime](/engine/idle-runtime.md)). OpenSky takes the rider off
the vehicle on `ExitCartEnd`.
`MQ101` never calls `SetVehicle(None)` for its riders, so the game must do the same.
[WARNING] This rule is inferred from the `MQ101` scripts, not from an open spec.

## Saving

The link is the world state component `vehicleLink`. It is not written to a save. The
game allows no save during the cart ride, so a save never holds one. When a follower leaves
its carrier, its last pose is kept as a transform override.

## Where OpenSky differs

- `Game.SetHudCartMode` and `Game.SetSittingRotation` do nothing yet. The first hides the
  HUD during the ride; the second turns the rider in the seat.
- The cart's wheels do not turn, and the cart does not tilt on uneven ground.
