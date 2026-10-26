---
type: Subsystem
title: Dragon flight
description: How a dragon takes off, circles, hovers, and lands, on its own in a fight and under the player, and how its behavior graph, effects, and conditions follow.
tags: [engine, animation, combat, player]
---

# Dragon flight

A dragon flies in two cases. A dragon nobody rides flies when its fight is in the air stage
([combat behaviour](/engine/combat-behavior.md#flying-combat)), or when agent control orders a
take-off. A dragon the player rides flies from the moment the rider is seated
([riding](/engine/riding.md)). Both use one set of flight rules. In both cases, the rules move the
body and its behavior graph only plays the clips.

## Phases

The phases are the `GetFlyingState` values
(<https://ck.uesp.net/wiki/GetFlyingState_-_Actor>):

| Value | Phase | What the dragon does |
| --- | --- | --- |
| 0 | On the ground | Walks with its packages and mover |
| 1 | Taking off | Climbs to its flight height; the speed grows to the cruise speed |
| 2 | Cruising | Flies round a centre: the target in a fight, else where it took off |
| 3 | Hovering | Stops in the air and turns to face a point |
| 4 | Landing | Flies to a landing point and comes down |

`GetIsFlying` and `Actor.IsFlying` are 1 in phases 1 to 4. The CK wiki says the value becomes 0
when the landing animation completes. Value 5, perched on a word wall or a rock, is not modelled.

The fight stage picks the goal: air circles the target at `fCombatOrbitDistance` (4,000), perch
hovers and faces the target, and ground lands 600 units from the target, on the side the dragon
comes from. A forced order wins over the fight. `SetAllowFlying(false)` and an interior keep a
dragon on the ground.

## Numbers

| Number | Value | Source |
| --- | --- | --- |
| Cruise speed | 2,000 units/s | `Dragon_Flying_MT` forward walk speed (`MOVT` `SPED`) |
| Turn rate in flight | π/2 rad/s | `Dragon_Flying_MT` rotate in place |
| Turn rate in a hover | π/4 rad/s | `Dragon_Hovering_MT` rotate in place |
| Take-off time | 5 s | Length of the clip `mttakeoff45.hkx` |
| Approach time | 3.33 s | Length of the clip `mtland45approach.hkx` |
| Flight height | 1,500 above the ground | OpenSky |
| Hover height | 700 above the ground | OpenSky |
| Climb rate | 500 units/s | OpenSky |
| Slowest landing speed | 300 units/s | OpenSky |

The dragon movement types have a 40-byte `SPED`, 10 floats
([records](/formats/records.md)). `Dragon_Flying_MT` runs at 7,400; OpenSky flies at the walk
speed, because circling at 7,400 needs a turn circle wider than the orbit.

## The behavior graph

`dragonbehavior.hkx` was stepped offline with `openskycli hkx <path> --raise <event>` (repeated) to
find which event moves it where:

| Event | From | To |
| --- | --- | --- |
| `TakeOff` | `ST_Ground` | `ST_TakeOff`, then `ST_Flight` by itself after the clip |
| `HoverStart` | `ST_Flight` | `ST_Hover` |
| `HoverStop` | `ST_Hover` | `ST_Flight` |
| `FlyStopDefault` | `ST_Flight` | `ST_Land`: the approach clip, then the touchdown, then `ST_Ground` |

`FlyStartRequest` and `FlyStartRequestVertical` do not leave `ST_Ground`. `FlyStopDefault` does
nothing in `ST_Hover`, so a landing from a hover first raises `HoverStop`. The approach clip runs
for its own length, so `DistToGoal` does not time it. OpenSky therefore raises `FlyStopDefault`
only when the dragon is less than one approach time from its landing point. The landing order is
set earlier, so `GetFlyingState` is 4 for the whole descent. From that point the landing cannot be
called off: `TakeOff` in `ST_Land` does not stop the touchdown.

Each step writes `TargetSpeed`, `PitchDelta`, `MoveDirZ`, `DistToGoal`, `TweenPosition`,
`TweenRotation`, and `IsOnGround`. The graph step writes `Speed` and `TurnDelta` itself. The rider's
`0_master.hkx` reads `PitchOffset`; OpenSky writes the mount's climb angle there. [INFO] That
reading is OpenSky's.

## Clip events

`DragonActorScript` registers for `DragonLandEffect`, `DragonTakeoffEffect`, the wing and tail
attack events, and the crash landing start, and plays the camera shake and impacts itself. The
engine reads the events no script registers for:

- `FlightLandingEffect`, on the wing beats of the approach clips: dust on the ground under the
  dragon. [INFO] The game names no impact set for it; OpenSky plays `FXDragonTakeoffImpactSet`.
- `FlightForcefulLandStart`, `FlightCrashLandStart`, and `FlightCrashLandEnd`: the touchdown. A
  landing dragon ends its flight on the ground under it.
- `FlightCrashLandLoadEffect`, on the crash approach clips: nothing to load in OpenSky.

A dragon that dies or unloads in the air drops to the ground under it.

## Riding

The rider does not steer (UESP "Skyrim:Dragon Riding",
<https://en.uesp.net/wiki/Skyrim:Dragon_Riding>). The keys are orders:

| Key | Order |
| --- | --- |
| Jump | Lock the actor nearest the view centre, or unlock the one locked |
| Sneak | Attack the locked target, or stop |
| Use | In the air: land, or call the landing off. On the ground: dismount |

Without a target the dragon circles where it took off, 3,000 units out. Attacking, it circles the
target 1,500 units out and breathes its strongest shout at it every 6 seconds from within 3,500
units. The landing order shows `sTESVDLC2FlyingMountLandingMessage`, and calling it off
`sTESVDLC2FlyingMountCancelLandingMessage`. The rider can shout and cast a readied spell, but not
swing a weapon. `IsOnFlyingMount` is 1 only while the ridden dragon is in the air.

## Checking it

`openskycli game debug flight <ref> takeoff|land` forces a flight, also for the ridden dragon.
`openskycli game state flight [<ref>]` shows each flight: phase, position, speed, the approach,
and the order. `state mount` shows the player's mount with the rider's orders.

## Where OpenSky differs

- [INFO] Perching on a word wall or a rock (state 5) is a hover in the air; perch markers are
  not read.
- [INFO] Only the default landing plays; the hasty and crash landings are not chosen.
- [INFO] Switch Target is not bound. A locked target that dies unlocks.
- [INFO] The ridden dragon's breath is cast straight at the locked target, not aimed by the
  breath clip.
- [INFO] The flight heights, the climb rate, the radii, the lock cone, and the breath timing are
  OpenSky's numbers.
- [INFO] The rider's spells are not limited to the vanilla list; any readied spell casts.
