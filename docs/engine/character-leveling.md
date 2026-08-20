---
type: Subsystem
title: Character leveling
description: The character level curve and the two settings behind it, where the level, the
  banked experience and the perk-point pool persist, what an attribute pick does and where
  the ten points live, and the five rules a perk-point spend has to satisfy.
tags: [engine, progression, leveling, perks, actor-values, conditions, papyrus]
timestamp: 2026-08-20T00:00:00Z
---

# Character leveling

Skills go up by use ([skill advancement](/engine/skill-advancement.md)); each skill point
banks character experience; enough of it raises the character's own level, which hands out
an attribute pick and a perk point. This page is that second half — the curve, where the
progress persists, what a pick does to an actor value, and what a point may be spent on.

The record side is [perks](/formats/perks.md) for the PERK record and
[actor value information](/formats/actor-value-information.md) for the AVIF perk-tree node
run every spend is validated against.

## Contents

- The curve
- Where the numbers come from
- Where progress persists
- When the level moves, and the one deviation
- The attribute pick
- The live player level
- Spending a perk point
- The condition surface
- The Papyrus surface
- What is deliberately absent

## The curve

One formula, from [Skyrim:Leveling](https://en.uesp.net/wiki/Skyrim:Leveling), living as
pure functions in `CharacterLeveling`:

| Question | Formula |
| --- | --- |
| What does the next character level cost? | `fXPLevelUpBase + level * fXPLevelUpMult` |
| What has one character earned in total by level N? | the sum of every threshold below N |

The wiki prints the same curve twice more, in vanilla numbers: `(Current level + 3) * 25`
for one threshold, and `12.5 * N^2 + 62.5 * N - 75` for the running total, with the inverse
`FLOOR(-2.5 + SQRT(8 * XP + 1225) / 10)`. All three are the settings spelling with 75 and 25
substituted in, so OpenSky computes from the settings and *checks* against those constants:
`CharacterLevelingTests` asserts the closed form against the summed one at every level to
60, which is what makes a retuned load order move the whole curve instead of half of it.

The two ends the wiki states outright are pinned directly: 100 experience to leave level 1,
1300 to leave level 49.

The remainder carries. Experience past a threshold stays banked toward the next level and
one award may cross several thresholds, which is the rule behind the wiki's own
over-training note: "Over-training will still grant you level ups even if the progress bar
is stuck at 100%".

## Where the numbers come from

Four game settings, read off this machine's install on 2026-08-20 with
`make run-cli ARGS="gmst list --prefix fxp"` and the matching prefixes, and pinned by
`CharacterLevelingRealDataTests`:

| Setting | Value | What it does |
| --- | --- | --- |
| `fXPLevelUpBase` | 75 | Constant term of the level-up threshold |
| `fXPLevelUpMult` | 25 | What each level already held adds to it |
| `iAVDhmsLevelUp` | 10 | Points one attribute pick adds |
| `fLevelUpCarryWeightMod` | 5 | Carry weight a stamina pick adds |

All four are authored by `Skyrim.esm`, so the documented fallbacks in
`CharacterLevelSettings.documentedDefaults` and the install's own numbers agree today. They
are still resolved rather than assumed, and `iAVDhmsLevelUp` is read as an integer *and* as
a float because it is the one integer setting in the group.

`iAVDhmsLevelUp` is the same setting [actor values](/engine/actor-values.md) reads as
`ActorValueLevelSettings.pointsPerLevel`, where it is the number of points an NPC's class
spreads across the three attributes. Two readings of one setting, each stated by its own
source, and neither derived from the other.

## Where progress persists

`PlayerProgressState` is a world-state component keyed by `ReferenceKey.player`, carrying
the level, the experience banked toward the next one, the unspent perk-point pool, how many
attribute picks are owed, the picks already made, and a count of skill points gained. It
travels in the save's `PLVL` chunk, and a session that never levelled writes no chunk at all
([runtime state](/engine/runtime-state.md)).

Skill progress is *not* here — it lives in the `Skill Advance` actor values, because the
vanilla table already names a slot per skill holding exactly that quantity. Nothing in that
table holds a character level, so this is the one part of progression that needed a
component of its own.

Neither is the *effect* of an attribute pick. The ten points are a base offset on the chosen
actor value and ride in the `AVOV` chunk with every other session-made deviation from a
derived baseline. Two homes for the same ten points would be two chances to disagree; the
pick history beside them is a record of what happened, not the mechanism.

## When the level moves, and the one deviation

The moment the experience crosses the threshold. Vanilla banks the levels and moves the
number only once the player opens the skills menu — "when you do choose to level, you will
be raised to the highest level earned through skill progression" — and `Actor.GetLevel`
follows the menu there: "if you have leveled up but have yet to go into the perk menu
screen, this will still return your level seen in the HUD"
([GetLevel - Actor](https://www.creationkit.com/index.php?title=GetLevel_-_Actor)).

OpenSky raises the level, the perk point and the owed attribute pick together at the moment
they are earned, and leaves only the *choice* pending. That is a stated deviation. The
confirmation step is a menu, item 20.7 owns menus, and a level that is earned but invisible
to `GetLevel`, to `PC Level Mult` scaling and to every condition until a screen exists would
be a worse answer than one that is slightly early. The owed picks queue exactly as vanilla
queues them, so the screen still has its "if you gained 4 levels you will be prompted to
make 4 choices in succession".

## The attribute pick

One pick spends one owed choice and does three things, in this order:

1. Adds `iAVDhmsLevelUp` points to the chosen value's **base offset**, so it rides on top of
   whatever the records author and survives re-derivation ([actor values](/engine/actor-values.md)).
2. For stamina only, adds `fLevelUpCarryWeightMod` to carry weight. UESP states that as a
   rule of the pick rather than of stamina: "Adding to your base stamina when you level up
   increases your carry weight by 5. ... Temporary changes to your stamina (such as damage,
   drain, or fortify) do not affect your carry weight"
   ([Skyrim:Stamina](https://en.uesp.net/wiki/Skyrim:Stamina)).
3. Fills health, magicka and stamina, which is the other half of accepting a level: "When
   you accept the new level ... your character is fully healed, regaining any Health,
   Magicka, and Stamina that was depleted."

A pick nobody is owed is refused with `PlayerProgressError.noAttributePickOwed` rather than
handing out an unpaid-for ten points.

## The live player level

`PlayerLevelSource` is one small reference the derivation reads. `ActorValueResolver` and
`ActorValueBaselineResolver` are immutable values built once per load order and read from
the cell-build queue, and both take the player's level as an input because an NPC flagged
`PC Level Mult` scales against it. Storing it as an `Int` on those values would mean
rebuilding them — and every copy a runtime already holds — on every level-up.

So `PlayerLevelRuntime` publishes into the source its own `ActorValueRuntime`'s baselines
carry, and every derived baseline moves on its next read. Before item 20.6 there was no
player level, both defaulted to 1 and every scaled actor resolved at the bottom of its
range; that default survives for a session with no progression.

`ActorValueBaseline.level` is what carries the answer outward: an NPC's derived level, and
the player's character level, read by the condition seam and by the Papyrus native through
the one baseline every other actor-value read already goes through.

## Spending a perk point

`PerkTreeSpendValidator` is the only place the tree, the rank order and the skill
requirement are enforced. `PerkRuntime` stays what it was — a grant layer, because a quest,
a script and a race all hand out perks no tree gates.

Five rules, each with its own case in `PerkSpendRefusal`:

| Rule | Refusal | Where it comes from |
| --- | --- | --- |
| The record resolves | `unresolvedPerk` | A key nothing carries could never be evaluated |
| The perk is playable | `notPlayable` | PERK `DATA`; a quest perk is not something a point buys |
| Not already owned | `alreadyOwned` | A point spent twice buys nothing |
| In a tree at all | `notInPerkTree` | AVIF perk-tree node run |
| Rank order | `previousRankMissing` | The record whose `NNAM` names it must be owned |
| Tree parent | `parentMissing` | A box `FNAM` marks parent-required needs an owned parent |
| Record conditions | `unmetCondition` | The perk's own `CTDA` run — the skill requirement |

`PerkTreeIndex` inverts the AVIF connection run to answer the parent question. A node's
`CNAM` array is "Line to Index", pointing from parent to child, so parents are the boxes
whose lines reach a box. This machine's `AVOneHanded` reads, measured 2026-08-20 with
`make run-cli ARGS="record AVOneHanded"`:

```text
#0  perk NULL,           lines to [7]
#7  perk Armsman00,      lines to [4, 3, 5, 1, 6]
#1  perk FightingStance, lines to [2, 11]
```

The entry node grants no perk, so the first real box of every tree has a parent that costs
nothing to own. A higher rank is *not* its own box — `Armsman20` through `Armsman80` are
absent from the tree — so the box a rank belongs to is found by walking `NNAM` back to the
chain head.

Rules 5 and 6 overlap rule 7 on vanilla data, deliberately. Vanilla authors the parent both
as a `HasPerk` condition and as a tree line, but neither is guaranteed: `Armsman00` carries
no record conditions at all, while `Armsman20` carries both
`GetBaseActorValue One-Handed >= 20` and `HasPerk Armsman00 == 1`. Checking only one would
let a differently-authored tree be climbed out of order.

A record run this engine cannot evaluate is a refusal, not a pass: `ConditionEvaluator`
answers an unknown function with a reason-tagged false, so a perk gated on something
unimplemented stays unbuyable rather than free.

## The condition surface

Two functions arrived with this item, both because a vanilla perk requirement needs them.
Indices are the raw stored numbers; the Creation Kit spells each 4096 higher.

| Index | Function | Answer |
| --- | --- | --- |
| 80 | `GetLevel` | The actor's level — derived for an NPC, the character level for the player |
| 277 | `GetBaseActorValue` | The base value, never a modifier |

`GetBaseActorValue` reading the base rather than the total is the point: a fortified skill is
not a trained one, so a perk requirement is something a potion cannot buy. See
[conditions](/formats/conditions.md).

## The Papyrus surface

| Native | Source | Effect |
| --- | --- | --- |
| `Actor.GetLevel()` | Vanilla | The receiver's level, through the same baseline every actor-value read uses |
| `Game.GetPerkPoints()` | SKSE | The player's unspent perk points |
| `Game.ModPerkPoints(int)` | SKSE | Adds or removes points, clamped to the documented 0 – 255 |

The two perk-point functions have no vanilla Papyrus surface at all; the Creation Kit wiki
declares them as SKSE additions to the `Game` script, and the script-level half of SKSE
compatibility is a stated goal ([Papyrus VM](/engine/papyrus-vm.md)). `Game.SetPerkPoints`
is not implemented, and its absence is stated rather than guessed at. A session with no
character leveling refuses both rather than answering zero, which would read as a player who
has spent everything.

## What is deliberately absent

- **The level-up and perk-tree screens.** Item 20.7 owns them; this item owns the rules
  behind them, and `perkSpendRefusal(for:)` is the exact answer that screen draws a node's
  availability from.
- **Legendary skills**, which reset a skill at 100 and refund its perks.
- **The Dragonborn perk reset**, which spends a dragon soul to clear one tree.
- **Experience multipliers** — Rested, Well Rested, Lover's Comfort and the Guardian Stones
  — which multiply *skill* experience before it ever reaches this page, and which need the
  effects that grant them.
- **`Game.SetPerkPoints`**, above.
