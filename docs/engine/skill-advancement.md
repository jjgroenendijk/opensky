---
type: Subsystem
title: Skill advancement
description: How using a skill becomes skill experience, where it is stored, what crossing a
  threshold does to the skill and the character level, and which actions report a use.
tags: [engine, progression, skills, leveling, combat, magic, actor-values]
---

# Skill advancement

Skills improve by use. The path:

1. A system that performs an action reports it.
2. The skill's own numbers turn it into experience.
3. The experience builds up on the skill.
4. Crossing the threshold raises the skill by one point, and banks that point's worth toward the
   character level.

The actor value table is on the [actor values](/engine/actor-values.md) page. The `AVIF` record,
whose `AVSK` field holds the four numbers per skill, is on the
[actor value information](/formats/actor-value-information.md) page.

## Formulas

All three come from UESP [Skyrim:Leveling](https://en.uesp.net/wiki/Skyrim:Leveling):

| Question | Formula |
| --- | --- |
| What is one use worth? | `Skill Use Mult * amount + Skill Use Offset` |
| What does the next level cost? | `Skill Improve Mult * level ^ fSkillUseCurve + Skill Improve Offset` |
| What does a skill point bank? | `Skill level acquired * fXPPerSkillRank` |

The wiki text writes the cost curve with `(level-1)^1.95`. But its worked example, its graph, and
its totals all use the current level: "if you want to level Lockpicking (Skill Improve Mult 0.25,
Skill Improve Offset 300) from level 15 to 16: 0.25 * 15^1.95 + 300 = 349.1267420446517". OpenSky
follows the worked example, because it has numbers, and a test checks that number.

## The numbers

The four numbers per skill come from `AVSK` in the user's install. Vanilla values
(`make run-cli ARGS="record AVOneHanded"`):

| Skill | Use mult | Use offset | Improve mult | Improve offset |
| --- | --- | --- | --- | --- |
| One-Handed | 6.3 | 0 | 2 | 0 |
| Archery (`AVMarksman`) | 9.3 | 0 | 2 | 0 |
| Block | 8.1 | 0 | 2 | 0 |
| Heavy Armor | 3.8 | 0 | 2 | 0 |
| Destruction | 1.35 | 0 | 2 | 0 |
| Lockpicking | 45 | 10 | 0.25 | 300 |
| Smithing | 160 | 0 | 0.25 | 300 |

Smithing differs from the wiki's table, which says 1 and notes "in the original Skyrim.esm the skill
use multiplier is 160". The install says 160, and the install wins.

Two game settings:

| Setting | Vanilla | Default |
| --- | --- | --- |
| `fSkillUseCurve` | 1.95 | 1.95 |
| `fXPPerSkillRank` | Not in the plugins | 1, from UESP |

The skill limit of 100 is not a setting either. No game setting names it, and UESP states it in
text.

## Where experience is stored

In the eighteen "Skill Advance" actor values, indices 114 to 131. They are in the same order as the
skills at 6 to 23.

A separate world state component was the other option, and was rejected:

1. The vanilla table already has these slots for exactly this number. A second store could disagree
   with them.
2. `GetActorValue OneHandedSkillAdvance` is a question scripts and the console can ask. This way the
   answer is the same number the runtime spends.
3. Actor values are already logged and saved, so skill progress survives a load with no new save
   chunk.

The cost: a script can write skill progress with `SetActorValue`, as vanilla also allows. The write
is stored as a distance from the record value, like a trained point
([actor values](/engine/actor-values.md)).

The cost of the next point uses the base skill, never the modified one. A Fortify One-Handed potion
raises damage, not the number of blows the next point needs.

## Reporting a use

One reporting call, with an empty default, is shared by melee, the combat loop, projectiles, and
casting. The game view implements it once. So a swing, a blow taken, an arrow, and a spell reach the
same thresholds by one path, and a test scene with no progression reports nothing.

A use event has who acted, the kind of action, and its base experience. It does not name a skill.
A weapon's skill depends on its animation type, and armor's skill on what the target wears. Only
the session knows those.

Only the player advances: "for the player only" (<https://ck.uesp.net/wiki/AdvanceSkill_-_Game>).
NPC skills come from their records. Every dropped use is counted: an NPC's use, an action no skill
claims, an empty amount, and a skill with no `AVSK` in the load order.

## What each action is worth

UESP gives the unit per skill. Its note: "'Raw damage' refers to the damage before armor is taken
into account."

| Action | Skill | Base experience |
| --- | --- | --- |
| Melee hit that lands | One-Handed or Two-Handed, by animation type | The weapon's base damage |
| Arrow that lands | Archery | The bow's base damage |
| Blow blocked | Block | Raw damage the block took |
| Blow taken in armor | Heavy or Light Armor | Raw damage of the blow, times pieces worn |
| Spell cast | The effect's `MGEF` magic skill | Spell base cost times the effect's skill usage multiplier |
| Held spell, per step | The same | Magicka spent, times the same multiplier |
| Lock picked | Lockpicking | `fSkillUsageLockPick<band>`: 2, 3, 5, 8, 13 from Novice to Master |
| Lockpick broken | Lockpicking | `fSkillUsageLockPickBroken`, 0.25 |

- A weapon skill counts only when the blow hits something that has health ("against valid
  targets"), and always at base damage: "Boosting weapon damage via skill perks or equipment
  enchantments does not result in more XP per strike, nor does improving your weapons at a
  grindstone."
- Unarmed hits, staves, torches, and shields give nothing. "Unarmed combat does not have its own
  skill tree and cannot be developed like other skills."
- Casting counts per effect, not per spell, because the Creation Kit puts both values on the
  `MGEF`: "Magic Skill: The Skill associated with the effect ... will accumulate Skill Uses from
  it", and "Skill Usage Mult: For Spells, a multiplier to the Skill Uses ... that casting this
  effect will give the player" (<https://ck.uesp.net/wiki/Magic_Effect>). A spell with effects of
  two schools raises both.

## Armor: two readings

UESP [Heavy Armor](https://en.uesp.net/wiki/Skyrim:Heavy_Armor): "The number of heavy armor items
simultaneously worn by the player does increase XP gained ... If the player is wearing a mixed set
of heavy and light armor, XP will only be awarded to one skill". Two things are left open. OpenSky
decides them in one place:

- A mixed set counts for the larger half. Heavy wins a tie.
- Experience is multiplied by the number of pieces. That more pieces give more is quoted. The exact
  factor is not, and is not checked against the game.

## Crossing the threshold

Experience is spent one point at a time, so one big use can cross several points. The rest carries to
the next level, as the wiki's totals require ("Cumulative XP from Y to X = Cumulative(X) -
Cumulative(Y)"). Experience exactly equal to the cost gives one point and carries nothing. A skill at
the limit gains nothing and carries nothing.

Each point raises the base skill by one, stored as a distance from the record value. So a trained
skill survives a level change, a race change, or a new load order.

## Character experience

Each point banks `level * fXPPerSkillRank` toward the character level. Character leveling spends it
in the same call. So a skill point that crosses the character threshold raises the level, adds a
perk point, and asks for an attribute choice before the call returns. See
[character leveling](/engine/character-leveling.md).

Without character leveling (as in tests of skills alone), the experience is still computed and
reported, but not banked.

## Papyrus

| Function | Unit | Effect |
| --- | --- | --- |
| `Game.AdvanceSkill(asSkillName, afMagnitude)` | Skill use | Converted through `AVSK`. May or may not reach the threshold |
| `Game.IncrementSkill(asSkillName)` | One whole point | Raises the skill and banks character experience. Leaves stored progress alone |

`IncrementSkill` leaves progress alone on purpose. The point came from a trainer, a book, or a quest,
not from use. Spending the stored progress would take away something the point did not pay for.

Both act on the player only. Both refuse a name that is not one of the eighteen skills, and refuse
when the session has no progression. Names use the record names too, so the wiki's
`Game.AdvanceSkill("Marksman", 50.0)` raises Archery ([actor values](/engine/actor-values.md) lists
the names).

## Not reported yet

These actions have a skill and a known base experience, but the engine does not perform them yet.
Each needs one reporting call when its system arrives:

- Pickpocket and Speech: one base experience per gold moved.
- Smithing, Alchemy, and Enchanting, which need crafting menus.
- Sneak: `fSkillUsageSneakPerSecond` (0.625) while hidden, and sneak attacks.
- Restoration by healing done, and Destruction's difficulty change, which needs a difficulty setting.
- Shield bashes, which melee does not tell apart from swings yet.
