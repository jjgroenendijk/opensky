---
type: Subsystem
title: AI spell use
description: How an NPC that owns spells casts them in a fight - the same cast path as the player,
  where its spells come from including leveled spell lists, which spells become options, and what
  is simplified on purpose.
tags: [engine, magic, combat, combat-ai, npc, spells]
---

# AI spell use

An NPC that owns spells casts them in a fight. The decision of when to cast is on the
[combat behavior](combat-behavior.md) page. This page covers what stands behind it.

## The same path as the player

So casts in progress are keyed by the actor and the hand, not the hand alone: two actors charging at
once are two casts.

An NPC always casts with its right hand. Vanilla NPCs cast from either hand and dual-cast. One hand
is a simplification.

## Where an NPC's spells come from

The spells are read from records, beside the spellbook, as inventory baselines sit beside the
inventory:

| Source | Field | Inherited through |
| --- | --- | --- |
| The `NPC_` | `SPLO` list | `ACBS` "Use Spell List": a record passes its list up only while that bit is set |
| The actor's `RACE` | `SPLO` list | The traits template, because the race an actor is comes from its traits |

An entry may name a leveled spell list (`LVSP`), and for vanilla casters the useful ones do. In
`Skyrim.esm`, `LvlBanditWizard` has seven `SPLO` entries. Every one that is a `SPEL` is a self buff
or a heal: Ironflesh, a ward, two heals, a racial ability, and a Breton power. Its attack spells are
behind two `LVSP` records, `LSpellBandit03FireFrostShock` and `LSpellBandit05FireFrostShock`, each
with three choices at level 1. Without expanding those, a vanilla caster knows nothing to throw. The
list rolls for the actor's base at its encounter level, the same roll the template chain uses for an
`LVLN` and the outfit chain for an `LVLI` ([leveled lists](leveled-lists.md)).

The list is added to the actor's spellbook the first time the combat loop asks what that actor can
cast, and its abilities are applied in the same pass. This is done late, not at cell build: a cell of
forty townsfolk who never fight would otherwise write forty spellbooks into the save, repeating what
their records say. Doing it twice changes nothing.

## Which spells become options

A known spell becomes a combat option only if it passes four checks:

| Check | Refuses |
| --- | --- |
| The spell type is spell | An ability, which is carried, and a power, a once-a-day resource this layer has no rule for |
| The delivery is not self | A self buff or heal, which is not something to throw at someone |
| Some effect entry is hostile | A heal or buff cast at an enemy |
| OpenSky runs the delivery, and the `ETYP` takes a hand | A cast that would only be counted as missing, or one with no hand to cast from |

An option carries the cost, the range (`SPIT`'s, or the session's aimed limit for a record that sets
none), the charge time, and whether it is held. The machine reads these and never reads a record.

In the install, `LvlBanditWizard`'s nine known spells give two options: Ice Spike at 48 magicka and
Ice Storm at 144, both aimed and reaching 4,000 units.

## What a released cast does

The same as the player's. An aimed fire-and-forget spell fires its `PROJ`
([spell delivery](spell-delivery.md)). A target actor spell applies to what the caster's aim
ray reaches. A held spell is held for 1.5 s and applies once a second. Only the ray differs: an NPC's
spell leaves the NPC's own eye, aimed at the middle of the player's capsule.

A held cast whose `SPIT` minimum duration has not passed is dropped too. The player's release waits
for the minimum because their button is still held. An NPC has no button.

## How the game rates a spell

The game rates each spell an NPC could cast, then takes the best one it can use and afford.

### Each effect

A fixed table rates the effects. An effect finds its row by four things: its archetype, its primary
actor value (only where the row names one), whether the `MGEF` is hostile (flag `0x01`), and whether
the spell's delivery is Self. The value modifier rows also cover the absorb (4), dual value modifier
(5), accumulate magnitude (32), and peak value modifier (34) archetypes.

| Archetype, actor value | Hostile, not Self | Weight | Rates | Min cast time setting |
| --- | --- | --- | --- | --- |
| Value modifier, Health (24) | yes | 1 | magnitude | `fCombatMagicOffensiveMinCastTime` (3) |
| Value modifier, Magicka (25) | yes | 0.5 | magnitude | offensive (3) |
| Value modifier, Stamina (26) | yes | 0.33 | magnitude | offensive (3) |
| Stagger (33) | yes | 10 | magnitude | `fCombatMagicDefaultMinCastTime` (1) |
| Disarm (9) | yes | 10 | magnitude | default (1) |
| Command Summoned (10) | yes | 10 | magnitude | `fCombatMagicTargetEffectMinCastTime` (10) |
| Banish (42), Confidence (1) | yes | 5 | magnitude | target effect (10) |
| Turn Undead (24), Confidence (1) | yes | 3 | magnitude | target effect (10) |
| Paralysis (21), actor value 53 | yes | 20 | effect cost | `fCombatMagicParalyzeMinCastTime` (2) |
| Script (1) | yes | 1 | script AI score | default (1) |
| Value modifier, Health (24) | no, Self | 1 | magnitude | default (1) |
| Value modifier, Magicka (25) | no, Self | 0.33 | magnitude | default (1) |
| Value modifier, Stamina (26) | no, Self | 0.1 | magnitude | default (1) |
| Value modifier, Ward Power (63) | no, Self | 1 | magnitude | `fCombatMagicWardMinCastTime` (1.5) |
| Summon (18) | no, Self | 1 | effect cost | `fCombatMagicSummonMinCastTime` (15) |
| Summon (18) | no, not Self | 1 | effect cost | summon (15) |
| Cloak (35) | no, Self | 1 | magnitude | `fCombatMagicCloakMinCastTime` (5) |
| Light (12) | no, Self | 1 | effect cost | `fCombatMagicLightMinCastTime` (10) |
| Invisibility (11), actor value 54 | no, Self | 1 | effect cost | `fCombatMagicInvisibilityMinCastTime` (15) |
| Bound Weapon (17) | no, Self | 1 | effect cost | default (1) |
| Value modifier, Damage Resist (39) | no, Self | 1 | magnitude | `fCombatMagicArmorMinCastTime` (15) |
| Reanimate (22) | no, not Self | 10 | magnitude | `fCombatMagicReanimateMinCastTime` (15) |
| Script (1) | no, Self | 1 | script AI score | default (1) |

An effect that matches no row scores 0, for example Demoralize (7) or a Slow on Speed Mult. The
magnitude is 0 when the `MGEF` has the No Magnitude flag (`0x400`).

```text
value    = (magnitude or effect cost) x share
duration = 3 for a concentration spell (fCombatMagicConcentrationScoreDuration)
           else max(duration, 1), plus taper duration x taper weight x 0.5
           when the MGEF has neither No Duration (0x200) nor No Magnitude (0x400)
score    = value x duration x row weight
```

- The share is 1. A dual value modifier rates its second actor value the same way, with the
  `MGEF` second actor value weight as the share, and adds it.
- A Script row ignores all of this: its score is the `MGEF` script AI score times the row weight.
- A hostile effect with a resist actor value is multiplied by the target's resistance multiplier.
- Magicka and Stamina damage score 0 unless the target holds more than 0.2 of that value, and a
  further check on the target passes. That check was not found.

### The spell

- The spell's score is the sum of its effect scores.
- The best scoring effect whose row names a min cast time decides how the NPC uses the spell. The
  Magicka and Stamina damage rows and the Self Stamina row name none.
- The item score is the spell score times the combat style's magic score multiplier (the shout
  multiplier for a shout, the staff multiplier for a staff). It doubles, by
  `fCombatInventoryRangedScoreMult` (2), when the spell reaches farther than `fCombatRangedDistance`
  (1024).
- The spell is no option when its cost is above the caster's current value of its cost actor value.
  For a concentration spell the cost is multiplied by the deciding row's min cast time. An item
  paid with charge (actor values 64 and 82) skips this test.
- A target beyond the range plus reach (plus `fCombatInventoryMaxRangeEquippedBonus`, 384, when the
  spell is readied) multiplies the score by `fCombatInventoryMaxRangeScoreMult` (0.1) times the
  range plus reach over the distance. A target inside the minimum range (plus
  `fCombatInventoryMinRangeUnequippedBonus`, 256, when not readied) multiplies it by
  `fCombatInventoryMinRangeScoreMult` (0.1). A readied spell adds
  `fCombatInventoryEquippedScoreBonus` (0.1).
- The candidates are sorted by score. The best one that can be used and passes the resource test
  wins. No roll and no cost tie-break were found.

Example: a Firebolt has a fire damage effect of magnitude 25, duration 0, taper weight 0.3, and
taper duration 1. The duration factor is `1 + 1 x 0.3 x 0.5 = 1.15`, so it scores
`25 x 1.15 = 28.75`. Its stagger effect is not hostile and scores 0. An Ice Spike's frost damage is
a dual value modifier of magnitude 25 with No Duration: Health gives 25, and its second actor value,
Stamina with weight 1, gives `25 x 0.33 = 8.25`, so it scores 33.25. Both reach past 1024 units, so
both item scores double, and the Ice Spike wins.

## Simplified on purpose

- Combat style (`CSTY`) is not decoded. Vanilla tunes when a caster prefers magic, at what range, and
  with what magicka limits through `CSTY` and game settings. OpenSky uses one probability and one
  choice rule ([combat behavior settings](combat-behavior.md#settings)). Decoding the style
  is the next step if the simple rule looks wrong in play.
- The strongest affordable spell wins. Cost stands in for strength, because OpenSky does not
  rate spells as the game does ([magic records](../formats/magic-records.md#mgef-data)).
- After an NPC casts a spell with a Script effect, it casts no such spell for the largest script
  AI delay of that spell's effects. Its other spells stay open.
- No shouts, summons, reanimation, or healing itself mid-fight. An NPC only casts a hostile spell at
  its target. The buffs and heals in its list are known and never chosen.
