---
type: File Format
title: Race and class records
description: RACE and CLAS layouts, the skeleton blocks, starting attributes, regeneration, and
  per-level weights.
tags: [format, esm, actors, race, class]
---

# Race and class records (RACE, CLAS)

A race gives an actor its skeleton, default skin, starting attributes, and skill bonuses. A
class gives the weights that decide how an actor's stats grow per level. The stat math is on
the [actor values](/engine/actor-values.md) page.

Sources: UESP [RACE](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/RACE) and
[CLAS](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS); the Creation Kit wiki
[Race](https://ck.uesp.net/wiki/Race) page.

## RACE fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `WNAM` | FormID | Default skin armor, worn when the `NPC_` has no `WNAM` |
| `BOD2`, `BODT` | struct | Body template (see [armor records](/formats/armor.md)) |
| `DATA` | 128 or 164 bytes | Below |
| `MNAM`, `FNAM` | 0 bytes | Male and female markers that open gendered blocks |
| `ANAM` | zstring | Skeleton model path for the open gender |

Movement, spell lists, keywords, tints, and morphs are not read.

## Skeleton blocks

On `NordRace` the order is: `MNAM`, then the male `ANAM` and `MODT`; then `FNAM`, then the female
`ANAM` and `MODT`. Later `MNAM` and `FNAM` markers open other blocks, such as body models, but
those blocks have no `ANAM`. So an `ANAM` always belongs to the last marker. The first path for
each gender wins.

## RACE DATA

`DATA` is 128 bytes at form version 40 and 164 bytes at 43. OpenSky reads these parts:

| Offset | Type | Meaning |
| --- | --- | --- |
| `0x00` | uint8 x 14 + 2 | Seven skill and bonus byte pairs, then padding |
| `0x10` | float32 x 4 | Male and female height and weight. Not read |
| `0x20` | uint32 | Flags |
| `0x24` | float32 x 3 | Starting health, magicka, and stamina |
| `0x30` | float32 x 2 | Base carry weight, base mass |
| `0x38` | float32 | Movement, size, and biped data. Not read |
| `0x54` | float32 x 3 | Health, magicka, and stamina regeneration |
| `0x60` | float32 | Unarmed damage. The fields after it are not read |

Flags: `0x1` playable, `0x2` FaceGen head. Playable races have `0x2`. Creature races, such as
cow, dog, and bear, do not. This bit decides whether an actor has FaceGen files.

A skill pair with a bonus of 0 is dropped. A race that fills fewer than seven pairs leaves the
rest as zero, and a 0/0 pair would read as "+0 to Aggression". Example: `NordRace` gives
Two-Handed +10, and One-Handed, Block, Smithing, Light Armor, and Speech +5. UESP lists the same
bonuses.

Each part is read on its own. A `DATA` long enough for the starting values but not for
regeneration still gives the starting values.

Regeneration is a percentage of the maximum per second. The Creation Kit wiki says: "Health
Regen: The percentage of total Health that is regenerated each second". Every playable vanilla
race has 50/50/50 starting values, and regenerates 0.7, 3, and 5 percent per second. Every
playable race has carry weight 300, mass 1, and unarmed damage 4.

## CLAS fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Name |
| `DATA` | 36 bytes | Below |

The Swift type is `CharacterClass`, because `Class` reads badly in code.

## CLAS DATA (36 bytes)

| Offset | Type | Meaning |
| --- | --- | --- |
| `0x00` | uint32 | Unknown, "possibly flags". Not read |
| `0x04` | uint8 x 2 | Trainer skill and level. Not read |
| `0x06` | uint8 x 18 | Skill weights, one per skill (actor values 6 to 23) |
| `0x18` | float32 | Default bleedout |
| `0x1C` | uint32 | Voice points. Not read |
| `0x20` | uint8 x 3 | Health, magicka, and stamina weights |
| `0x23` | uint8 | Flags. UESP: "0x1 seems to indicate guard". Not read |

A short `DATA` gives zero weights, not an error. A class that adds no points per level is a
valid answer. Rejecting it would break every actor that names it.

A `CLAS` link resolves through the load order, like any other link. So a patch plugin can
override a class.
