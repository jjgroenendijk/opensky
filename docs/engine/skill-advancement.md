---
type: Subsystem
title: Skill advancement
description: How use of a skill becomes skill experience, where that experience is stored,
  what a threshold crossing does to the skill and to character leveling, and which systems
  report a use today.
tags: [engine, progression, skills, leveling, combat, magic, actor-values]
timestamp: 2026-08-19T00:00:00Z
---

# Skill advancement

Skills improve by use. This page is the whole path: a system that simulates an action
reports it, the skill's own AVIF parameters convert it into experience, the experience
accumulates on the skill, and crossing the threshold raises the skill by a point and banks
what that point is worth toward the character's own level.

The record side is [actor values](/engine/actor-values.md) for the table every number here
is addressed by, and [perks](/formats/perks.md) for the AVIF record itself, whose `AVSK`
field carries the four per-skill numbers.

## Contents

- The three formulas
- Where the numbers come from
- Where accumulated experience is stored
- Reporting a use
- What each action is worth
- Crossing the threshold
- Character experience
- The Papyrus surface
- What is not wired yet

## The three formulas

All three are UESP's, from
[Skyrim:Leveling](https://en.uesp.net/wiki/Skyrim:Leveling), and they live as pure
functions in `SkillAdvancement`:

| Question | Formula |
| --- | --- |
| What is one use worth? | `Skill Use Mult * amount + Skill Use Offset` |
| What does the next skill level cost? | `Skill Improve Mult * level ^ fSkillUseCurve + Skill Improve Offset` |
| What does a skill point bank? | `Skill level acquired * fXPPerSkillRank` |

The wiki's prose writes the cost curve as `(level-1)^1.95` while its own worked example,
its graph caption and its per-skill totals all use the current level: "if you want to level
Lockpicking (Skill Improve Mult 0.25, Skill Improve Offset 300) from level 15 to 16: 0.25 *
15^1.95 + 300 = 349.1267420446517". The worked example is the one OpenSky follows, because
it is the one with numbers attached, and `SkillAdvancementTests` pins that number.

## Where the numbers come from

The four per-skill numbers are the AVIF `AVSK` field (`SkillUseParameters`), read off the
user's own install through `ActorValueInformationStore` and reached by
`SkillUseParameterSource`. Measured on this machine 2026-08-19 with
`make run-cli ARGS="record AVOneHanded"`:

| Skill | Use mult | Use offset | Improve mult | Improve offset |
| --- | --- | --- | --- | --- |
| One-Handed | 6.3 | 0 | 2 | 0 |
| Archery (`AVMarksman`) | 9.3 | 0 | 2 | 0 |
| Block | 8.1 | 0 | 2 | 0 |
| Heavy Armor | 3.8 | 0 | 2 | 0 |
| Destruction | 1.35 | 0 | 2 | 0 |
| Lockpicking | 45 | 10 | 0.25 | 300 |
| Smithing | 160 | 0 | 0.25 | 300 |

Smithing is the one row that differs from the table on the wiki, which prints 1 and notes
"in the original Skyrim.esm the skill use multiplier is 160". The install says 160, and the
install wins.

Two game settings, resolved by `SkillAdvancementSettings`:

| Setting | Install value | Fallback |
| --- | --- | --- |
| `fSkillUseCurve` | 1.95 | 1.95 |
| `fXPPerSkillRank` | not authored | 1 |

No active plugin on this machine authors `fXPPerSkillRank`, so it takes the UESP-documented
default of 1 — the same typed-read-with-a-documented-fallback shape
`ActorValueLevelSettings` uses. The skill ceiling of 100 is likewise not a setting: no
`iMaxSkill`- or `fSkillCap`-prefixed GMST exists in the install, and UESP states the ceiling
in prose instead.

## Where accumulated experience is stored

In the eighteen `Skill Advance` actor values, indices 114 through 131, which run in the same
order as the skills at 6 through 23 (`ActorValueIdentity.skillAdvanceIndex(forSkill:)`).

A dedicated world-state component was the alternative and was rejected:

1. The vanilla table already names exactly these slots and they hold exactly this quantity.
   A component beside them would be a second place skill progress lives, and the two could
   disagree.
2. `GetActorValue OneHandedSkillAdvance` is a question the game's own script corpus and
   console can ask, and answering it from the same number the runtime spends is free this
   way.
3. Persistence comes for nothing: actor values already travel in the journal and the save,
   so the skill half of progression survives a reload with no new save chunk.

The cost is that a script can write skill progress with `SetActorValue`, which vanilla also
allows. The write goes through `ActorValueRuntime.setBase`, so it is stored as an offset
from the derived baseline exactly like a trained skill point is
([actor values](/engine/actor-values.md)).

The skill *level* a threshold is computed against is the base value, never the modified one:
a Fortify One-Handed potion raises the number a swing does and not the number of blows the
next point costs.

## Reporting a use

`SkillUseReporting` is one method with a do-nothing default, shaped exactly like
`ScriptHitReporting`. `MeleeCombatWorld`, `CombatLoopWorld`, `ProjectileWorld` and
`CasterWorld` all refine it, and `GameViewController` implements it once — so a swing, a
blow taken, an arrow and a cast reach the same thresholds through one path, and a synthetic
scene with no progression compiles and reports nothing.

A `SkillUseEvent` carries who acted, what kind of action it was, and the action's base
experience. It deliberately does not carry a skill: a weapon hit's skill depends on the
animation family the weapon belongs to, and an armoured hit's on what the target is wearing,
which is a question only the session can answer.

`SkillAdvancementRuntime` converts. Only the player advances — "for the player only"
(<https://ck.uesp.net/wiki/AdvanceSkill_-_Game>) — and NPCs stay on skills derived from
their records. Every drop is a counter on `SkillAdvancementTally` rather than a log line: an
NPC's use, an action no skill claims, an empty amount, and a load order with no `AVSK` for
the skill.

## What each action is worth

UESP's per-skill notes give the unit, and its footnote defines "raw": "'Raw damage' refers
to the damage before armor is taken into account."

| Action | Skill | Base experience |
| --- | --- | --- |
| Landed melee strike | One-Handed or Two-Handed, by animation family | The weapon's WEAP base damage |
| Landed arrow | Archery | The bow's WEAP base damage |
| Blow blocked | Block | Raw damage the block absorbed |
| Blow taken in armour | Heavy or Light Armor | Raw rating of the strike, times pieces worn |
| Cast | The effect's MGEF Magic Skill | Spell base cost times the effect's `Skill Usage Mult` |
| Maintained cast, per step | The same | Magicka drained, times the same multiplier |

Three consequences worth stating:

- A weapon skill is credited only when the blow reached something whose health it could take
  ("against valid targets"), and always at the *base* damage: "Boosting weapon damage via
  skill perks or equipment enchantments does not result in more XP per strike, nor does
  improving your weapons at a grindstone."
- Unarmed strikes, staves, torches and shields credit nothing. "Unarmed combat does not have
  its own skill tree and cannot be developed like other skills."
- Casting is per *effect*, not per spell, because the Creation Kit puts both halves on the
  MGEF: "Magic Skill: The Skill associated with the effect ... will accumulate Skill Uses
  from it", and "Skill Usage Mult: For Spells, a multiplier to the Skill Uses ... that
  casting this effect will give the player" (<https://ck.uesp.net/wiki/Magic_Effect>). A
  spell whose effects name two schools feeds both.

### The armour reading, flagged

"The number of heavy armor items simultaneously worn by the player does increase XP gained
... If the player is wearing a mixed set of heavy and light armor, XP will only be awarded
to one skill" (<https://en.uesp.net/wiki/Skyrim:Heavy_Armor>). Two things that paragraph
leaves open are decided in `WornArmorProfile` rather than at a call site, and both are
readings rather than quotations:

- A mixed set credits the larger half, and heavy armour takes a tie.
- The piece count scales the experience proportionally, so four pieces are worth four times
  one. That the count raises it is quoted; the factor is not, and is unverified against the
  shipped game.

## Crossing the threshold

`SkillAdvancement.advance` spends the accumulated experience against thresholds one whole
point at a time, so one enormous use can cross several. The remainder carries onto the next
level, which is what the wiki's cumulative arithmetic requires ("Cumulative XP from Y to X =
Cumulative(X) - Cumulative(Y)"); experience exactly equal to the threshold advances the
skill and carries nothing. A skill at the ceiling gains nothing and carries nothing.

Each point raises the skill's base by one through `ActorValueRuntime.advanceSkill`, which
guards the index against the eighteen skills and stores the point as an offset — so a
trained skill survives a level change, a race change or a reordered load order.

## Character experience

Each point banks `level * fXPPerSkillRank` into `PlayerProgressState`, beside a count of the
points gained. That value is the seam item 20.6 fills in: the character level curve
(`fXPLevelUpBase` 75 and `fXPLevelUpMult` 25 on this install), the attribute pick, the perk
point, and where all of it persists are that item's, and inventing a save chunk for them
here would fix a shape it has not decided yet. So the bank is a session accumulator today
and a reload starts it at zero — a stated gap, not a hidden one. The skill half persists
regardless, because it lives in the actor values.

## The Papyrus surface

| Native | Unit | Effect |
| --- | --- | --- |
| `Game.AdvanceSkill(asSkillName, afMagnitude)` | Skill *use* | Converts through the skill's `AVSK` and may or may not reach the threshold |
| `Game.IncrementSkill(asSkillName)` | One whole point | Raises the skill, banks the character experience, leaves accumulated progress alone |

`IncrementSkill` leaving the progress alone is deliberate: the point did not come from use —
a trainer, a skill book, a quest reward — so spending what the character earned by using the
skill would take away something the point did not pay for.

Both are global functions acting on the player alone, both refuse a name that is not one of
the eighteen skills, and both refuse rather than pretend when the session runs no
progression. The name is read with the record vocabulary, so the wiki's own
`Game.AdvanceSkill("Marksman", 50.0)` reaches Archery
([actor values](/engine/actor-values.md) has the alias table).

## What is not wired yet

Every action below has a skill and a documented base experience, and nothing reports it
because the engine does not simulate the action yet. Each becomes one emitting call at the
seam that grows it:

- Lockpicking: `fSkillUsageLockPickBroken` 0.25 and the five per-difficulty settings
  (2, 3, 5, 8, 13) are already in the install and read for nothing.
- Pickpocketing and Speech: one base experience per gold moved.
- Smithing, Alchemy and Enchanting: crafting, which no menu drives yet.
- Sneak: `fSkillUsageSneakPerSecond` 0.625 while hidden, plus the sneak-attack amounts.
- Restoration by healing done, and the Destruction difficulty reduction, which needs a
  difficulty setting the engine does not carry.
- Shield bashes, which the melee runtime does not distinguish from swings yet.

Item 20.7 puts the read-only surface — accumulated experience, threshold, banked character
experience — in the progression panel.
