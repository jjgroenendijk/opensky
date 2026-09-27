---
type: File Format
title: Actor value information
description: AVIF record layout - names, the AVSK skill use values, and the perk tree node
  list - and how a record is matched to an actor value number.
tags: [format, esm, progression, skills, perks, record]
---

# Actor value information (AVIF)

An `AVIF` record describes one actor value, for example `OneHanded` or `Health`. It gives
the name, the abbreviation, and the description. For the 18 skills it also gives the skill
use values and the perk tree: where each perk box sits and how the boxes connect.

`AVIF` has no number of its own. The actor value numbers that conditions, scripts, and saves
use are listed in [actor values](/engine/actor-values.md). A record is matched to a number by
name, as described below.

## Sources

- UESP [AVIF](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AVIF), with its "Perk
  Sections" table and its notes on the `ANAM` and `CNAM` quirks.
- xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`,
  `wbRecord(AVIF, 'Actor Value Information', [...])`: the field order, the `CNAM` values,
  and the `wbRArray('Perk Tree', wbRStruct('Node', [...]))` shape.

Where the two disagree, OpenSky keeps both readings. See `AVSK` below.

## Record fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID. Most vanilla IDs start with `AV` |
| `FULL` | lstring | Name in the game |
| `DESC` | lstring | Description. xEdit says required, but a record without it still decodes |
| `ICON` | zstring | Image path for the editor |
| `ANAM` | zstring | Abbreviation. Rarely set |
| `CNAM` | uint32 | Skill category, or something else. See below |
| `AVSK` | 4 x float32 | Skill use values. Only on records with a perk tree |
| perk tree | node list | Repeated node fields, below |

Skill categories: 0 none, 1 combat, 2 magic, 3 stealth. OpenSky keeps the raw value too.

## AVSK

16 bytes, four little-endian float32 values:

| Offset | Name |
| --- | --- |
| 0x00 | Skill use multiplier |
| 0x04 | Skill use offset |
| 0x08 | Skill improve multiplier |
| 0x0C | Skill improve offset |

The sources disagree on the second value. UESP calls it "Skill Use Offset", and xEdit calls
it "Skill Offset Mult". OpenSky uses the UESP name and does not guess which is right. An
`AVSK` that is not exactly 16 bytes is skipped, and the rest of the record still decodes.

## Perk tree nodes

The tree is a flat list of fields, not an array with a size. Each node starts at `PNAM` and
runs to the next `PNAM` or the end of the record.

| Field | Type | Meaning |
| --- | --- | --- |
| `PNAM` | FormID | The `PERK` this box gives. Null on the entry node |
| `FNAM` | uint32 | xEdit: "Parent Required". UESP: the first node often has a very large value |
| `XNAM` | uint32 | Grid column |
| `YNAM` | uint32 | Grid row |
| `HNAM` | float32 | Horizontal offset inside the grid cell |
| `VNAM` | float32 | Vertical offset inside the grid cell |
| `SNAM` | FormID | The `AVIF` this node belongs to. Normally this record |
| `CNAM` | uint32 | A line from this box to the node with that `INAM`. Zero or more |
| `INAM` | uint32 | This box's ID in the tree. Unique, but not in sequence |

The entry node (null `PNAM`, `INAM` 0) is not a drawn box. Its numbers show the quirk UESP
describes: on `AVMysticism` in `Skyrim.esm` it has `XNAM` 14824284 and `FNAM` 0. Nothing
reads these values, so OpenSky keeps them as they are.

Lines point at `INAM` values, not at list positions. The grid only says where a box is drawn.
It does not say what a perk needs. The needs are the conditions of the `PERK` record (see
[perks](/formats/perks.md)).

## CNAM has two meanings

Before the first `PNAM`, `CNAM` is the skill category of the record. After a `PNAM`, it is a
line of the open node. Only the position tells them apart. So the decoder must track which
node is open. UESP says the same. It adds that on a record with no perk tree, `CNAM` seems to
hold "large 4byte info", not a category. In vanilla, 91 records have a `CNAM` outside 0 to 3,
and all of them have no perk tree.

## Matching a record to an actor value number

OpenSky tries these names in order against the table in
[actor values](/engine/actor-values.md):

1. The editor ID as written.
2. The editor ID without a leading `AV`. Vanilla writes `AVOneHanded`.
3. The `FULL` name, when it is inline text.

`FULL` comes last because a localized plugin stores a string ID there, not text. The match
ignores case and punctuation, so `One-Handed`, `OneHanded`, and `one handed` are one name. A
record that matches nothing, such as a new actor value from a mod, gets no number but is
still stored.

Three vanilla skills use old Oblivion words in their editor IDs and match nothing. OpenSky
maps them by hand. The mapping comes from each record's own `FULL` string in the
`Skyrim.esm` string table:

| Editor ID | `FULL` text | Index |
| --- | --- | --- |
| `AVMarksman` | Archery | 8 |
| `AVSpeechcraft` | Speech | 17 |
| `AVMysticism` | Illusion | 21 |

These aliases apply only to `AVIF` records. They do not change how condition parameters and
script functions look up actor value names.

## Perk trees that are not skills

In vanilla (five masters), 20 records have a perk tree. 18 are the skills, and they match
exactly the actor value numbers 6 (`One-Handed`) to 23 (`Enchanting`). The other two are
Dawnguard's vampire and werewolf trees. They hang on `AVMagickaRateMod` and
`AVHealRatePowerMod`, which are not skills. So "has a perk tree" and "is a skill" are
different questions.

## Errors

- A record of another type is an error.
- A broken or cut field is skipped and counted. The rest of the record still decodes.
- A node without a field that xEdit calls required is kept, with zeros, and counted.

All vanilla `AVIF` records decode with no broken fields and no incomplete nodes.
