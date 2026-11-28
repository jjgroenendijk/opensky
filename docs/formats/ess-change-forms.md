---
type: File Format
title: Skyrim Save Change Forms
description: The change form section of a Skyrim SE save, and which change types OpenSky decodes and writes.
tags: [format, save, ess]
---

# Skyrim save change forms

A change form records how one form differs from its plugin record at save time: a moved
reference, a container's items, a quest's stages. The section follows global data table 2
in the [save body](ess.md).

Reference: UESP
[Save File Format/Change Form](https://en.uesp.net/wiki/Skyrim_Mod:ChangeFlags) and the
change form section of
[Save File Format](https://en.uesp.net/wiki/Skyrim_Mod:Save_File_Format). Types are listed
in [ESS](ess.md#basic-types).

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

A decoder reads the documented parts in order. When a flag's data has no documented layout, the
decoder stops there and records why, as `partial(blockedBy:)`. Everything before the stop is kept.
Nothing after it is guessed.

## References

`REFR`, `ACHR`, and the other placed types. The flags are UESP's `CHANGE_REFR_*` and
`CHANGE_ACTOR_*` sets.

| Part | When | Layout |
| --- | --- | --- |
| Initial data | Created form (`refID` kind 2) | `refID` cell or worldspace, vector position, vector rotation, `uint8` flag, `refID` base object |
| | Moved (0x2) or Havok moved (0x4) | `refID` space, vector position, vector rotation |
| | Also cell changed (0x8) or promoted (0x2000000) | then `refID` starting space and 4 bytes of cell offsets |
| Havok data | 0x4 | `vsval` count, then that many bytes. Skipped |
| Actor header | `ACHR` | `uint32` process level, `uint32` actor flags. Skipped |
| Form flags | 0x1 | `uint32` flags, `uint16` unknown. `0x800` disabled, `0x20` deleted, as in a plugin |
| Base object | 0x80 | `refID` |
| Scale | 0x10 | `float32` |
| Extra data | Any extra data flag | An extra data list, below. A running `TranslateTo` move is type 161 ([translation](../engine/papyrus-translation.md#a-move-in-a-save)) |
| Inventory | 0x20 or 0x8000000 | `vsval` count of items: `refID` item, `int32` count, `vsval` count of extra data lists |
| Animation | 0x10000000 | `vsval` length, then bytes. Skipped. Inside: a flag, then for each behaviour graph a count, the project name, and the graph state; then the number 42 (body slots), the third-person slots, and the first-person slots or a 0 when they are the same |

Rotation is in radians, as in a plugin's placement. An inventory count is a change against
the base container, so it can be negative.

### Actor data after the animation part

An actor has more data after the animation part, in this order. The process data comes first.
An actor with process level `0xFFFFFFFF` in its actor header has no AI process and writes no
process data. Process data has no length in front, and parts of it are not decoded
([actor process data](ess-actor-process.md)). So a decoder reads the parts below only
for an actor with no process. Any other `ACHR` with bytes left there is
`partial(blockedBy: "actor process data")`.

A refID here is the usual 3 bytes, and 3 zero bytes mean none.

| Part | Layout |
| --- | --- |
| Process data | Present when the process level is not `0xFFFFFFFF` |
| Unknown | `uint8` |
| Timers | 4 `float32`: update target, voice, time since the last update, dead-body check |
| Action | `int32` action, `float32` action timer, `int32` unknown |
| Emotion | `int32` type, `int32` value |
| Crime and combat | `int32` critical stage, `int32` thief crime stamp, `int32` the time combat last saw its target. With combat data, combat stops on load when this stamp plus a fixed time limit is past |
| Weight | `float32`, the `NPC_` weight (`NAM7`). A value other than the base's sets the base's weight on load |
| Killer | `refID` |
| Actor state | `uint16` (low 14 bits used); `uint8` each: sit or bed state (3 sitting, 7 in bed), fly state, life state (1 dying, 3 unconscious, 5 recycle, 7 essential down), knock state, attack state; then 9 flag bytes |
| Support | `refID`, the moving reference the actor stands on, or none |
| Spell casters | `uint8` mask of 4 casters. For each set bit: `uint32`, `refID` spell, `uint32`, `uint32`, `refID` target, `uint32`, `uint32`, `refID`, `uint32`, then a `vsval` length and that many bytes |
| Selected spells | 4 `refID`s, then the `refID` of the selected power |
| Health, magicka, stamina, voice | Actor values 24, 25, 26, and 38. Each: `uint32` 3, then `float32` permanent, temporary, and damage modifiers |
| Other actor values | `vsval` count of (`int32` index, `float32` base value), then `vsval` count of (`int32` index, 3 `float32` modifiers) |
| Added spells | `uint32` count of `refID` |
| Movement | `uint8` flag, then data with no length. Not decoded |
| More flags | `uint32` |
| Combat | `uint8` flag, then data with no length. Not decoded |
| Spell pairs | `uint32` count of (`refID` spell, `int32`) |
| Last part | `uint32` day of the last bribe or intimidation, `float32` underwater timer, `refID` dialogue branch, `uint8` flag |

The actor state's third byte is the life state. Values 1 (dying), 2 (dead), and 5 (recycle) mean
dead; 7 is essential down. A health damage modifier below zero is damage the actor still carries.
The movement and combat data have no known layout, so a decoder stops at the first set flag of the
two. Everything before them is decoded.

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
UESP does not say which bit is "locked". Real saves keep `XLOC` flag 0x04 (leveled) in the
byte, and the level is the authored one ([locks](../engine/locks.md#leveled-locks)).

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

## Writing

The writer encodes the parts the decoder reads, and sets each change flag from the fields
that are present. It writes version 74, stores the data uncompressed, and picks the
narrowest length size that holds it. A reference with a part it cannot write, such as an
extra data entry with no documented layout, is refused with a typed error.

- References: a created form's initial data; a move; for an actor, 8 zero bytes for the
  actor header; then form flags, base object, scale, extra data, and inventory.
- Actor base: form flags, faction ranks, the three spell lists, name, race (twice), face,
  and sex.
- Quests: flags, stages, and objectives. Topic infos: only the said-once flag.

[ESS export](../engine/ess-export.md) lists what is not confirmed.

## Confirmed on real data

Not yet: see [ESS](ess.md#confirmed-on-real-data). The first real-data run must
check the reference initial data for each initial type, and which extra data types stop
lists most often.
