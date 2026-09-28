---
type: Subsystem
title: Character leveling
description: The level curve and its settings, where level, experience, and perk points are
  saved, what an attribute pick does, the live player level, and the rules for spending a
  perk point.
tags: [engine, progression, leveling, perks, actor-values, conditions, papyrus]
---

# Character leveling

Skills rise by use ([skill advancement](/engine/skill-advancement.md)). Each skill point adds
character experience. Enough experience raises the character level, which gives one attribute
pick and one perk point. This page covers that second half.

The record side is [perks](/formats/perks.md) for `PERK`, and
[actor value information](/formats/actor-value-information.md) for the `AVIF` perk tree that
every spend is checked against.

## The curve

From UESP [Skyrim:Leveling](https://en.uesp.net/wiki/Skyrim:Leveling):

| Question | Formula |
| --- | --- |
| What does the next level cost? | `fXPLevelUpBase + level * fXPLevelUpMult` |
| What has a character earned in total by level N? | The sum of every cost below N |

The wiki also gives the curve with the vanilla numbers filled in: `(Current level + 3) * 25` for
one level, `12.5 * N^2 + 62.5 * N - 75` for the total, and the inverse
`FLOOR(-2.5 + SQRT(8 * XP + 1225) / 10)`. These are the setting formulas with 75 and 25. OpenSky
computes from the settings, and the tests check the result against these closed forms up to
level 60. So a load order that changes the settings moves the whole curve.

The wiki states two end points: 100 experience to leave level 1, and 1300 to leave level 49.

Leftover experience carries over, and one award can cross several levels. The wiki:
"Over-training will still grant you level ups even if the progress bar is stuck at 100%".

## Settings

Read from the local install with `make run-cli ARGS="gmst list --prefix fxp"` and the matching
prefixes:

| Setting | Value | Meaning |
| --- | --- | --- |
| `fXPLevelUpBase` | 75 | The fixed part of the level cost |
| `fXPLevelUpMult` | 25 | What each level already held adds to the cost |
| `iAVDhmsLevelUp` | 10 | Points one attribute pick adds |
| `fLevelUpCarryWeightMod` | 5 | Carry weight a stamina pick adds |

`Skyrim.esm` sets all four, and the fallback values agree with it. They are still read, not
assumed.

[Actor values](/engine/actor-values.md) also reads `iAVDhmsLevelUp`, as the points an NPC's
class spreads over the three attributes.

## Where progress is saved

A player progress component holds the level, the experience toward the next level, the unspent
perk points, the owed attribute picks, the picks already made, and a count of skill points
gained. It is saved in the `PLVL` chunk. A session that never leveled writes no chunk
([save chunks](/formats/opensky-save.md#chunks)).

Skill progress is not here. It lives in the `Skill Advance` actor values, because the vanilla
table already has one slot per skill for exactly that. Nothing in that table holds a character
level, so the level needed its own component.

The effect of an attribute pick is not here either. The ten points are a base offset on the
chosen actor value, saved in `AVOV`. Two homes for the same points could disagree. The list of
picks only records what happened.

## When the level changes

Vanilla banks levels and changes the number only when the player opens the skills menu: "when
you do choose to level, you will be raised to the highest level earned through skill
progression". `Actor.GetLevel` follows the menu: "if you have leveled up but have yet to go into
the perk menu screen, this will still return your level seen in the HUD"
([GetLevel - Actor](https://www.creationkit.com/index.php?title=GetLevel_-_Actor)).

OpenSky differs on purpose. It raises the level and gives the perk point and the owed pick as
soon as they are earned. Only the choice waits. There is no level-up menu yet. A level that was
earned but stays hidden from `GetLevel`, from `PC Level Mult` scaling, and from every condition
would be a worse answer than one that comes slightly early. Owed picks still queue as in
vanilla, so a later menu can still show "if you gained 4 levels you will be prompted to make 4
choices in succession".

## The attribute pick

One pick uses one owed choice and does three things, in this order:

1. It adds `iAVDhmsLevelUp` points to the chosen value's base offset. So it adds on top of the
   record values and survives when the value is derived again.
2. For stamina only, it adds `fLevelUpCarryWeightMod` to carry weight. UESP makes this a rule of
   the pick, not of stamina: "Adding to your base stamina when you level up increases your carry
   weight by 5. ... Temporary changes to your stamina (such as damage, drain, or fortify) do not
   affect your carry weight" ([Skyrim:Stamina](https://en.uesp.net/wiki/Skyrim:Stamina)).
3. It fills health, magicka, and stamina: "When you accept the new level ... your character is
   fully healed, regaining any Health, Magicka, and Stamina that was depleted."

A pick with none owed is refused.

## The live player level

The actor value resolvers are built once per load order. They need the player's level, because
an NPC with `PC Level Mult` scales from it. Storing the level on them would mean rebuilding them
at each level-up. So they share one small level source. Leveling writes into it, and every derived
value uses the new level on its next read. With no progression, the level is 1.

Conditions and Papyrus read the level through the same derived baseline as every other actor
value.

## Spending a perk point

One validator enforces the tree, the rank order, and the skill requirement. The perk runtime
stays a plain grant layer, because quests, scripts, and races also give perks that no tree
limits ([perks](/engine/perks.md)).

| Rule | Refusal | Source |
| --- | --- | --- |
| The record resolves | `unresolvedPerk` | A perk that does not resolve could never be evaluated |
| The perk is playable | `notPlayable` | `PERK` `DATA`. A quest perk is not bought with a point |
| Not owned yet | `alreadyOwned` | A second purchase buys nothing |
| In a tree | `notInPerkTree` | The `AVIF` perk tree nodes |
| Rank order | `previousRankMissing` | The record whose `NNAM` names this one must be owned |
| Tree parent | `parentMissing` | A box that `FNAM` marks as needing a parent needs an owned parent |
| Record conditions | `unmetCondition` | The perk's own `CTDA` list, which holds the skill requirement |

A node's `CNAM` array is "Line to Index". It points from parent to child. So a box's parents are
the boxes whose lines reach it. `AVOneHanded` on the local install, from
`make run-cli ARGS="record AVOneHanded"`:

```text
#0  perk NULL,           lines to [7]
#7  perk Armsman00,      lines to [4, 3, 5, 1, 6]
#1  perk FightingStance, lines to [2, 11]
```

The entry node has no perk. So the first real box of every tree has a parent that costs nothing.
A higher rank is not its own box: `Armsman20` to `Armsman80` are not in the tree. The box of a
rank is found by following `NNAM` back to the start of the chain.

The rank, parent, and condition rules overlap on vanilla data, on purpose. Vanilla writes the
parent both as a `HasPerk` condition and as a tree line, but neither is certain. `Armsman00` has
no conditions. `Armsman20` has both `GetBaseActorValue One-Handed >= 20` and
`HasPerk Armsman00 == 1`. Checking only one rule would let a tree written another way be climbed
out of order.

A condition OpenSky cannot evaluate is a refusal, not a pass. An unknown function is false with a
reason, so a perk that depends on it cannot be bought, instead of being free.

## Conditions

Indices are the stored numbers. The Creation Kit adds 4096.

| Index | Function | Returns |
| --- | --- | --- |
| 80 | `GetLevel` | The actor's level: derived for an NPC, the character level for the player |
| 277 | `GetBaseActorValue` | The base value, never with modifiers |

`GetBaseActorValue` reads the base on purpose. A fortified skill is not a trained one, so a
potion cannot buy a perk requirement ([condition evaluation](/engine/conditions.md)).

## Papyrus

| Native | Source | Effect |
| --- | --- | --- |
| `Actor.GetLevel()` | Vanilla | The actor's level, through the same baseline as every actor value |
| `Game.GetPerkPoints()` | SKSE | The player's unspent perk points |
| `Game.ModPerkPoints(int)` | SKSE | Adds or removes points, clamped to 0 to 255 |

The two perk point functions are not vanilla Papyrus. The Creation Kit wiki lists them as SKSE
additions to the `Game` script ([Papyrus VM](/engine/papyrus-vm.md)). `Game.SetPerkPoints` is not
implemented. A session with no leveling refuses both, instead of answering 0, which would look
like a player who spent everything.

## Not done yet

- The in-game level-up and perk tree menus, and legendary skills.
- The Dragonborn perk reset, which spends a dragon soul to clear one tree.
- Experience multipliers: Rested, Well Rested, Lover's Comfort, and the Guardian Stones.

## Controls

World > Progression has three sections. Each control makes the same call a game session makes.

| Section | What it does |
| --- | --- |
| Character | Level, experience, unspent points, owed picks. Award experience, make a pick, add or remove perk points |
| Skills | The 18 skills with value, trained base, experience, and next threshold. Grant use (`AdvanceSkill`) or a whole point (`IncrementSkill`) |
| Perk Tree | The chosen skill's `AVIF` boxes with lines, rank chain, and refusal reason, the chosen box's `PERK` record, and the real spend beside two developer grants |

Choices the panel makes:

- It is its own destination, not part of World > Combat & Physics. Combat asks what an actor is
  worth in this fight. Progression asks what the player has become.
- It has no reset. Every control changes world state on purpose. A reset would take levels away
  from a character, not restore a setting.
- It shows a list and an inspector, not a drawn tree. The tree's meaning is its lines, rank
  chains, and refusal rules, which read well as text.
