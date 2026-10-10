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

A link stores one offset: the follower's pose in the carrier's frame. Each frame the
follower's pose is the carrier's live pose times that offset. So a rider follows the cart,
and the cart follows the horse, through one chain.

A tether keeps the offset the cart had to the horse at the moment of the link. `SetVehicle`
does not: it puts the rider's root on the cart's root. The cart idle then moves the body
into its seat. In the cart idles, such as `IdleCartPrisonerASway`, the root bone has no
offset and the `NPC COM` bone carries the seat, for example (-33.5, -199.6, 138.8) for seat
A, in the cart's frame. Seats B, C, and D are further forward, and the driver is at the
front. This was read from the clips on the install.

The player plays no cart idle, so its feet get a fixed seat: seat C at (-42.0, -104.7), and
67.5 units up. That height is seat C's hip height, 138.8, less a standing hip height of 71.3,
the `NPC COM` height at the end of the cart exit clip. So the eye sits about where a seated
rider's eye is. [WARNING] This seat is derived from the clips, not from an open spec.

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

The rider's root goes on the horse's `SaddleBone`, a node of
`meshes\actors\horse\character assets\skeleton.nif` (read on the install). Its position is taken
from the horse's drawn pose at the moment the rider is seated. A horse whose skeleton did not load
seats the rider 90 units above its feet instead.

The rider plays the clips in `meshes\actors\character\animations\horse_rider\`: `idle.hkx`
while the horse stands, and `walkforward.hkx` or `runforward.hkx` as the horse walks or runs.
[WARNING] The walk and run names follow the horse's own folder; `idle.hkx` was seen on the
install. A clip that does not load leaves the rider in the clip it plays.

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

- `Game.SetHudCartMode` and `Game.SetSittingRotation` do nothing yet. The HUD movie has a
  `CartMode` among its HUD modes, but OpenSky does not drive HUD modes yet. The second turns
  the player in the seat; the player keeps the view it had.
- The cart's wheels do not turn, and the cart does not tilt on uneven ground.
