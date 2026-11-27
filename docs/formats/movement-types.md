---
type: File Format
title: Movement types
description: Skyrim SE MOVT records, how an actor picks one, and how its speeds become the
  actor's walk, run, and turn rates.
tags: [format, plugin, actors, movement]
---

# Movement types

A `MOVT` record holds the speeds of one way of moving, such as `NPC_1HM_MT`. Fields: `EDID`,
`MNAM` (a name), `SPED`, `INAM`, `OBND`, and `VMAD`. The `SPED` values are in the record; the
rules for using them are below.

## SPED

11 float32 values, in this order:

| Index | Value | Default |
| --- | --- | --- |
| 1, 2 | Left walk, left run | 100, 500 |
| 3, 4 | Right walk, right run | 100, 500 |
| 5, 6 | Forward walk, forward run | 100, 500 |
| 7, 8 | Back walk, back run | 100, 500 |
| 9, 10 | Rotate in place walk, run | pi |
| 11 | Rotate while moving run | pi |

Speeds are game units per second. Rotations are radians per second, stored as they are: the
install holds values such as 3.142, 6.283, and 1.571. A record of form version 27 or lower has
10 floats, and rotate while moving run takes the rotate in place run value. `SphereDefault_MT`,
`AtronachStorm_Default`, and `NPC_Magic_MT` are such records.

`INAM` holds three thresholds: directional, movement speed, and rotation speed. Each defaults to
"none", the largest float. The game keeps them with the actor's movement data, and no reader is
known. Almost every vanilla record leaves them at none. Wolf and dog set 0.785 radians and 100,
and horses set 100 on the speed threshold.

## Which movement type an actor uses

1. The actor's behaviour graph has an integer variable `iState`. Its value picks a name from the
   graph's list of movement names.
2. That name is matched exactly against every `MOVT` `MNAM`.
3. When the race has an `MTYP` + `SPED` pair for that `MOVT`, the race's `SPED` replaces the
   record's speeds. The record's `INAM` is kept.
4. When no name matches, the game falls back by state to the race's `WKMV`, `RNMV`, `SWMV`,
   `FLMV`, `SNMV`, or `SPMV`: walk, run, swim, fly, sneak, or sprint. Without one, it uses the
   matching default object, "Default MovementType: Walk" and so on. This fallback copies the
   record's speeds without the scaling below.

A race `MTYP` counts only when a `SPED` follows it; a lone `MTYP` is dropped at load.

## The actor's speed table

- The eight linear speeds are multiplied by the actor's scale (the reference scale times the
  `NPC_` height), then by SpeedMult (actor value 30) / 100. A SpeedMult of 0 counts as 100.
- The rotations are not scaled.
- An over-encumbered actor, whose inventory weight is above its carry weight after the carry
  weight entry point, runs at its walk speeds.
- Otherwise each run speed is `max(walk, run * f)`, with
  `f = 1 - effect * (min(w, fMoveWeightMax) + fMoveWeightMin) / (fMoveWeightMax - fMoveWeightMin)`.
  `effect` is `fMoveEncumEffect` (0.3) with a weapon drawn, else `fMoveEncumEffectNoWeapon`
  (0.15). `fMoveWeightMax` is 115 and `fMoveWeightMin` is 0. `w` is a weight of the actor's
  equipment; which weight is not known.
- An actor can strafe only when all four left and right speeds are above 0.

## Normalized speed

Paths and the AI ask for a speed `n` on a scale where 1 is walk and 2 is run. With forward walk
`W` and forward run `R`:

| `n` | Units per second |
| --- | --- |
| up to 1 | `n * W` |
| 1 to 2 | `(2 - n) * W + (n - 1) * R` |
| above 2 | `(n - 1) * R` |

Example: with `W` 80 and `R` 370, `n = 1.5` is 225 units per second. A normalized turn speed
uses rotate in place walk and run the same way.

## Acceleration

The race's `DATA` acceleration `A`, deceleration `D`, and angular acceleration `G` are times in
seconds ([RACE DATA](/formats/actors.md#race-data-in-the-game)):

- acceleration = `max(R, speed) / A`, in units per second squared;
- deceleration = `max(R, speed) / D`;
- angular acceleration = `max(|turn rate|, T) / G`, in radians per second squared.

`T` is rotate in place run when the requested speed is below 5 units per second, or when the
actor can strafe and its graph allows it; otherwise it is rotate while moving run. A value
within 0.0001 of zero counts as 1. So a larger value ramps more slowly. The path code uses the
same numbers: it predicts a stop in `|v| / deceleration` seconds over `v^2 / (2 * deceleration)`
units.

| `A` | Acceleration with `R` = 370 | Time to run speed | In combat pathing |
| --- | --- | --- | --- |
| 1 | 370 units/s² | 1 s | 0.5 s |
| 4 | 92.5 units/s² | 4 s | 2 s |

The game's per-frame step is not known in detail. The rule above implies
`speed += min(acceleration * dt, target - speed)`, and the same for the turn rate.
