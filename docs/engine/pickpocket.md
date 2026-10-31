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

The menu shows the chance for the selected item, "To steal" on the target's side and "To place"
on the player's.

## Perks

| Entry point | Index | Vanilla perk | Effect |
| --- | --- | --- | --- |
| Mod Pickpocket Chance | 61 | `Pickpocket00` to `Pickpocket80`, `Cutpurse`, `ExtraPockets` | Scales the chance, with the item bound as the condition subject |
| Can Pickpocket Equipped Item | 56 | `Misdirection`, `PerfectTouch` | Allows taking an equipped item, under item conditions |
| Should Apply Placed Item | 84 | `Poisoned` | A poison placed in the target's pockets is applied to them instead of left there |

## Placing items

A player item can be placed into the target's pockets. The chance uses the same formula. A
success moves the item; a failure is caught like a failed take. With Poisoned, a placed poison
lands on the target as if it hit them, and the poison is used up.

## Success and failure

A roll from 0 to 100 below the chance succeeds:

- The item moves to the player and is marked stolen.
- Pickpocket gains skill use equal to the item's value times the count, or the coins taken
  ([skill advancement](/engine/skill-advancement.md)).
- The story manager hears an add-item event with the pickpocket method.
- The misc stat "Items Pickpocketed" goes up by one. "Pockets Picked" goes up by one at the first
  success after the pockets open. The wiki lists both stats without saying what they count, so this
  split is OpenSky's reading.

A failed roll moves nothing. The target noticed, so the pockets close, the HUD shows
`sPickpocketFail` ("You've been caught pickpocketing."), and the
[crime](/engine/crime.md) system charges a pickpocket crime. The target is the witness. It
costs the faction's flat `CRVA` pickpocket price (25 in vanilla), not a share of the item's value.

The target then refuses another try for two game days. Activating it while sneaking shows its
name and `sNoPickPocketAgain` (" has already caught you.") instead of opening the pockets.
The day of the catch is a script-state value on the target, so a save keeps it. Beside it the
target keeps the crime faction the catch was charged to.

UESP gives two ways to end the refusal early:

- A guard comes for the crime and the player makes it "go away quietly": a bribe, a Thane's status,
  or paying as "part of the Guild". This forgets every catch charged to that guard's faction (see
  [guard response](/engine/guard-response.md)). A paid fine or a jail sentence only unlinks the
  catches, so a later bribe for another crime does not forget them.
- "Casting Harmony will cause all affected targets to 'forget' if they have been pickpocketed
  recently. This does not work with other Pacify spells." No field marks Harmony. In the data,
  Harmony is the vanilla calm effect delivered from self over an area, and Pacify and Calm are
  aimed. So OpenSky forgets the catch for a calm effect delivered from self with an area, on any
  actor but the caster.

## Where OpenSky differs

- The CK settings list `fPickpocketSkillUsesCurve` (0.8). No source explains it, so OpenSky does not
  apply it.
- The target does not turn hostile or start a dialogue after a failure. The crime is charged, and
  the guards react as for any other bounty.
