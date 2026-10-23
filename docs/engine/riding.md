---
type: Subsystem
title: Riding
description: How the player mounts, steers, and dismounts a horse or a tamed dragon, and how the two behavior graphs, crime, and conditions follow.
tags: [engine, player, animation]
---

# Riding

The player mounts a horse or a tamed dragon with the use key. While mounted, the movement keys
drive the horse, and the use key dismounts. A cart rider, which the player does not steer, is in
[vehicles](/engine/vehicles.md).

## Who can be mounted

An actor can be mounted when all of these pass:

- Its skeleton has a saddle bone: `SaddleBone` (horse) or `NPC Saddlebone` (dragon). [INFO] The
  game reads a race flag; OpenSky reads the skeleton, because every vanilla mount race has the bone.
- It is alive, and no other actor rides it.
- A dragon (keyword `ActorTypeDragon`) passes the perk entry point Allow Mount Actor (91), with the
  dragon as the target ([perk entry points](/engine/perk-entry-points.md#activation)).

A horse somebody else owns asks `sStealHorse` ("Do you want to steal this horse?") first. Yes
mounts it and reports a theft worth `iCrimeGoldStealHorse` (100), with the owner as the victim
([crime](/engine/crime.md)). The crosshair prompt on a mountable actor reads `sRide`.

Sources: <https://ck.uesp.net/wiki/Settings>, the game settings read on the install.

## Mounting and dismounting

Both graphs play one paired clip. A paired clip holds the tracks of both characters; the horse's
tracks carry the prefix `2_` ([behavior clips](/engine/behavior-clips.md)).

| Step | Rider graph (`0_master.hkx`) | Mount graph |
| --- | --- | --- |
| Mount | `HorseEnter`, leads to `MountSynced` | `pa_HorseEnter` |
| Seated | `pairedStop` leads to `HorseRider_State`, which sets `bIsRiding` | |
| Dismount | `HorseExit`, leads to `DismountSynced` | `pa_HorseExit` |
| Off | `HorseExitOut` returns to `Default` | |

A dragon uses `DragonMountEnter`, `pa_DragonMountEnter`, `DragonMountExit`, `pa_DragonMountExit`,
and `DragonMountExitOut`. These names were read from the graphs on the install.

During the clip the player's root is linked to the mount's root. On `pairedStop` the root moves
to the saddle bone. When the exit event comes, the player stands at the race's dismount offset,
turned with the mount. [INFO] Only x (right) and y (forward) of the offset are used; the player
then falls to the ground. A phase whose end event never comes ends after 4 seconds, so a missing
clip cannot hold the player.

## Steering

The mount runs its own graph through a second locomotion bridge and its own capsule. The rider's
graph only follows: it reads the mount's speed, turn, and sprint.

- The movement keys, read against the camera's yaw, name a direction. The mount turns toward it
  at `iHorseTurnDegreesPerSecond` (45) degrees a second and moves forward.
- Walk and run speeds come from the movement type `Horse_Default_MT`; sprint uses the run speed of
  `Horse_Sprint_MT`.
- Jump raises `forwardJumpStart` while moving and `standingRearUp` while standing.
- The rider may look down at most `fMountedMaxLookingDown` (40) degrees.
- The rider keeps melee weapons, bows, and crossbows. Sneak, block, shouts, and attacks with
  anything else (fists, staves, spells) are dropped. Source: UESP "Skyrim:Combat", Horse-Mounted
  Combat. Drawing a
  weapon writes `iCombatStance` on the mount ([actor state graph](/engine/actor-state-graph.md)).
- A door is refused with `sNotAllowedToUseAutoDoorsWhileonHorse`
  ([interaction](/engine/interaction.md)).

While mounted, the player's `iState` takes `iState_NPCHorse`, or `iState_HorseSprint` while the
mount sprints.

The mount is taken from its AI packages and its graph runner while ridden, and given back on
the dismount. A mount that dies or unloads drops the rider at once.

## Conditions and scripts

`IsRidingMount`, `IsBeingRidden`, and `IsPlayersLastRiddenMount` answer for the player too.
`IsOnFlyingMount` is 1 on a dragon ([world condition functions](/engine/condition-functions-world.md)).
`Actor.Dismount()` starts the dismount clips and returns true when it did.

## Where OpenSky differs

- [WARNING] A dragon is not flown. It stands still while the player sits on it.
- [INFO] The ridden mount's capsule (radius 40, height 160) is OpenSky's value.
- [INFO] `iHorseTurnDegreesRampUpPerSecond` is not used; the turn rate is constant.
- [INFO] Horse stamina is not spent while sprinting.
- [INFO] The camera eye sits the player's standing eye height above the saddle.
