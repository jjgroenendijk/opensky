---
type: Subsystem
title: Perk entry points
description: Which formula reads each perk entry point, what it binds, and where OpenSky's rule
  is a reading of a source rather than a measured fact.
tags: [engine, perks, combat, magic, barter, stealth, crafting]
---

# Perk entry points

A perk entry point is a named place in a game rule where perks may change a value. The
[perks](/engine/perks.md) page explains how one is evaluated. This page lists which rule reads
each one. An entry point that no rule reads changes nothing.

Sources: the Creation Kit wiki page "Perk Entry Point"
(<https://ck.uesp.net/wiki/Perk_Entry_Point>), and UESP "Skyrim Mod:Mod File Format/PERK" for the
condition subjects. The numbers are xEdit's.

## Weapon hits

Every weapon hit, by the player or an NPC, melee or arrow, builds one set of strike terms. The
attacker owns the attack perks, with the weapon and the target bound. The struck actor owns the
defence perks, with the attacker and its weapon bound.

| Entry point | Id | Where |
| --- | --- | --- |
| Calculate Weapon Damage | 0 | adds to the base damage, such as Silver vs undead |
| Calculate My Critical Hit Chance | 1 | the critical chance, in percent |
| Calculate My Critical Hit Damage | 2 | the critical damage |
| Mod Sneak Attack Mult | 18 | the sneak-attack factor |
| Mod Bashing Damage | 26 | a bash |
| Mod Power Attack Stamina | 27 | the stamina a player power attack costs |
| Mod Power Attack Damage | 28 | a power attack |
| Mod Incoming Stagger | 33 | the struck actor's stagger |
| Mod Target Stagger | 34 | the stagger the attacker causes |
| Mod Attack Damage | 35 | every swing and arrow |
| Mod Incoming Damage | 36 | the struck actor's damage |
| Mod Target Damage Resistance | 37 | the struck actor's armour rating |
| Mod Shield Deflect Arrow Chance | 40 | an arrow that strikes an actor with a shield |
| Set Sweep Attack | 50 | whether a swing strikes every actor in its arc |
| Apply Combat Hit Spell | 51 | a spell on the struck actor |
| Apply Bashing Spell | 52 | a spell on the bashed actor |
| Apply Weapon Swing Spell | 67 | a spell on the actor an enemy swings at |
| Mod Armor Rating | 85 | each worn piece, after tempering |

Rules that are a reading of the wiki, not a measured fact:

- The critical chance starts at the `Critical Chance` actor value, 0 without effects, as the
  wiki says. `CRDT` "% Mult" scales the chance. The damage starts at `CRDT` damage and is added
  after every factor, before the block, so tempering does not raise it. A bash is never a
  critical. The `CRDT` spell is not cast.
- Only the first passing select-spell effect at an entry point lands. Vanilla perks such as
  Warmaster and Paralyzing Strike share one condition, so with both owned only the higher
  priority one applies. This matches the known game limit that one combat-hit spell applies per
  hit, which no primary source states.
- An unarmed hit is not a combat hit (wiki). NPC weapons are unarmed in OpenSky today, so an
  NPC's combat-hit spells never land.
- `IsAttackType` compares the keyword's editor ID with the attack in progress. A power attack
  has `PowerAttackTypeStanding`, `PowerAttackTypeForward`, `PowerAttackTypeBack`, or
  `PowerAttackTypeSide` for either side, and a power bash `PowerAttackBash`. The game reads the
  keyword from the race's attack data; OpenSky has none, so the names stand in for it.
- A deflected arrow does no damage and reports no hit. OpenSky has no bounce, so the arrow
  still sticks where it struck.

## Spells

A spell the player or an NPC casts lands its effects scaled by the caster's and the target's
perks. The spell is bound as a base form, and `EPMagic_*` conditions read it.

| Entry point | Id | Where |
| --- | --- | --- |
| Mod Spell Magnitude | 29 | each effect's magnitude, caster's perk, target bound |
| Mod Spell Duration | 30 | each effect's duration, caster's perk, target bound |
| Mod Incoming Spell Magnitude | 41 | each effect's magnitude, target's perk |
| Mod Spell Cost | 38 | the magicka cost |

The scaling applies to a cast spell or scroll, on a projectile hit and on a self cast. A drunk
potion takes Mod Spell Magnitude and Mod Spell Duration from the drinker's perks, with the potion
bound as the spell. Its `HasKeyword` reads the keywords of its effects, so Catalyst's test of
`MagicAlchBeneficial` and `MagicAlchDurationBased` works. A potion skips Mod Incoming Spell
Magnitude: the Atronach Stone's perk halves it with no condition, which would halve every drink.
`EPMagic_SpellHasKeyword` reads the same keywords; the other `EPMagic_*` conditions fail on a
potion. A worn or weapon enchantment and a perk ability apply as authored.

## Barter

| Entry point | Id | Where |
| --- | --- | --- |
| Mod Buy Prices | 8 | the buy modifier, merchant bound as the target |
| Mod Sell Prices | 60 | the sell modifier, merchant bound as the target |
| Mod Player Intimidation | 43 | the intimidation check |
| Mod Bribe Amount | 46 | the bribe price |

## Crafting

| Entry point | Id | Where |
| --- | --- | --- |
| Mod Tempering Health | 76 | a factor on the skill above the offset in the best quality level, item bound |
| Mod Ingredients Harvested | 87 | how many times a plant's produce is granted, produce bound as the item |

The entry point starts at 1. The steel and advanced smithing perks multiply it by 2 for their
material, and Fortify Smithing multiplies it by `1 + Smithing Modifier / 100`. The result is the
`1 + perk` term of the UESP effective skill (see [crafting](/engine/crafting.md)). UESP gives the
perk term only; that Fortify Smithing enters the same term is read from `PerkSkillBoosts`.

## Animation

| Entry point | Id | Where |
| --- | --- | --- |
| Set Boolean Graph Variable | 54 | each passing perk's text names a player graph variable set true |

The perks are read every frame. A variable whose perk stops passing goes back to false: Ranger's
`bPerkQuickShot` holds only while the player does not sneak. Vanilla uses `bPerkShieldCharge`,
`bPerkQuickdraw` and `bPerkQuickShot`.

## Armour weight

| Entry point | Id | Where |
| --- | --- | --- |
| Mod Armor Weight | 32 | each worn armour piece, item bound |

Conditioning and Unhindered set worn heavy or light armour to 0. The perk weight counts in the
carried total, which the inventory menus, `IsOverEncumbered` and fast travel read, and in the
movement noise of detection. A carried piece that is not worn keeps its record weight.

## Stealth

| Entry point | Id | Where |
| --- | --- | --- |
| Mod Detection Sneak Skill | 57 | the sneaker skill in the detection value |
| Mod Detection Light | 47 | the target's light level, before the clamp to 1 |
| Mod Detection Movement | 48 | the movement part of the sound term |
| Mod Spell Casting Sound Event | 55 | a factor on a cast's action sound, spell bound |
| Apply Sneaking Spell | 69 | the chosen spell, cast on the player on the frame sneak starts |

These are the player's perks, evaluated once a frame with no observer bound. No vanilla perk at
these entry points tests the observer, so the result is the same as per pair. NPCs sneaking
against the player do not take their perks yet.

Quiet Casting sets Mod Spell Casting Sound Event to 0. The value is read as a factor on the
cast's action sound, so 0 silences it, which is what the perk text says. Whether the game also
changes the cast's sound is not known; OpenSky plays it unchanged.

## Activation

| Entry point | Id | Where |
| --- | --- | --- |
| Filter Activation | 74 | the use-key gate, before the lock check, activated reference bound as the target |
| Set Activate Label | 81 | the prompt label of the crosshair target, target bound |

A non-zero Filter Activation value blocks the press. No event follows, as for a locked door,
but no lock notice shows. Vanilla uses it to stop a werewolf opening doors and containers.

## Skill books

| Entry point | Id | Where |
| --- | --- | --- |
| Adjust Book Skill Points | 5 | the levels a first read of a skill book adds, book bound as the item |

A skill book raises its skill one level the first time it is read (UESP "Skyrim:Skill Books").
The entry point starts at 1; the Black Book reward adds 1. The read mark is the spellbook's, so a
book counts once per save. The spellcasting panel's `Read skill book` button reads the first
unread one the player carries; there is no book menu yet.
