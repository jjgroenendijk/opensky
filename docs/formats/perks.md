---
type: File Format
title: Perks
description: PERK record layout - the header, effect sections, entry points, and the EPFD
  function data - and what the vanilla data shows about them.
tags: [format, esm, progression, perks, conditions, record]
---

# Perks (PERK)

A `PERK` record is a perk the player picks, or a passive effect an actor has. It has a
header, conditions for when it can be taken, and a list of effects. An effect can set a
quest stage, give an ability spell, or hook an entry point. An entry point is a named place
in a game formula, for example "Mod Attack Damage", where the engine asks: "does anything
change this value?". Entry points connect perks to every other system. See
[perks at runtime](/engine/perks.md).

## Sources

- UESP [PERK](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PERK), with its "Perk
  Sections", "Perk Effect Types", and "Function Types" tables.
- xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`: `wbRecord(PERK, 'Perk', [...])` at line
  5908, the `wbPerkDATADecider` effect union, the `wbEPFDDecider` function data union, and
  `wbEntryPointsEnum` at line 2426.

OpenSky follows xEdit where they differ. xEdit lists all 92 entry points in order. UESP
sorts them by name and misses the last few. Both agree on every ID they both list.

## Record fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `VMAD` | struct | Scripts and fragments. See [VMAD](/formats/vmad.md) |
| `FULL` | lstring | Name |
| `DESC` | lstring | Description |
| `ICON` | zstring | Image path for the editor |
| `CTDA` | struct | Conditions to take the perk. See [conditions](/formats/conditions.md) |
| `DATA` | 5 x uint8 | Header, below |
| `NNAM` | FormID | Next rank of this perk. Null on the last rank |
| effects | sections | Repeated `PRKE` ... `PRKF` sections, below |

Header `DATA`:

| Offset | Type | Name |
| --- | --- | --- |
| 0x00 | uint8 | Is trait |
| 0x01 | uint8 | Minimum level |
| 0x02 | uint8 | Rank count |
| 0x03 | uint8 | Is playable |
| 0x04 | uint8 | Is hidden |

Each rank after the first is its own `PERK` record, linked through `NNAM`.

### The rank count and level bytes are not what they seem

`Armsman00` says rank count 1, but its `NNAM` chain has five records: `Armsman00`,
`Armsman20`, `Armsman40`, `Armsman60`, `Armsman80`. The byte and the chain disagree often
in vanilla. xEdit shows a count that matches the chain only because it recomputes it after
loading (`wbPERKNumRanksAfterLoad`).

The level byte is 0 on every vanilla record, even `Armsman80`, which needs One-Handed 80.
The skill need is a condition (`GetBaseActorValue`), not a header field.

So OpenSky keeps both bytes as they are and never trusts them. To find ranks, follow `NNAM`.
A mod can make `NNAM` loop, so the walk stops at a perk it has seen.

## Effect sections

Each effect starts with `PRKE` and ends with `PRKF`. `PRKE` is 3 bytes: type, rank,
priority. The rank counts from 0, so 0 is rank 1. The type sets the meaning of the `DATA`
inside the section:

| Type | Section | `DATA` |
| --- | --- | --- |
| 0 | Quest | `QUST` FormID, uint16 stage, 2 unused bytes with random values |
| 1 | Ability | `SPEL` FormID |
| 2 | Entry point | uint8 entry point, uint8 function, uint8 condition tab count |

An entry point section then has its conditions and its function data:

| Field | Type | Meaning |
| --- | --- | --- |
| `PRKC` | int8 | Starts a condition tab. The value says who the tab tests |
| `CTDA` | struct | A condition in the tab the last `PRKC` started |
| `EPFT` | uint8 | Shape of the `EPFD` data |
| `EPF2` | lstring | Button text. Only for "add activate choice" |
| `EPF3` | 2 x uint16 | Script flags (bit 0 run now, bit 1 replace default) and a fragment index |
| `EPFD` | varies | The function data, below |

The tab count in `DATA` need not match the tabs in the record. `Armsman40` says three for
Mod Attack Damage and has two. xEdit ignores the count when writing, because it is fixed per
entry point. OpenSky keeps both numbers and checks neither.

Who each `PRKC` index tests depends on the entry point: usually the perk owner, the target,
the attacker, the weapon, or the spell. The UESP "Perk Effect Types" table lists them.

## DATA and CTDA have two meanings

Before the first `PRKE`, `DATA` is the 5-byte header and `CTDA` is a condition to take the
perk. Inside a section, `DATA` is the section data and `CTDA` belongs to a condition tab.
Only the position tells them apart, so the decoder tracks the open section. The quest
decoder does the same (see [records](/formats/quest-records.md)).

## Functions

The second byte of an entry point `DATA` is the function: how the value changes.

| ID | Function | `EPFT` |
| --- | --- | --- |
| 1 | Set value | 1 |
| 2 | Add value | 1 |
| 3 | Multiply value | 1 |
| 4 | Add range to value | 2 |
| 5 | Add actor value mult | 2 |
| 6 | Absolute value | none |
| 7 | Negative absolute value | none |
| 8 | Add leveled list | 3 |
| 9 | Add activate choice | 4 |
| 10 | Select spell | 5 |
| 11 | Select text | 6 |
| 12 | Set to actor value mult | 2 |
| 13 | Multiply actor value mult | 2 |
| 14 | Multiply 1 + actor value mult | 2 |
| 15 | Set text | 7 |

The `EPFT` column is what each function should have. OpenSky reads the record's own `EPFT`,
so a record that disagrees still decodes as written.

## EPFD function data

| `EPFT` | Data |
| --- | --- |
| 0 | Unknown. Kept raw |
| 1 | float32 |
| 2 | float32, float32; or actor value, float32 factor (see below) |
| 3 | `LVLI` FormID |
| 4 | `SPEL` FormID, with `EPF2` and `EPF3` |
| 5 | `SPEL` FormID |
| 6 | zstring |
| 7 | lstring |

For `EPFT` 2, the function decides (xEdit `wbEPFDDecider`). Under functions 5, 12, 13, and
14, the first value is an actor value, not a plain float. The bytes alone cannot show this.
`EPFD` comes after the section's `DATA` in all vanilla records, but that is not guaranteed.
So OpenSky keeps `EPFD` raw until the section ends, then reads it. Data with the wrong
length for its shape stays raw.

### The actor value is stored as a float

The actor value in these four functions is a float that holds the index, not an integer.
UESP writes the data as "float AV, float FACTOR". xEdit's `wbEPFDActorValueToStr`
(`Core/wbDefinitionsTES5.pas` line 889) reads the uint32 as a float and rounds it.

Read as an integer, the value is a bit pattern. For example, `AlchemySkillBoosts` gives
1125187584 (`0x43120000`) instead of 146. OpenSky rounds the float to an integer index. A
value outside the int32 range becomes -1, the "no actor value" index.

## Errors

- A record of another type is an error. Nothing else is.
- A broken field is skipped and counted. The rest still decodes, including the effects.
- A section field (`PRKC`, `EPFT`, `EPF2`, `EPF3`, `EPFD`, `PRKF`) with no open section is
  counted.
- A `CTDA` in a section with no open tab is counted.
- A section without `PRKF` at the end of the record is kept and counted.
- An effect type, entry point, function, or `EPFT` outside the known values keeps its raw
  byte.

## Vanilla perks

In the five masters: 483 perks, all decode. They have 622 entry point effects, 32 ability
effects, and 28 quest effects. Every ability links to a real spell. 68 of the 92 entry points
are used. No perk is a trait. 46 are hidden and 34 are not playable.

The ten most used entry points cover more than half of all uses:

| Entry point | ID | Effects |
| --- | --- | --- |
| Mod Attack Damage | 35 | 81 |
| Mod Spell Magnitude | 29 | 61 |
| Apply Combat Hit Spell | 51 | 58 |
| Mod Spell Cost | 38 | 43 |
| Mod Armor Rating | 85 | 31 |
| Mod Incoming Damage | 36 | 23 |
| Mod Tempering Health | 76 | 21 |
| Activate | 14 | 19 |
| Mod Spell Duration | 30 | 17 |
| Mod Buy Prices | 8 | 15 |

The perk tree layout comes from `AVIF`, not from `PERK`. See
[actor value information](/formats/actor-value-information.md).
