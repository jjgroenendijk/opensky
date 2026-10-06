---
type: File Format
title: Skyrim Save Change Forms
description: The change form section of a Skyrim SE save, and which change types OpenSky decodes for its import.
tags: [format, save, ess]
---

# Skyrim save change forms

A change form records how one form differs from its plugin record at save time: a moved
reference, a container's items, a quest's stages. The section follows global data table 2
in the [save body](/formats/ess.md).

Reference: UESP
[Save File Format/Change Form](https://en.uesp.net/wiki/Skyrim_Mod:ChangeFlags) and the
change form section of
[Save File Format](https://en.uesp.net/wiki/Skyrim_Mod:Save_File_Format). Types are listed
in [ESS](/formats/ess.md#basic-types).

## Envelope

| Field | Type | Notes |
| --- | --- | --- |
| formID | `refID` | The changed form |
| changeFlags | `uint32` | Which parts follow. The meaning depends on the type |
| type | `uint8` | Low 6 bits: the type index. Top 2 bits: the size of the two lengths, 0 = 1 byte, 1 = 2 bytes, 2 = 4 bytes |
| version | `uint8` | 74 in SE saves |
| length1 | 1, 2, or 4 bytes | Stored data length |
| length2 | 1, 2, or 4 bytes | Uncompressed length. Nonzero means the data is zlib compressed |
| data | length1 bytes | |

Length size bits 3 are an error. A compressed form inflates only when a decoder asks for
it, so listing and histograms stay cheap.

### Type index

| Index | Type | Index | Type | Index | Type |
| --- | --- | --- | --- | --- | --- |
| 0 | `REFR` | 17 | `LIGH` | 34 | `WOOP` |
| 1 | `ACHR` | 18 | `MISC` | 35 | `MGEF` |
| 2 | `PMIS` | 19 | `APPA` | 36 | `SMQN` |
| 3 | `PGRE` | 20 | `STAT` | 37 | `SCEN` |
| 4 | `PBEA` | 21 | `MSTT` | 38 | `LCTN` |
| 5 | `PFLA` | 22 | `FURN` | 39 | `RELA` |
| 6 | `CELL` | 23 | `WEAP` | 40 | `PHZD` |
| 7 | `INFO` | 24 | `AMMO` | 41 | `PBAR` |
| 8 | `QUST` | 25 | `KEYM` | 42 | `PCON` |
| 9 | `NPC_` | 26 | `ALCH` | 43 | `FLST` |
| 10 | `ACTI` | 27 | `IDLM` | 44 | `LVLN` |
| 11 | `TACT` | 28 | `NOTE` | 45 | `LVLI` |
| 12 | `ARMO` | 29 | `ECZN` | 46 | `LVSP` |
| 13 | `BOOK` | 30 | `CLAS` | 47 | `PARW` |
| 14 | `CONT` | 31 | `FACT` | 48 | `ENCH` |
| 15 | `DOOR` | 32 | `PACK` | | |
| 16 | `INGR` | 33 | `NAVM` | | |

The placed types (`REFR`, `ACHR`, the `P...` projectiles and hazards) share the reference
layout below.

## Decode status

A decoder reads the documented parts in order. When a flag's data has no documented layout,
the decoder stops there and records why, as `partial(blockedBy:)`. Everything before the
stop is kept. Nothing after it is guessed. The inspector shows a histogram per type: count,
compressed, complete, blocked with the reason, and failed.

## References

`REFR`, `ACHR`, and the other placed types. The flags are UESP's `CHANGE_REFR_*` and
`CHANGE_ACTOR_*` sets.

| Part | When | Layout |
| --- | --- | --- |
| Initial data | Created form (`refID` kind 2) | `refID` cell or worldspace, vector position, vector rotation, `uint8` flag, `refID` base object |
| | Moved (0x2) or Havok moved (0x4) | `refID` space, vector position, vector rotation |
| | Also cell changed (0x8) or promoted (0x2000000) | then `refID` starting space and 4 bytes of cell offsets |
| Havok data | 0x4 | `vsval` count, then that many bytes. Skipped |
| Actor header | `ACHR` | 8 bytes. Skipped |
| Form flags | 0x1 | `uint32` flags, `uint16` unknown. `0x800` disabled, `0x20` deleted, as in a plugin |
| Base object | 0x80 | `refID` |
| Scale | 0x10 | `float32` |
| Extra data | Any extra data flag | An extra data list, below |
| Inventory | 0x20 or 0x8000000 | `vsval` count of items: `refID` item, `int32` count, `vsval` count of extra data lists |
| Animation | 0x10000000 | `vsval` length, then bytes. Skipped |

Rotation is in radians, as in a plugin's placement. An inventory count is a change against
the base container, so it can be negative.

After the animation part an actor has more data: life state, packages, actor values,
perks. UESP does not document its layout. An `ACHR` with bytes left there is
`partial(blockedBy: "actor data after animation")`. So death, health, and perks are not
read from a save.

### Extra data list

A `vsval` count, then entries. Each entry is a `uint8` type and its data.

| Type | Name | Read as |
| --- | --- | --- |
| 22 | Worn | No data |
| 23 | WornLeft | No data |
| 33 | Ownership | `refID` owner |
| 36 | Count | `uint16` |
| 37 | Health | `float32` |
| 40 | Charge | `float32` |
| 42 | Lock | `uint8` level, `uint8` flags, `refID` key, 8 bytes |
| 136 | AliasInstanceArray | `vsval` count of `refID` quest and `uint32` alias id |
| 155 | Enchantment | `refID` enchantment, `uint16` charge |

Other types with a fixed size, a repeated fixed size, or a short variable layout in UESP
are skipped by size. The size tables live beside the reader. A type with no documented size
stops the list, and the change form becomes partial. Lock flags are kept but not mapped:
UESP does not say which bit is "locked".

## Actor base (`NPC_`)

Parts in this order, each present when its flag is set.

| Flag | Part | Layout |
| --- | --- | --- |
| 0x1 | Form flags | `uint32`, `uint16` |
| 0x2 | Base data | 24 bytes, the `ACBS` layout |
| 0x4 | Attributes | Undocumented. The decoder stops here |
| 0x40 | Factions | `vsval` count of `refID` faction and `int8` rank |
| 0x10 | Spell list | Three lists, each a `vsval` count of `refID`: spells, leveled spells, shouts |
| 0x8 | AI data | 20 bytes, the `AIDT` layout. Skipped |
| 0x20 | Full name | `wstring` |
| 0x200 | Skills | 52 bytes, the `DNAM` layout |
| 0x400 | Class | `refID` |
| 0x2000000 | Race | `refID` race, `refID` previous race |
| 0x800 | Face | `uint8` present. Then `refID` hair color, 4 bytes skin tone, `refID` skin, `vsval` count of head part `refID`s, `uint8` face data present, then `uint32` count of `float32` morphs and `uint32` count of `int32` presets |
| 0x1000000 | Gender | `uint8`, 1 female |
| 0x1000 | Default outfit | `refID` |
| 0x2000 | Sleep outfit | `refID` |

The player's base form is `Skyrim.esm` `0x7`. Its face block holds no tint layers.

## Quest (`QUST`)

| Flag | Part | Layout |
| --- | --- | --- |
| 0x1 | Form flags | `uint32`, `uint16` |
| 0x2 | Quest flags | `uint16` |
| 0x4 | Script delay | `float32` |
| 0x80000000 | Stages | `vsval` count of `int16` stage and `uint8` done |
| 0x20000000 | Objectives | `vsval` count of two `uint32`s. UESP does not name them |
| 0x10000000 | Run data | Read to find its end, not mapped |
| 0x8000000 | Instances | Read to find its end, not mapped |
| 0x4000000 | Already run | `uint8` |

`QUEST_SCRIPT` (0x40000000) has no documented data. A quest with bytes left after the
known parts is partial, blocked by `QUEST_SCRIPT` when that flag is set.

The quest flag bits OpenSky maps are `0x1` running and `0x2` completed. This follows the
plugin `QUST DNAM` flags and is not confirmed for saves.

## Topic info (`INFO`)

Flag `0x80000000` marks a line as said once. It carries no data.

## Confirmed on real data

Not yet: see [ESS](/formats/ess.md#confirmed-on-real-data). The first real-data run must
check the reference initial data for each initial type, and which extra data types stop
lists most often.
