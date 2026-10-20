---
type: Engine
title: Pickpocketing
description: How OpenSky rolls a pickpocket take, what a success and a failure do, and where the numbers come from.
tags: [inventory, crime, skills]
---

# Pickpocketing

Activating a living actor while sneaking opens the actor's pockets in the container menu,
instead of starting a conversation. Each item taken from the pockets is one roll. Take All is
refused, because each take needs its own roll.

Sources: UESP [Skyrim:Pickpocket](https://en.uesp.net/wiki/Skyrim:Pickpocket) for the rule, and
the Creation Kit wiki [Category:Settings](https://ck.uesp.net/wiki/Category:Settings) for the
default game settings. The local install's game settings were checked against these defaults.

## The chance

The chance is a percentage. Each `fPickPocket*` game setting is read from the load order, with the
default below when a plugin does not set it.

| Term | Formula | Defaults |
| --- | --- | --- |
| Thief | (`ActorSkillBase` + thief's Pickpocket) times `ActorSkillMult` | 20, 1 |
| Target | (`TargetSkillBase` + target's Pickpocket) times `TargetSkillMult` | 20, -0.25 |
| Gold | `AmountBase` + coins taken times `AmountMult` | 0, -0.1 |
| Weight | `WeightBase` + weight taken times `WeightMult` | 0, -4 |
| Seen | minus `fPickPocketDetected` when the target has detected the thief | 25 |

The sum goes through the Mod Pickpocket Chance perk entry point, then is clamped between
`fPickPocketMinChance` (0) and `fPickPocketMaxChance` (90). For example, a thief with Pickpocket 15
who takes a 1-weight item from a target with Pickpocket 15 that has not seen them has
35 - 8.75 - 4 = 22.25 percent.

An equipped item can only be taken with a perk that passes the Can Pickpocket Equipped Item entry
point.

## Success and failure

A roll from 0 to 100 below the chance succeeds:

- The item moves to the player and is marked stolen.
- Pickpocket gains skill use equal to the item's value times the count, or the coins taken
  ([skill advancement](/engine/skill-advancement.md)).
- The story manager hears an add-item event with the pickpocket method.
- The misc stat "Items Pickpocketed" goes up by one. "Pockets Picked" goes up by one at the first
  success after the pockets open. The wiki lists both stats without saying what they count, so this
  split is OpenSky's reading.

A failed roll moves nothing. The target noticed, so the pockets close and the
[crime](/engine/crime.md) system charges a theft. The target is the witness. A pickpocket theft
costs the faction's flat `CRVA` pickpocket price (25 in vanilla), not a share of the item's value.

## Where OpenSky differs

- The CK settings list `fPickpocketSkillUsesCurve` (0.8). No source explains it, so OpenSky does not
  apply it.
- The target does not turn hostile or start a dialogue after a failure. The crime is charged, and
  the guards react as for any other bounty.
