---
type: File Format
title: Combat style records
description: Skyrim SE CSTY combat styles and their float blocks that may stop early.
tags: [format, plugin, combat]
---

# Combat style records

`CSTY` holds the weights an actor's combat AI uses. An NPC links one through `NPC_ ZNAM`.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## Fields

Each block is a run of floats that may stop early; xEdit marks every member optional. The
install has `CSGD` at 8, 32 and 40 bytes, `CSME` at 28 and 32, `CSCR` at 8 and 16, and
`CSFL` at 4, 12 and 32. A block that stops early keeps the default for each float it lacks. A
new style starts as a copy of the game's default combat style, when one is set.

| Field | Members, in order |
| --- | --- |
| `CSGD` | Offensive, defensive, group offensive multipliers; equipment score multipliers for melee, magic, ranged, shout, unarmed, staff; avoid threat chance |
| `CSMD` | 8 bytes not named by xEdit. The game skips it at load |
| `CSME` | Attack staggered, power attack staggered, power attack blocking, bash, bash recoil, bash attack, bash power attack, special attack multipliers |
| `CSCR` | Circle multiplier, fallback multiplier, flank distance, stalk time |
| `CSLR` | Strafe multiplier |
| `CSFL` | Hover chance, dive bomb chance, ground attack chance, hover time, ground attack time, perch attack chance, perch attack time, flying attack chance |
| `DATA` | uint32 flags: 0x01 dueling, 0x02 flanking, 0x04 allow dual wielding |

Header flag 0x80000 is an older allow-dual-wielding switch.

## Defaults

| Field | Default |
| --- | --- |
| `CSGD` | Offensive 0.5, defensive 0.5, group offensive 1, the six equipment multipliers 1, avoid threat 0.2 |
| `CSME` | The first seven values 1, special attack 0.1 |
| `CSCR` | All four values 0.2 |
| `CSLR` | 0.2 |
| `CSFL` | 0.5, 1, 0.5, 0.5, 0.5, 0.5, 0.5, 0.75, in the member order above |
| `DATA` | 1: dueling only |

## What the values change

Most values pick a point between two game settings. In this section,
`lerp(v, Min, Max) = Min + (Max - Min) * v`. Example: a circle multiplier of 0.2 gives a circle
chance of `lerp(0.2, 0, 0.75) = 0.15`.

| Value | Formula |
| --- | --- |
| Fallback chance | `lerp(fallback, fCombatFallbackChanceMin 0, fCombatFallbackChanceMax 0.5)` |
| Fallback distance | `lerp(fallback, fCombatFallbackDistanceMin 96, fCombatFallbackDistanceMax 256)` units |
| Fallback wait | `lerp(fallback, fCombatFallbackWaitTimeMin 0.75, fCombatFallbackWaitTimeMax 1.5)` s |
| Circle chance | `lerp(circle, fCombatCircleChanceMin 0, fCombatCircleChanceMax 0.75)` |
| Distant circle chance | `lerp(circle, fCombatCircleDistantChanceMin 0.25, fCombatCircleDistantChanceMax 0.75)` |
| Circle angle | `lerp(circle, fCombatCircleAngleMin 30, fCombatCircleAngleMax 90)` degrees |
| Flank distance | `lerp(flank, fCombatFlankingDistanceMin 0, fCombatFlankingDistanceMax 1024)` units |
| Stalk time | `lerp(stalk, fCombatFlankingStalkTimeMin 0.01, fCombatFlankingStalkTimeMax 10)` s |
| Strafe chance | `lerp(strafe, fCombatStrafeChanceMin 0, fCombatStrafeChanceMax 0.75)` |
| Special attack chance | `lerp(special, fCombatSpecialAttackChanceMin 0, fCombatSpecialAttackChanceMax 1)` |
| Block chance | `lerp(defensive, fCombatBlockChanceMin 0, fCombatBlockChanceMax 1)`, times `fCombatBlockChanceWeaponMult` 0.25 without a shield |
| Block attack chance | `lerp(defensive, 0, 1)` |
| Hover, dive bomb, ground attack, perch, flying attack chances | `lerp(v, 0, 1)` |
| Hover time | `lerp(hover time, fCombatHoverTimeMin 5.5, fCombatHoverTimeMax 15)` s |
| Ground attack time | `lerp(ground attack time, 8, 17)` s |
| Perch time | `lerp(perch time, 4, 15)` s |

The circle angle is then drawn at random between `fCombatCircleAngleMin` and the lerped value.
Against the player it is multiplied by `fCombatCircleAnglePlayerMult` (0.75). It is never less
than the angle, in degrees, of `radius * fCombatCircleMinDistanceRadiusMult (3) / distance`.

### Close-range movement

The AI chooses its movement near a target by where the target is:

| Where | Choices, by weight |
| --- | --- |
| In range | Back off (fixed weight 0.25); circle or fall back, weighted by the circle and fallback chances above; stay |
| Out of position | Reposition, surround, or distant circle, weighted by the distant circle chance |
| Out of range | Advance; fall back to a ranged weapon, only when the actor's range is beyond `fCombatRangedDistance` (1024) |

Out of range means the distance predicted half a second ahead is above the actor's reach. The
fallback distance is at least the actor's radius times a fixed factor. A strafe goes a random
distance between 96 units and the strafe maximum, and at least three times the actor's radius.

Example: circle 0.2 and fallback 0.2. In range, circle weighs 0.15 and fallback 0.1 against the
backoff's 0.25.

### Attack and bash chances

The attack chance starts at `lerp(offensive, fCombatAttackChanceMin 0.05,
fCombatAttackChanceMax 1)`. Then:

- a staggered target multiplies it by the larger of the attack staggered and power attack
  staggered values;
- a target in mid-swing multiplies it by `fCombatAttackChanceBlockingSwingMult` (0);
- a target that is not attacking multiplies it by a value that falls from
  `fCombatAttackChanceBlockingMultMax` (0.67) at defensive 0 to
  `fCombatAttackChanceBlockingMultMin` (0.2) at defensive 1;
- the time since the actor's last attack raises it, from 1 times to
  `fCombatAttackChanceLastAttackBonus` (1.5) times over `fCombatAttackChanceLastAttackBonusTime`
  (5 s).

The bash chance is `lerp(defensive, fCombatBashChanceMin 0.025, fCombatBashChanceMax 0.2)` and
the offensive bash chance `lerp(offensive, fCombatOffensiveBashChanceMin 0,
fCombatOffensiveBashChanceMax 0.05)`. Both are multiplied by the bash value and by one more
factor: bash recoil for a recoiling target, bash power attack for a power-attacking target,
bash attack for an attacking target, or `fCombatBashTargetBlockingMult` (0) for a target that
blocks toward the attacker within the 35 degree hit cone.

The attack staggered, power attack staggered, and power attack blocking values also weight the
choice between attacks ([attack data](/engine/attack-data.md#the-ais-pick)).

With flanking, the flank distance is added to a radius of the target to give the distance the
actor flanks at. The stalk time starts a stalk timer. A stalk reaches 256 units, and the actor
counts as near the flank point within 384.

`DATA` 0x04 allows dual wielding for a race with `DATA` flag 0x40000000, which allows a
left-hand item. `DATA` 0x02 lets the actor use flanking movement; without it the actor never
flanks. No reader of the dueling, charging, or retarget bits is known.

## The general block

`CSGD` drives most combat choices through two values:

- The offensive value `O` is the offensive multiplier. When the group offensive multiplier is
  below 1 and `n` actors, more than one, fight the player, an attacker of the player uses
  `O = offensive * max(groupOffensive^(n - 1), fCombatGroupOffensiveMultMin (0.1))`.
- The defensive value `Df` is the defensive multiplier.

| Uses `O` | Uses `Df` |
| --- | --- |
| Attack chance, offensive bash chance | Block chance, block attack chance, bash chance |
| Ranged attack chance: `lerp(O, fCombatRangedAttackChanceMin, Max)` | Block start distance: `lerp(Df, fCombatBlockStartDistanceMin 32, Max 192)`, and the same for the stop distance |
| Immediate offensive spell chance: `lerp(O, 0.05, 0.75)` from the `fCombatCastImmediateOffensiveMagicChance` pair | Block time: three-point lerp of `fCombatBlockTimeMin`, `Mid`, `Max` at `2 * Df - 1` |
| Immediate spell hold time and concentration spell chance, cast and wait times, from their settings | Cover search distance: `lerp(Df, fCombatCoverSearchDistanceMin 1536, Max 3072)` |
| Orbit time: random between `fCombatOrbitTimeMin` (3) and `lerp(O, fCombatOrbitTimeMax 12, Min)` | The health and magicka percents to restore at |

The advance radii use `Df - O`: three-point lerps of `fCombatAdvanceInnerRadiusMin`, `Mid`,
`Max` and of `fCombatAdvanceOuterRadiusMin` 128, `Mid` 256, `Max` 512. A staggered target first
multiplies `Df` by `fCombatAdvanceRadiusStaggerMult`. Cover wait time also uses `Df - O`, and
cover attack time `O - Df`. A three-point lerp at `x` is `mid + (max - mid) * x` above 0, else
`min + (mid - min) * (x + 1)`. Example: `Df` 0.5 and `O` 0.5 give an outer radius of 256.

The equipment multipliers scale the score of each choice: a weapon by melee, ranged (bow and
crossbow), or unarmed; a staff item by melee; a spell by magic, a shout by shout, and a staff's
magic by staff. Every score doubles (`fCombatInventoryRangedScoreMult`, 2) when the target is
further than `fCombatRangedDistance` (1024).

Avoid threat chance is the dodge chance: `lerp(v, fCombatDodgeChanceMin 0, fCombatDodgeChanceMax
1)`. The actor rolls it when it sees a threat, only on the navmesh and not in flight.

## Actors

An actor's combat style is its `NPC_` `ZNAM`. Through a template, it follows the "Use AI
Data" template flag (0x0010). xEdit ties `ZNAM` to no template flag. The Creation Kit
shows Combat Style on the AI Data tab of the actor window, so OpenSky uses that flag. This
choice is not confirmed against the running game.

In `Skyrim.esm`, 3,787 of the 5,118 `NPC_` records reach a combat style, directly or
through their templates.
