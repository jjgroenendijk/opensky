---
type: Engine
title: Attack data
description: How an actor's ATKD attack list is built from its race and template, and what each
  attack value changes in a swing, its stamina cost, its stagger, and the AI's choice.
tags: [engine, combat, melee, actors, gmst]
---

# Attack data

Each `ATKD` + `ATKE` pair on a `RACE` or an `NPC_` is one attack. `ATKE` is the animation event
that starts it, and `ATKD` holds 44 bytes of values. The event name is the key of the attack
list.

## Which list an actor uses

```mermaid
flowchart TD
    A["NPC_ record"] --> B{"Own ATKD or ATKR?"}
    B -- yes --> C["Own list, merged with the ATKR race's list"]
    B -- no --> D["No own list"]
    C --> E{"Template flag 0x800, Attack Data?"}
    D --> E
    E -- "yes, and the template's list is not just its race's" --> F["Template's list"]
    E -- otherwise --> G{"Has a list?"}
    F --> G
    G -- yes --> H["Use it"]
    G -- no --> I["Use the race's list"]
```

- The `ATKR` merge: an own attack whose event the attack race lacks is removed. When the two
  lists still differ in length, each attack-race entry the own list lacks is added. An added
  entry is shared with the attack race, not copied. When both have an event, the own entry wins.
  An NPC with only `ATKR` gets the whole attack-race list.
- The race fallback checks whether a list exists, not whether it is empty. An NPC whose own list
  is empty keeps the empty list.
- With the Traits template flag (0x1), the race comes from the template. An NPC that used its
  old race's list moves to the new race's list.
- A race change at run time moves a list that came from the old race to the new race's list. A
  new race with `DATA` flag 0x4000000 or 0x8000000 skips this step.
- At run time the game reads the list of the reference's base `NPC_`.

## Values

| Value | Default | What it changes |
| --- | --- | --- |
| Damage multiplier | 1 | The skill-scaled weapon damage ([melee damage](/engine/melee-damage.md#skill-sneak-attacks-and-armour)) |
| Attack chance | 1 | The attack's weight in the AI's random pick |
| Spell | none | Cast on the target with the hit |
| Flags | 0 | See below |
| Attack angle | 0 | Degrees added to the attacker's heading before the hit cone test |
| Strike angle | `fCombatHitConeAngle` (35) | Half-angle of the hit cone, in degrees |
| Stagger | 0 | A factor of the stagger the hit gives |
| Attack type | none | A keyword a condition function compares with the attack under way |
| Knockdown | 0 | Above 0, the hit pushes the target away with this force |
| Recovery time | 0 | Seconds before the AI picks this attack again |
| Stamina multiplier | 1 | The stamina cost of the attack |

Flags:

| Bit | Effect |
| --- | --- |
| `0x1` | Ignore weapon. No reader is known |
| `0x2` | Bash: pays the bash stamina cost. The general attack pick leaves it out |
| `0x4` | Power attack: pays the power attack cost, marks the hit as a power attack, applies the power attack damage entry point, and is the only kind picked in power-only mode |
| `0x8` | Left hand: the general attack pick leaves it out |
| `0x10` | Rotating: the hit test does not add the attack angle |
| `0x80000000` | Override data. No reader is known |

## The hit cone

A target is inside an attack's cone when
`|heading + attackAngle - directionToTarget| <= strikeAngle * mult`, with the difference wrapped
to plus or minus 180 degrees.

| Use | `mult` |
| --- | --- |
| The hit test | 1 |
| The AI's attack pick | `fCombatAttackStrikeAngleMult` (0.67) |
| An attack while moving | `fCombatAttackMovingStrikeAngleMult` (1.5) |
| A defender deciding to block | `fCombatBlockAttackStrikeAngleMult` (1.25) |
| A dead target | The use's value times `fCombatDeadActorHitConeMult` (2) |

Example: a 35 degree strike angle hits a living target up to 35 degrees off the heading. The AI
starts that attack only within `35 * 0.67`, about 23 degrees.

## The AI's pick

The AI picks one attack at random, weighted by attack chance. An attack with a weight of 0 or less
is never picked. The weight changes with the target, using the attacker's
[combat style](/formats/combat-style.md) `CSME` values:

- a staggered target: times power attack staggered for a power attack, else times attack
  staggered;
- a blocking target, with the attacker inside the target's 35 degree block cone: a power attack
  times power attack blocking.

An attack is skipped while its recovery time has not passed since its last use. An attack that
costs stamina is skipped while the attacker's Stamina is 0 or less.

## Stamina

| Attack | Cost |
| --- | --- |
| Normal | 0 |
| Bash | `fStaminaBashBase` (35) times the stamina multiplier |
| Power bash | `fStaminaPowerBashBase` (55) times the stamina multiplier |
| Power attack | `(weight * fStaminaAttackWeaponMult + fStaminaAttackWeaponBase) * fPowerAttackStaminaPenalty`, then the power attack stamina entry point, then times the stamina multiplier |

`weight` is the weapon's weight, or 1 unarmed. The entry point uses the right-hand weapon.
Example: a power attack with a 10-weight sword costs `(10 * 1 + 20) * 2 = 60` before perks.

## Stagger

```text
stagger = (attacker AV 9 * fStaggerAttackMult + fStaggerAttackBase)
          / (target Mass * fStaggerMassMult + fStaggerMassBase)
          * conditions * weapon * ATKD stagger
```

`fStaggerAttackMult` is 0.01, `fStaggerAttackBase` 0.5, `fStaggerMassMult` 1, and
`fStaggerMassBase` 0. Mass is actor value 36. The conditions multiply when they hold: a
recoiling target by `fStaggerRecoilingMult` (1.5), a running target by `fStaggerRunningMult`
(1.5), and a blocking target by `fStaggerBlockingMult` (0 in `Skyrim.esm`). The weapon factor is
`fStaggerShieldMult` (1) with a shield, `fStagger2WeapMult` (0.5) for a two-handed weapon, bow, or
crossbow, and `fStagger1WeapMult` (0.2) otherwise. The result is at least `fStaggerMin` (0).

## Knockdown

A knockdown above 0 pushes the target away from the attacker with that force, the same push an
explosion's knockdown uses ([explosions](/engine/explosions.md)).
