---
type: Subsystem
title: Dragon flight
description: How a dragon takes off, circles, hovers, perches, and lands, on its own in a fight and under the player, and how its behavior graph, effects, and conditions follow.
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
| 5 | Perched | Sits on a perch: a word wall, a tower, or a rock |

`GetIsFlying` and `Actor.IsFlying` are 1 in phases 1 to 5. The CK wiki says the value becomes 0
when the landing animation on the ground completes. A perch has no navmesh, so a perched dragon
still counts as flying. [INFO] That reading of value 5 is OpenSky's.

The goal of each step is chosen in this order:

1. A dragon that dies in the air comes down with a crash landing.
2. A dragon under Dragonrend comes down with a hasty landing. The shout's effect raises the
   actor value `Dragon Rend`; OpenSky reads any value above 0.
3. A forced order from agent control.
4. An injured dragon in a fight lands beside its target.
5. The fight stage: air circles the target at `fCombatOrbitDistance` (4,000), perch lands on a
   perch (or hovers when none fits), and ground lands 600 units from the target, on the side
   the dragon comes from.

`SetAllowFlying(false)` and an interior keep a dragon on the ground. A dead dragon on the ground
does not take off again.

`GetIsInjured` is 1 when health is below the race's injured health share
(<https://ck.uesp.net/wiki/GetIsInjured>). `DragonRace` sets it to 0.35.

## Perches

A perch is a piece of furniture with the `MNAM` flag `0x04000000`, such as `DragonPerchTower`
(`0x01E595`), `DragonPerchRockL02` (`0x0AA934`), and the word wall perch `DragonPerchWordwall`
(`0x01CC4A`). Its seat gives the feet and the facing.

In the perch stage of a fight, the dragon lands on the nearest perch that is within
`fCombatLandingSearchDistance` (6,000) of the target and faces it within
`fCombatPerchMaxTargetAngle` (75°). [INFO] The nearest-first order is OpenSky's. The forced
`perch` order takes the nearest perch within the search distance, whatever it faces. A perched
dragon sits until the goal changes, then raises `TakeOff`.

## Landings

The engine lands a dragon with the action `ActionFlyStop`. Its idle tree `FlyStopRootDragon`
picks the graph event. OpenSky runs that tree through the idle selector, so the order and the
conditions are the game's own. The main children, in order; the first match wins:

| Child | Condition | Event |
| --- | --- | --- |
| `FlyStopPerchRoot` | `GetIsID` on the perch furniture | `FlyStopPerchTower`, `FlyStopPerchRockL02`, ... |
| `FlyStopCrashHasty` | `GetIsHastyLandRequest` == 1 | `FlyStopHasty` |
| `FlyStopCrash` | `GetIsCrashLandRequest` == 1 | `FlyStopCrash` |
| `FlyStopInjured` | `GetIsInjured` == 1 | `FlyStopInjured` |
| `FlyStopHastyAlways` | `IsInList` `DragonAlwaysCombatLandsList` | `FlyStopHasty` |
| `FlyStopDefault` | none | `FlyStopDefault` |

The tree also holds `FlyStopCrashHastyVertical`, `FlyStopInjuredSafe`, and
`FlyStopDefaultSafe`. Each child also tests `IsFurnitureAnimType` == 0. Where the tree gives no
event, OpenSky raises the event of the landing kind directly.

A landing request (hasty or crash) starts the approach at once, without the long glide.
`GetIsHastyLandRequest` and `GetIsCrashLandRequest` are 1 for that dragon until it touches down.
[INFO] The game does not show what sets a request. OpenSky's reading: death in the air is a
crash (UESP "Skyrim:Dragon" describes dying dragons crashing down), and Dragonrend is hasty.

## Numbers

| Number | Value | Source |
| --- | --- | --- |
| Cruise speed | 2,000 units/s | `Dragon_Flying_MT` forward walk speed (`MOVT` `SPED`) |
| Turn rate in flight | π/2 rad/s | `Dragon_Flying_MT` rotate in place; `fFlyingActorDefaultTurningSpeed` agrees |
| Turn rate in a hover | π/4 rad/s | `Dragon_Hovering_MT` rotate in place |
| Take-off time | 5 s | Length of the clip `mttakeoff45.hkx` |
| Approach time | 3.33 s | Length of the clip `mtland45approach.hkx` |
| Perch search distance | 6,000 | `fCombatLandingSearchDistance` |
| Perch angle | 75° | `fCombatPerchMaxTargetAngle` |
| Breath inhale | 1 s | Length of the clip `shout_flightinhale.hkx` |
| Flight height | 1,500 above the ground | OpenSky |
| Hover height | 700 above the ground | OpenSky |
| Climb rate | 500 units/s | OpenSky |
| Slowest landing speed | 300 units/s | OpenSky |

The dragon movement types have a 40-byte `SPED`, 10 floats
([records](/formats/records.md)). `Dragon_Flying_MT` runs at 7,400; OpenSky flies at the walk
speed, because circling at 7,400 needs a turn circle wider than the orbit.

The OpenSky numbers cannot be read from data. The flight height, the climb, and the landing speed
come from the game's pathing for flying actors, which no record or setting holds. They were chosen
so the clips line up with the motion.

## The behavior graph

`dragonbehavior.hkx` was stepped offline with `openskycli hkx <path> --raise <event>` (repeated) to
find which event moves it where:

| Event | From | To |
| --- | --- | --- |
| `TakeOff` | `ST_Ground` or a perch idle | `ST_TakeOff`, then `ST_Flight` by itself after the clip |
| `HoverStart` | `ST_Flight` | `ST_Hover` |
| `HoverStop` | `ST_Hover` | `ST_Flight` |
| `FlyStopDefault` | `ST_Flight` | `ST_Land`: the approach clip, then the touchdown, then `ST_Ground` |
| `FlyStopHasty` | `ST_Flight` | The short touchdown |
| `FlyStopCrash` | `ST_Flight` | The crash slide along the ground |
| `FlyStopInjured` | `ST_Flight` | The injured touchdown |
| `FlyStopPerchTower` | `ST_Flight` | The tower landing, then `ST_Perch_Tower_Idle` |
| `FlyStopPerchRockL02` | `ST_Flight` | The rock landing, then its perch idle |
| `shoutStart` | `ST_Flight` | The breath inhale |
| `shoutRelease` | The inhale | The exhale; the spell fires on `Voice_SpellFire_Event` |

`FlyStartRequest` and `FlyStartRequestVertical` do not leave `ST_Ground`. `FlyStopDefault` does
nothing in `ST_Hover`, so a landing from a hover first raises `HoverStop`. The approach clip runs
for its own length, so `DistToGoal` does not time it. OpenSky therefore raises the landing event
only when the dragon is less than one approach time from its landing point. The landing order is
set earlier, so `GetFlyingState` is 4 for the whole descent. From that point the landing cannot be
called off: `TakeOff` in `ST_Land` does not stop the touchdown.

Each step writes `TargetSpeed`, `PitchDelta`, `MoveDirZ`, `DistToGoal`, `TweenPosition`,
`TweenRotation`, and `IsOnGround`. `IsOnGround` is 1 on the ground and on a perch. The graph step
writes `Speed` and `TurnDelta` itself. The rider's `0_master.hkx` reads `PitchOffset`; OpenSky
writes the mount's climb angle there. [INFO] That reading is OpenSky's.

## Clip events

`DragonActorScript` registers for `DragonLandEffect`, `DragonTakeoffEffect`, the wing and tail
attack events, and the crash landing start, and plays the camera shake and impacts itself. The
engine reads the events no script registers for:

- `FlightLandingEffect`, on the wing beats of the approach clips: dust on the ground under the
  dragon. [INFO] The game names no impact set for it; OpenSky plays `FXDragonTakeoffImpactSet`.
- `FlightForcefulLandStart`, `FlightCrashLandStart`, and `FlightCrashLandEnd`: the touchdown. A
  landing dragon ends its flight on the ground under it. On a perch these are ignored; the dragon
  ends on the perch.
- `FlightCrashLandLoadEffect`, on the crash approach clips: nothing to load in OpenSky.

A dragon that unloads in the air drops to the ground under it.

## Riding

The rider does not steer (UESP "Skyrim:Dragon Riding",
<https://en.uesp.net/wiki/Skyrim:Dragon_Riding>). The keys are orders:

| Key | Order |
| --- | --- |
| Jump | Lock the actor nearest the view centre, or unlock the one locked |
| Sneak | Attack the locked target, or stop |
| Use | In the air: land, or call the landing off. On the ground: dismount |
| Hotkey 1 and 2 | Switch Target: the next actor to the left or the right |

Switch Target uses the favourites hotkeys 1 and 2 (UESP "Skyrim:Controls",
<https://en.uesp.net/wiki/Skyrim:Controls>). It steps through the living actors within 60° of
the view, left to right, and wraps round. Switching ends an attack. [INFO] The 60° cone is
OpenSky's.

Without a target the dragon circles where it took off, 3,000 units out. Attacking, it circles the
target 1,500 units out. Every 6 seconds, when the target is within 3,500 units and within 90° of
its heading, it raises `shoutStart`, waits for the 1 s inhale, raises `shoutRelease`, and casts its
strongest shout when the graph sends `Voice_SpellFire_Event`. If the graph sends no event, the
shout casts 1 s into the exhale. The landing order shows `sTESVDLC2FlyingMountLandingMessage`, and
calling it off `sTESVDLC2FlyingMountCancelLandingMessage`. After
`Game.SetAllowFlyingMountLandingRequests(false)` the order is refused with
`sTESVDLC2FlyingMountCannotLandMessage`
(<https://ck.uesp.net/wiki/SetAllowFlyingMountLandingRequests_-_Game>). `IsOnFlyingMount` is 1
only while the ridden dragon is in the air.

The rider can shout and cast a readied spell, but not swing a weapon. A refused spell shows
`sTESVDLC2FlyingDragonNoCastMessage`. No record lists the allowed spells, so OpenSky's rule
follows the UESP list and its note "Area of effect spells or summons cannot be used". It refuses:

- a spell with target-location delivery, such as a rune;
- a summon, reanimation, bound weapon, hazard, cloak, telekinesis, detect life, guide, or
  invisibility effect;
- a self-delivered hostile effect with an area, such as Fire Storm.

Aimed spells, wards, healing, and light pass. Candlelight and Magelight are on the UESP list.

## Checking it

`openskycli game debug flight <ref> takeoff|land|perch|hasty|crash` forces a flight, also for the
ridden dragon. `openskycli game state flight [<ref>]` shows each flight: phase, position, speed,
the approach, the landing request and its graph event, the perch, and the order. The ridden flight
adds a `rider` block with the locked and switched target. `state mount` shows the player's mount
with the rider's orders and the breath step.

## Where OpenSky differs

- [INFO] What sets a crash or hasty request is OpenSky's reading (see [landings](#landings)).
- [INFO] An injured dragon lands at once; the game may first try to reach a safe spot
  (`FlyStopInjuredSafe`).
- [INFO] The flight heights, the climb rate, the radii, the lock and switch cones, and the breath
  timing are OpenSky's numbers.
- [INFO] The rider's spell rule is OpenSky's, built from the UESP list.
