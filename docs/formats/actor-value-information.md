---
type: File Format
title: Actor value information
description: AVIF record layout (names, AVSK skill-use values, the perk-tree node run), the
  CNAM double meaning, and how a record is matched to an actor value index.
tags: [format, esm, progression, skills, perks, record]
---

# Actor value information (AVIF)

An `AVIF` record describes one actor value: its name, abbreviation, and description. For the
18 skills it also says how using the skill turns into skill experience, and where each perk
box sits in the skill's perk tree.

`AVIF` has no index of its own. The numbers used by conditions, script functions, and saves
come from [actor values](/engine/actor-values.md). A record is matched to a number by name,
as described in "Matching a record to an index" below.

Sources:

- UESP [AVIF](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/AVIF), including its "Perk
  Sections" table and its notes on `ANAM` and `CNAM`.
- xEdit `dev-4.1.6` `Core/wbDefinitionsTES5.pas`, `wbRecord(AVIF, ...)`: field order, `CNAM`
  values, and the `wbRArray('Perk Tree', wbRStruct('Node', [...]))` shape.

## Record fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID. Most vanilla IDs start with `AV` |
| `FULL` | lstring | Name in the game |
| `DESC` | lstring | Description. xEdit says required, but OpenSky accepts a record without it |
| `ICON` | zstring | Image path for the editor |
| `ANAM` | zstring | Abbreviation. Usually absent |
| `CNAM` | uint32 | Skill category, or something else. See "CNAM has two meanings" |
| `AVSK` | float32 x 4 | Skill-use values. Only on records with a perk tree |
| perk tree | fields | A run of node fields, below |

`CNAM` categories: 0 none, 1 combat, 2 magic, 3 stealth. OpenSky keeps the raw value too.

## AVSK

16 bytes, four little-endian floats. [Skill advancement](/engine/skill-advancement.md) uses
them.

| Offset | Type | Name |
| --- | --- | --- |
| 0x00 | float32 | Skill use multiplier |
| 0x04 | float32 | Skill use offset |
| 0x08 | float32 | Skill improve multiplier |
| 0x0C | float32 | Skill improve offset |

The sources disagree on the second float. UESP says "Skill Use Offset". xEdit says "Skill
Offset Mult". OpenSky uses the UESP name and does not pick a side.

An `AVSK` that is not exactly 16 bytes is counted as malformed and ignored. The rest of the
record still decodes.

## Perk-tree nodes

The tree is a flat run of fields, not a sized list. Each node starts with `PNAM` and ends at
the next `PNAM` or the end of the record.

| Field | Type | Meaning |
| --- | --- | --- |
| `PNAM` | FormID | The `PERK` this box grants. Null on the entry node |
| `FNAM` | uint32 | xEdit: "Parent Required", a Boolean. Kept raw, see below |
| `XNAM` | uint32 | Grid column |
| `YNAM` | uint32 | Grid row |
| `HNAM` | float32 | Horizontal offset inside the grid cell |
| `VNAM` | float32 | Vertical offset inside the grid cell |
| `SNAM` | FormID | The `AVIF` this node belongs to. Usually the record itself |
| `CNAM` | uint32 | A line from this box to the node with that `INAM`. Zero or more |
| `INAM` | uint32 | This box's ID in the tree. Unique, but not in sequence |

The entry node has a null `PNAM` and `INAM` 0. It is bookkeeping, not a drawn box. UESP warns
that the first node often has very large values. Example: on `AVMysticism` in `Skyrim.esm`
the entry node has `XNAM` 14824284 and `FNAM` 0. OpenSky reads these values as they are and
does not use them.

Lines point at `INAM` values, not list positions. The grid only says where a box is drawn.
It says nothing about cost or requirements. Requirements are conditions on the `PERK`
record.

## CNAM has two meanings

Before the first `PNAM`, `CNAM` is the skill category of the record. After a `PNAM`, it is a
line from the open node. Only position tells them apart. So the decoder must track which node
is open.

UESP adds that on records without a perk tree, the record-level `CNAM` seems to hold
something else ("large 4byte info"). This matches vanilla: many records have a `CNAM` outside
0 to 3, and none of them has a perk tree. So OpenSky never reads a category from a value that
is not one.

## Matching a record to an index

OpenSky matches a record to the actor-value table by name, trying in order:

1. The editor ID.
2. The editor ID without a leading `AV`. Example: `AVOneHanded` becomes `OneHanded`.
3. The `FULL` name, if it is inline text.

`FULL` comes last, because a localized plugin stores it as a string-table ID, not text. The
compare ignores punctuation and case, so `One-Handed`, `OneHanded`, and `one handed` match.
A record that matches no vanilla name, such as a mod's new actor value, has no index but is
still stored.

Three vanilla skills use old Oblivion words in their editor IDs, so all three tries fail.
OpenSky maps them with an alias table. Each alias was confirmed by resolving the record's own
`FULL` string in `Skyrim.esm`:

| Editor ID | `FULL` | Index |
| --- | --- | --- |
| `AVMarksman` | Archery | 8 |
| `AVSpeechcraft` | Speech | 17 |
| `AVMysticism` | Illusion | 21 |

The aliases apply only to record names. Condition parameters and script functions use a
separate lookup without them.

## Perk trees that are not skills

The 18 skills are exactly the records that match indices 6 (One-Handed) to 23 (Enchanting).
With Dawnguard loaded, two more records have perk trees: the vampire and werewolf trees, on
`AVMagickaRateMod` and `AVHealRatePowerMod`. These are not skills. So "has a perk tree" and
"is a skill" are different questions.

## Bad input

- A record that is not `AVIF` is an error.
- A malformed or short field is skipped and counted. Unknown fields are counted.
- A node missing a field that xEdit marks required is kept, with zeros, and counted.
- Vanilla has no malformed fields, no unknown fields, and no incomplete nodes.

## Inspecting

`openskycli record <editorid>` and the Asset Browser type "AVIF - Actor value information"
show the same summary: identity, matched index, category, the four `AVSK` values, and the
perk nodes, with perk names when [perks](/formats/perks.md) are loaded.
