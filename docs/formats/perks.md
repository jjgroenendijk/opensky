---
type: File Format
title: Perks
description: PERK layout (header, effect sections, entry points, EPFD function data), the two
  meanings of DATA, and header bytes that do not mean what they seem.
tags: [format, esm, progression, perks, conditions, record]
---

# Perks (PERK)

A `PERK` record is behind every perk the player picks and every passive bonus an actor has. It
is a header, availability conditions, and a list of effects. An effect can set a quest stage,
grant an ability spell, or hook an entry point.

An entry point is a named place in a game formula where the engine asks "does anything change
this value?". Example: Mod Attack Damage. Entry points connect perks to every other system. So
what a perk can do at runtime depends on how well this record is decoded. The runtime is on the
[perks](/engine/perks.md) page.

Sources:

- UESP [PERK](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PERK), with its "Perk
  Sections", "Perk Effect Types", and "Function Types" tables.
- xEdit `dev-4.1.6` `Core/wbDefinitionsTES5.pas`: `wbRecord(PERK, ...)` at line 5908,
  `wbPerkDATADecider`, `wbEPFDDecider`, and `wbEntryPointsEnum` at line 2426.

OpenSky follows xEdit where they differ. xEdit lists all 92 entry points in order. UESP sorts
them by name and misses the last few. They agree on every ID both name.

## Record fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `VMAD` | struct | Scripts. See [VMAD](/formats/vmad.md) |
| `FULL` | lstring | Name |
| `DESC` | lstring | Description |
| `ICON` | zstring | Image path for the editor |
| `CTDA` | struct | Availability conditions. See [conditions](/formats/conditions.md) |
| `DATA` | uint8 x 5 | Header, below |
| `NNAM` | FormID | Next rank of this perk. Null on the last rank |
| effects | sections | `PRKE` ... `PRKF` sections, below |

Header `DATA`:

| Offset | Type | Name |
| --- | --- | --- |
| 0x00 | uint8 | Is trait |
| 0x01 | uint8 | Minimum level |
| 0x02 | uint8 | Rank count |
| 0x03 | uint8 | Is playable |
| 0x04 | uint8 | Is hidden |

Each rank after the first is its own `PERK` record, linked through `NNAM`.

## Header bytes that do not mean what they seem

The rank count is not the length of the `NNAM` chain. `Armsman00` says rank count 1, but its
chain has five records: `Armsman00`, `Armsman20`, `Armsman40`, `Armsman60`, `Armsman80`. Many
records disagree like this. xEdit shows a matching count only because it recomputes it after
loading (`wbPERKNumRanksAfterLoad`).

The level byte is 0 on every vanilla record, even `Armsman80`, which the game offers only at
One-Handed 80. The requirement is a condition (`GetBaseActorValue`), not a header field.

OpenSky keeps both bytes as they are and does not use them for rank or level logic.

## Effect sections

Each effect starts with `PRKE` and ends with `PRKF`. `PRKE` is three bytes: type, rank,
priority. The rank counts from 0, so 0 is rank 1. The type decides what `DATA` inside the
section means:

| Type | Section | `DATA` |
| --- | --- | --- |
| 0 | Quest | `QUST` FormID, uint16 stage, two unused bytes with random content |
| 1 | Ability | `SPEL` FormID |
| 2 | Entry point | uint8 entry point, uint8 function, uint8 condition tab count |

An entry-point section then holds:

| Field | Type | Meaning |
| --- | --- | --- |
| `PRKC` | int8 | Starts a condition tab. The value says which subject the tab tests |
| `CTDA` | struct | A condition in the tab the last `PRKC` started |
| `EPFT` | uint8 | Shape of `EPFD` |
| `EPF2` | lstring | Button label. Only for "add activate choice" |
| `EPF3` | uint16 x 2 | Script flags (bit 0 run immediately, bit 1 replace default) and a VMAD fragment index |
| `EPFD` | varies | Function parameters, below |

The declared tab count and the real tabs can differ. `Armsman40` declares three tabs for Mod
Attack Damage and has two. xEdit ignores the count on write, because each entry point has a
fixed count. OpenSky keeps both numbers.

The subject of each tab index depends on the entry point: usually perk owner, target, attacker,
weapon, or spell. UESP's "Perk Effect Types" table lists them.

## DATA and CTDA have two meanings

Before the first `PRKE`, `DATA` is the five-byte header, and `CTDA` is an availability
condition. Inside a section, `DATA` is the section's payload, and `CTDA` belongs to a tab. So
the decoder must track whether a section is open.

## Entry points and functions

An entry point is kept as its raw ID, with a name from the 92-entry xEdit table. An unknown ID
survives decoding.

The function says how the value changes:

| ID | Function | Expected `EPFT` |
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

OpenSky reads the record's own `EPFT`, not the expected one, so a record that disagrees still
decodes as written.

## EPFD function data

| `EPFT` | Data |
| --- | --- |
| 0 | Unknown. Kept raw |
| 1 | float32 |
| 2 | float32, float32; or actor value, float32 factor |
| 3 | `LVLI` FormID |
| 4 | `SPEL` FormID, with `EPF2` and `EPF3` |
| 5 | `SPEL` FormID |
| 6 | zstring |
| 7 | lstring |

For `EPFT` 2, the function decides (xEdit `wbEPFDDecider`). Under functions 5, 12, 13, and 14
the first word is an actor value. The bytes cannot tell. So OpenSky keeps `EPFD` raw until the
section closes, then reads it using the function from the section's `DATA`.

A payload whose length does not fit its shape stays raw. The bytes stay visible.

## The EPFD actor value is a float

In those four functions, the actor-value word is a float that holds the index, not an integer.
UESP writes the payload as "float AV, float FACTOR". xEdit's `wbEPFDActorValueToStr`
(`Core/wbDefinitionsTES5.pas` line 889) reads a uint32, reinterprets it as a float, and rounds
it before the name lookup.

Example: `AlchemySkillBoosts` stores `0x43120000`. Read as an integer that is 1125187584. Read
as a float it is 146.0, the actor value index 146. OpenSky rounds the float to an index. A value
outside the int32 range becomes -1, meaning "no actor value".

## Bad input

- A record that is not `PERK` is an error. Nothing else is.
- A broken field is skipped and counted. The effects still decode, because formulas still ask
  about a perk with a broken header.
- An effect field with no open section is counted.
- A `CTDA` in a section with no open tab is counted.
- A section with no `PRKF` at the end of the record is kept and marked unterminated.
- Unknown fields are counted.
- Every enum value (effect type, entry point, function, `EPFT`) keeps its raw byte when it is
  outside the known set.

## Lookups

Across the load order, OpenSky resolves ability and "select spell" links to `SPEL` records,
walks rank chains through `NNAM` (with a loop check and a depth limit), and builds one index of
all entry-point effects keyed by entry-point ID and sorted by `PRKE` priority. A formula that
asks "which effects hook Mod Attack Damage?" does one lookup.

`openskycli record <editorid>` and the Asset Browser type "PERK - Perks" show the header,
conditions, and each effect with its data and condition tabs.

## Vanilla facts

- Every vanilla perk decodes, with no unknown fields, entry points, or functions.
- No perk is a trait.
- 68 of the 92 entry points are used. The most used are Mod Attack Damage (35), Mod Spell
  Magnitude (29), Apply Combat Hit Spell (51), Mod Spell Cost (38), and Mod Armor Rating (85).
  The ten most used cover more than half of all hooks.
- Every ability link resolves to a `SPEL`.
- The `VMAD` fragment tail of a `PERK` is not decoded yet (see [VMAD](/formats/vmad.md)).
