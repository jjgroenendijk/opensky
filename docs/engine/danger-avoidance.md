---
type: Subsystem
title: Danger avoidance
description: What the game counts as a danger to an actor - explosions, projectiles, and
  exploding objects - how a fighter scores and dodges them, and how onlookers keep their distance.
tags: [engine, ai, combat, explosions, projectiles]
---

# Danger avoidance

The game keeps one list of threats. A threat is something that will explode near an actor soon. A
fighter checks the list and sidesteps when the danger is large. A civilian who watches a fight
keeps a distance from it.

OpenSky does not build this yet. Its AI does not move away from explosions or projectiles.

All values below are the ones that apply in play. Where `Skyrim.esm` overrides the program's
built-in default, the page gives the plugin value.

## What counts as a threat

The game assumes an explosion deals D × (1 − (d / R)²) at distance d, where D is its damage and R
its radius. So the distance inside which it deals at least T is its effective radius,
R × √(1 − T / D), or 0 when T is larger than D.

| Source | It is a threat when |
| --- | --- |
| A projectile or explosion on its way | Its explosion deals at least 5, and its effective radius at 5 damage is at least 30 units |
| A destructible object, such as a barrel or a trap | One of its destruction stages explodes with a radius of at least 100 and damage of at least 25 |

Example: an explosion with damage 20 and radius 100 has an effective radius at 5 damage of
100 × √(1 − 5/20) ≈ 87 units, so it is a threat.

When a dangerous destructible object takes damage:

```mermaid
flowchart TD
    H[Destructible object takes damage] --> A{Next explosive stage comes<br/>from timed self-damage within 5 s?}
    A -- yes --> R1[Add a threat until that time]
    A -- no --> B{Health left before<br/>that stage below 30?}
    B -- yes --> R2[Add a threat for 3 s]
    B -- no --> R3[Remove its threat]
```

## How a fighter scores threats

For one actor and a look-ahead time, a threat counts when:

- the actor is ahead of it: the vector from the threat to the actor points along the threat's
  direction of travel;
- the space the threat sweeps through in that time overlaps the actor's bounds;
- most likely, the threat does not come from the actor's own side.

The score = the sum of the counted threats' damage / the actor's current `Health`.

## Dodging

The combat behaviour tree has a "Dodge Threat" step with a "Check Should Dodge" condition.

```mermaid
stateDiagram-v2
    [*] --> Watching
    Watching --> Sampling: every 0.125 to 0.25 s
    Sampling --> Watching: score of threats in the next 2 s is acceptable
    Sampling --> Dodging: score too high / pick a sidestep with a safety margin
    Dodging --> Watching: sidestep done
```

The dodge step works like this:

1. The reaction time is `fCombatDodgeReactionTime` (0.15 seconds) for a standing actor and
   `fCombatDodgeMovingReactionTime` (0.25 seconds) for a moving one.
2. A moving actor first checks its current path for threats over the next
   `fCombatDodgeAnticipateThreatTime` (2 seconds). A clear path is kept, and the step ends.
3. The reference score is the score that the "Check Should Dodge" condition found. The step goes
   on only when the score at the actor's own position within the reaction time is below it.
4. The escape point comes from the direction the most significant threat travels in, on the
   ground plane. The actor leaves to the side of that line it already stands on. When it is less
   than half its own radius from the line, the side is random.
5. Each side has one point, at a right angle to the line. Its distance from the actor is the
   threat's radius, less the actor's offset from the line on its own side or plus it on the other
   side, plus the actor's radius, plus `fCombatDodgeBufferDistance` (64 units).
6. The preferred side is tried first, then the other. A point is rejected when:
   - the navmesh does not reach it;
   - the score along the move, with time = distance / the actor's move speed, is at least
     `fCombatDodgeAcceptableThreatScoreMult` (0.5) times the reference score;
   - the move, when shorter than 2 seconds, followed by standing there until 2 seconds have
     passed, collects any score at all. That total must be exactly 0.
7. The move uses `fCombatDodgeAccelerationMult` and `fCombatDodgeDecelerationMult`, 10 each.

Most likely, the chance to dodge is `fCombatDodgeChanceMin` (0) + (`fCombatDodgeChanceMax` (1)
− the minimum) × the combat style's Avoid Threat Chance (`CSTY`). With these values it is the
style's own value. `fCombatAvoidThreatsChance` is never read. Several other threat settings, such
as the time to avoid a rune, are never read either.

## Onlookers

A civilian who sees a fight remembers the threat source for 5 seconds, and keeps away from it by a
radius set by the source's weapon. A higher level replaces a lower one, never the reverse.

| Source weapon | Radius | Level |
| --- | --- | --- |
| Melee | 512 | 1 |
| Ranged | 256 | 2 |
| Explosive | 512 | 3 |
| Mine | 256 | 3 |
| None | unchanged | unchanged |

What the onlooker then does is in
[random conversations](/engine/random-conversations.md#what-a-watcher-does): it head-tracks the
fight, says the ObserveCombat line, and steps away.
