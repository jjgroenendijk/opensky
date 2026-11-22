---
type: Subsystem
title: Combat approach
description: How a fighter in the game closes in on its target - the two advance radii, the
  speed in each distance band, and when it sprints - and what OpenSky does.
tags: [engine, combat, combat-ai, npc, movement]
---

# Combat approach

A fighter that walks toward its target changes its speed with the distance. Far away it runs.
Near the target it slows down, so it does not run past. The game works this out from two advance
radii and three distance bands.

Behaviour described from a clean-room read of the game program (1.6.1170) on 2026-11-22. The
values are the ones that apply in play: `Skyrim.esm` where it overrides the program's default.

## Advance radii

The game works out an inner and an outer advance radius for each fighter.

1. x = D − O.
   - D is the Defensive Mult of the [combat style](/engine/combat-behavior.md#combat-style).
     Against a staggered target D is multiplied by `fCombatAdvanceRadiusStaggerMult`, which is
     0. So every fighter is fully offensive against a staggered target.
   - O is the style's Offensive Mult. When the style's Group Offensive Mult is below 1 and the
     group has n members, n above 1, O is multiplied by the larger of GroupOffensive^(n − 1)
     and `fCombatGroupOffensiveMultMin`, 0.1. Which group is counted was not confirmed; most
     likely the actors that fight the same target.
2. Each radius is a blend over x: x = −1 gives `Min`, x = 0 gives `Mid`, and x = 1 gives `Max`.
   The blend is a straight line on each side of 0.
3. When x is above 0, both radii fall back to `Mid` in two cases: the fighter was last damaged
   more than `fCombatAdvanceLastDamagedThreshold`, 10 seconds, ago; or the fighter's reach and
   the reach of the target's weapon differ by more than the inner radius.
4. The fighter's own reach is added to both radii.

| Setting | Min | Mid | Max |
| --- | --- | --- | --- |
| `fCombatAdvanceInnerRadius...` | 0 | 0 | 256 |
| `fCombatAdvanceOuterRadius...` | 128 | 256 | 512 |

For example, a skeever's style has Offensive Mult 1 and Defensive Mult 0, so x = −1. Its inner
radius is its reach, and its outer radius is 128 units plus its reach.

## Speed

The game uses four speed levels. Walk is 1, fast walk 1.33, jog 1.66, and run 2. On this scale
1 is the actor's walk speed and 2 its run speed, with a straight line between them. The values
are built into the program.

The approach works out its speed again every `fCombatApproachTargetUpdateTime`, 0.25 seconds,
and every `fCombatApproachTargetSlowdownUpdateTime`, 0.05 seconds, while it slows down. The
distance it uses is the larger of the straight distance and the path length that is left.

```mermaid
flowchart TD
    D[Distance to the target] --> A{"Beyond the outer radius,<br/>or the target is staggered?"}
    A -- yes --> R[Run. A sprint is allowed]
    A -- no --> B{"Beyond the inner radius + 96?"}
    B -- yes --> F["Fast walk + the target's retreat speed,<br/>at most run"]
    B -- no --> S[Slow down toward the target]
```

- The retreat speed is the target's speed straight away from the fighter.
- In the middle band, a sprint is allowed when the sum reaches the run limit.
- The slow band starts at the inner radius plus `fCombatApproachTargetSlowdownDistance`, 96
  units. Inside it the speed is a blend by distance: half the base at distance 0, the base at
  the inner radius, and the middle band's speed at the band's edge.
- The base is the larger of walk and the target's retreat speed, when the fighter moves within
  `fCombatApproachTargetSlowdownVelocityAngle`, 135 degrees, of the direction to the target.
  Otherwise the base is fast walk.
- In the slow band the fighter brakes harder: its deceleration is multiplied by
  `fCombatApproachTargetSlowdownDecelerationMult`, 10, not by `fCombatPathingDecelerationMult`,
  2.

## Sprint

A fighter sprints when all of these hold:

- the band allows a sprint;
- the INI setting `bCombatPathSprinting` in the `Combat` section is on, which is the default;
- the distance is above the fighter's reach plus a stop range.

The stop range is `fCombatApproachTargetSprintStopRange`, 768 units. For a target that moves
away from the fighter it is `fCombatApproachTargetSprintStopMovingRange`, 0.

No step of the rule tells a creature from an NPC. So a skeever follows it with the walk and
run speeds of its own race. Whether a race without sprint data can sprint was not checked.

## In OpenSky

A fighter runs toward a target beyond its walk radius and walks inside it. The walk radius is
the outer radius of step 2 with x taken from the Offensive Mult alone, at most 512 units.

- [WARNING] The radii do not follow steps 1 to 4, and the three speed bands, the sprint, and
  the harder braking are not built. So a skeever 300 units from the player walks to it, where
  the game's skeever runs.
