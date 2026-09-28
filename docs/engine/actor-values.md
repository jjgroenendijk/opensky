---
type: Subsystem
title: Actor values
description: How OpenSky derives health, magicka, stamina, skills, and the other actor values from
  records, how the level points are shared out, how the formula was checked against the install,
  and how resistances and weaknesses combine.
tags: [engine, actors, gameplay, stats, health, magicka, stamina, resistances, skills]
---

# Actor values

An actor value is one number on an actor, such as health, One-Handed skill, or fire resistance. The
vanilla table has 164 entries. This page covers what an actor value is before anything changes it:
its baseline, derived from records. The record layouts are on the [actor records](/formats/actors.md)
and [race and class](/formats/actors.md#race) pages.

Related pages:

- [Actor value store](/engine/actor-value-store.md): damage, modifiers, script writes,
  regeneration, the HUD bars, and saving.
- [Actor value names](/engine/actor-value-names.md): how a condition index and a Papyrus name find
  the same value.

The record side is read-only and built once per load order. The runtime side is mutable and knows
nothing about records: it asks for a baseline and never derives one itself. Inventory uses the same
split.

## Health, magicka, and stamina

Every rule is quoted from an open source. The two constants come from game settings, not literals.

Without the `ACBS` auto-calc flag:

```text
value = race starting attribute + ACBS offset
```

"If the auto-calc flag for an NPC isn't set, all attributes are calculated just as: Attribute =
[Racial bonus] + [NPC offset]." (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS>)

With it:

```text
magicka = race + offset + share(iAVDhmsLevelUp * (level - 1), class weights)
stamina = same
health  = same + fNPCHealthLevelBonus * (level - 1)
```

UESP: "Attribute = [Racial bonus] + [NPC offset] + 10\*(Level-1)/(Sum of class' attribute
weights)\*[Attribute weight]", and "The only difference for health is that health always receives an
additional 5 points per level, regardless of the class weights". The Creation Kit names both
constants: "all Actors gain 10 points to distribute per level (this value comes from the
iAVDhmsLevelUp game setting) ... NPC's get a bonus amount of health per level as set by the
fNPCHealthLevelBonus game setting; by default this is 5." (<https://ck.uesp.net/wiki/Class>)
`Skyrim.esm` sets both to these defaults.

The level is the `ACBS` level word. A `PC Level Mult` actor multiplies the player's level by that
word over 1000, then clamps to Calc Min and Calc Max (<https://ck.uesp.net/wiki/Stats_Tab>). A zero
bound means no bound, because that is what the Creation Kit writes when a designer sets no clamp.
`PC Level Mult` implies auto-calc: "Note that if PC Level Mult is checked, Auto Calc Stats will
always be checked." (Same page.)

A negative offset can be larger than a small race base. The result stops at zero. The game has no
negative maximum, and one would break every fraction the HUD asks for.

## Sharing out the level points

The per-level spread is not a multiply and round. UESP states "the exact method":

1. Hand out every complete set of points first: `floor(points / sum of weights) * weight` each.
2. Give the leftover out one at a time, looping over the attributes "ordered first in decreasing
   order of weight", with ties broken "in reverse actor value index order (stamina, magicka, then
   health)". No attribute gets more than its own weight in one pass.

The Creation Kit's worked example breaks ties the other way (health first), but gets the same
numbers on every documented case, because ties only matter when the leftover runs out mid-pass.
Where they differ, OpenSky follows UESP, which calls its rule the exact method.

Every point is handed out, so the three results always add up to the points available. A class with
no weights shares nothing, instead of dividing by zero and putting a NaN into an actor's health.

## How the formula was checked

The Creation Kit writes its own calculated health, magicka, and stamina into every `NPC_` `DNAM`.
That is an independent answer. Deriving every auto-calc `NPC_` in `Skyrim.esm` without `PC Level
Mult` and comparing gives 4,297 records: 4,271 exact and 26 explained.

The 26 all take their stats from one template, `EncBandit04TemplateMelee` (`0001E60D`), whose `DNAM`
disagrees with its own `ACBS`. `NordRace`'s 50 starting health plus its +125 offset is 175, and its
`DNAM` says 170. Its sibling `EncBandit03TemplateMelee` matches the formula exactly. So the formula
is right and the stored value is stale, which the Creation Kit says can happen: "one must refresh
the Stats Tab (click on another tab then back to the Stats Tab) to update Calculated Health,
Magicka, and Stamina if Attribute Offsets or underlying Race or Class Base Attributes change."
(<https://ck.uesp.net/wiki/Stats_Tab>)

Getting from 61 mismatches to 26 is what showed the `statsRace` rule on the
[actor records](/formats/actors.md) page.

`openskycli actor-values --npc <formid-or-edid>` prints one actor's derivation with the record each
input came from. `--race <formid-or-edid>` prints one race's starting attributes, regeneration
rates, and derived table.

## The other values

An untouched value reads a baseline from records, where records give one:

| Actor value | Source |
| --- | --- |
| The eighteen skills (6 to 23) | 15 + `RACE` `DATA` skill bonus + the class spread |
| `Speed Mult` (30) | `NPC_` `ACBS` 0x0E "Speed Multiplier" |
| `Carry Weight` (32) | `RACE` `DATA` 0x30 "Base Carry Weight" |
| `Unarmed Damage` (35) | `RACE` `DATA` 0x60 "Unarmed Damage" |
| `Mass` (36) | `RACE` `DATA` 0x34 "Base Mass" |
| Everything else | 0 |

The skill formula is quoted: "Skill = 15 + [Racial bonus] + 8\*(Level-1)/(Sum of class' skill
weights)\*[Skill weight]" (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS>). The leftover
points go out "one at a time by looping over all the skills in order ... ordered first by their
weight (higher skills ordered first) and second by their actor value index (lower indices are
ordered first)". That tie rule is the opposite of the attribute one. Both are used as written. The 8
is `iAVDSkillsLevelUp`, which `Skyrim.esm` sets to exactly that.

Example: `NordRace` gives Two-Handed +10, and One-Handed, Block, Smithing, Light Armor, and Speech
+5, as UESP documents. Every playable race gives 300 carry weight, mass 1, and a 35-point skill
bonus budget.

Zero for everything else is a real value, not a placeholder. An actor value adds things up: a
resistance nothing grants is 0%, and a bonus nothing gives is +0. An actor with no record behind it,
such as a summon, reads 0 for mass and carry weight and 100 for speed. That is a known gap.

`NPC_` `DNAM` has "18 base skills, 18 skill mods". OpenSky does not read them. No open source says
how the two arrays differ, and the class formula itself is only "generally only be accurate to
within a couple points". So neither settles how they combine, and a number with an unknown source is
worse than the documented one.

## Resistances

A resistance actor value holds percentage points. `MGEF` `DATA` names the value an effect is resisted
by ("Resistance Actor Value"), so the resistance query takes an index, not a damage type.

The cap is 85%, and only for the player: "Resist Magic is capped at 85%. The cap only applies to
you; followers and enemies with 100% resistance are truly immune."
(<https://en.uesp.net/wiki/Skyrim:Resist_Magic>) Resist Poison has the same cap
(<https://en.uesp.net/wiki/Skyrim:Resist_Poison>). Resist Disease does not: "Resist Disease 100%
provides disease immunity ... values above 100% provide no additional benefit"
(<https://en.uesp.net/wiki/Skyrim:Resist_Disease>).

The cap is an OpenSky constant, not a game setting. The install's full game setting table has no
resistance cap under any editor ID. The only two settings matching "resist" are the strings
`sMagicEffectResisted` and `sNormalWeaponsResisted`. So no plugin can change it.

Resistances multiply, Resist Magic first: "a 100-point Fire Damage spell would deal only 15 points
of damage with Resist Magic 85%; Resist Fire 85% would then reduce the 15 points by a further 85% to
2.25 points of final damage" (same page).

A negative resistance is a weakness, and it stays negative. UESP words Weakness to Fire as "Target
is `<mag>`% weaker to fire damage" (<https://en.uesp.net/wiki/Skyrim:Weakness_to_Fire>), and vanilla
writes it as a harmful value modifier on `Resist Fire`. So a target at -30 points reads -0.3 and
takes 130% damage. There is no lower limit, because no source states one: the cap only bounds the
resistant end. Two weaknesses multiply through the same rule, which matches "Weakness to fire is
strengthened by weakness to magic".

`Damage Resist` (39) is not a percentage resistance. It is an armor rating with its own formula and
its own 80% cap, which is a game setting (`fMaxArmorRating = 80`). Reading 40 armor as 40%
resistance would be wrong, so the percentage query refuses it.
