---
type: File Format
title: OpenSky save chunks — world and scripts
description: Payload layouts of the GVAR, CLOK, PSCR, PTMR, INVN, SPWN, QSTS, QALS, and
  QLOC chunks in an .osav save.
tags: [format, save, world-state, papyrus, inventory, quests]
---

# OpenSky save chunks: world and scripts

These chunks hold world, script, inventory, and quest state in an `.osav` file. The
container, the key and cell encodings, and the error rules are on
[OpenSky save](/formats/opensky-save.md). Actor chunks are on
[save chunks: actors](/formats/opensky-save-actor-chunks.md).

Rules for every chunk on this page:

- A list chunk starts with a uint32 entry count.
- "key" and "cell" are the tagged encodings from `RDLT`.
- A session with nothing to write for a chunk writes no chunk. A file without the chunk
  restores the plugin state.
- Entries are sorted, so the same state gives the same bytes.
- Each count is checked against a minimum entry size before memory is reserved.

## GVAR: globals

One entry per changed global: the GLOB record's key, then uint8 type (0 short, 1 long, 2
float) and float32 value, already fitted to the type. The type is stored, not read from the
plugin, so the save can be read without the game. An unknown type is `invalidValue`.

## CLOK: game clock

Exactly 8 bytes: float64 `totalGameSeconds`, game seconds since the calendar start
([game clock](/engine/game-clock.md)). A value that is not finite, or is negative, is
`invalidValue`. Without `CLOK`, the clock starts at the vanilla start date.

## PSCR: script instances

A uint32 instance count, then per instance: the key of the reference the script is attached
to, then:

| type | field | notes |
| --- | --- | --- |
| string | scriptName | lowercase |
| string | activeState | as the script spells it |
| uint8 | firedOnInit | 0 or 1: `OnInit` already sent |
| uint32 | variableCount | variables that follow |

Each variable: string declaring script (lowercase), string name (lowercase), uint8 value
tag, then the value:

| tag | kind | payload |
| --- | --- | --- |
| 0 | none | nothing |
| 1 | boolean | one byte, 0 or 1 |
| 2 | integer | int32 |
| 3 | float | float32 |
| 4 | string | uint16 length + UTF-8 |

Object handles and arrays are written as `none`. The running VM gives them their identity,
and it means nothing after a reload. So a restored script sees its compiled default
([Papyrus VM](/engine/papyrus-vm.md)). An unknown value tag is `invalidValue`. A float that
is NaN or infinite is read as 0.0, because a mod script can divide by zero. Minimum sizes:
16 bytes per instance, 5 bytes per variable.

## PTMR: update timers

One entry per armed timer slot: the instance's reference key, then:

| type | field | notes |
| --- | --- | --- |
| string | scriptName | lowercase |
| uint8 | slot | 0 real-time repeating, 1 real-time once, 2 game-time repeating, 3 game-time once |
| float64 | interval | the registered interval |
| float64 | remaining | time left when the save was written |

Real-time slots use seconds; game-time slots use game hours. `remaining` is relative to the
save, not an absolute time, so time between saving and loading does not count. The slot
byte is the raw value of `PapyrusUpdateTimerSlot`
([Papyrus VM](/engine/papyrus-timers.md)). A slot above 3 is `invalidValue`. An
interval or remaining time that is negative or not finite is read as 0.0, so the timer fires
on the next step. Minimum entry size: 26 bytes.

## INVN: inventories

One entry per owner whose items differ from the plugins:

| type | field | notes |
| --- | --- | --- |
| key | key | the owner |
| cell | cell | where the owner was when it changed |
| uint32 | stackCount | stacks that follow |
| bytes | stacks | per stack: uint32 item FormID, int32 count |
| uint32 | equippedCount | equipped items that follow |
| bytes | equipped | uint32 FormID each |

One row per item. Stolen and honest copies are added together here; the stolen part is in
`STOL` ([actor chunks](/formats/opensky-save-actor-chunks.md)). A flag cannot be added to
these rows, because the rows have no length and an older build would misread the whole
chunk.

Stacks are sorted by FormID and equipped items ascend. A stack with a count of zero or less
is dropped. Two stacks of one item are added together, stopping at the maximum instead of
overflowing. Minimum sizes: 16 bytes per entry, 8 per stack, 4 per equipped item.

## SPWN: spawned references

One entry per object the game placed, such as a dropped item:

| type | field | notes |
| --- | --- | --- |
| key | key | the generated key |
| uint32 | base | FormID of the base record |
| cell | cell | where the object is |
| float32 x 3 | position | game units |
| float32 x 3 | rotation | radians |
| float32 | scale | as `XSCL` |
| int32 | count | stack size |

The cell is where the object is, not where it last changed. An absent cell is
`invalidValue`, because an object with no cell is not in the world. A count below 1, or a
scale that is not a positive finite number, becomes 1. Minimum entry size: 48 bytes.

## QSTS: quest state

One entry per quest whose state differs from the plugins:

| type | field | notes |
| --- | --- | --- |
| key | key | the QUST record |
| uint8 | flags | bit 0 running, bit 1 completed |
| uint32 | stageCount | stages reached |
| uint16 | stage | one per `stageCount`, ascending |
| uint32 | objectiveCount | objectives that follow |
| bytes | objectives | per objective: uint16 index, uint8 flags (bit 0 displayed, bit 1 completed, bit 2 failed) |

These flags are OpenSky's own. They describe the session, not the QUST `DNAM`. A quest has no
cell, so there is no cell field. Repeated or unsorted stages are sorted. Unknown objective
flag bits are ignored, so a newer build can add one. Minimum sizes: 16 bytes per entry, 2
per stage, 3 per objective.

## QALS: reference aliases

One entry per quest with filled aliases: the QUST key, a uint32 fill count, then per fill a
uint32 alias ID (`ALST`/`ALLS` number) and the key of the filled reference. A key is stored,
not a FormID, because a FormID changes with the load order. Repeated or unsorted alias IDs
are sorted. A quest that is not in the chunk has empty aliases, which is the state of a
quest that has not started. Minimum sizes: 11 bytes per entry, 11 per fill.

## QLOC: location aliases

The same shape as `QALS`, for location aliases. It is a separate chunk because `QALS` rows
have no length, and an older reader would take location fills for the next quest. The key
must be a plugin key, because an LCTN is always a plugin record; a generated key is
rejected.

## SCNS: playing scenes

One entry per playing [scene](/engine/scenes.md). A scene that is not in the chunk is not
playing.

| type | field | notes |
| --- | --- | --- |
| key | key | the SCEN record |
| cell | cell | always "no cell" today |
| uint32 | phase | 0-based phase index |
| uint8 | entered | 1 when the phase was entered |
| uint32 | runningCount | running actions that follow |
| bytes | running | per action: uint32 index, float64 start in scene seconds, uint8 timed, float32 duration |
| uint32 | completedCount | completed actions that follow |
| uint32 | completed | one action index per `completedCount` |

A start time that is not finite is rejected. When `timed` is 0 the action has no end time and
the duration is ignored. Minimum sizes: 21 bytes per entry, 17 per running action.

## SMQS: story-manager starts

One entry per quest the [story manager](/engine/story-manager.md) started: the QUST key, the
cell, a float64 game-seconds time of the last start, and a uint32 start count. Reset times and
"do all before repeating" read them. A time that is not finite is rejected. Minimum size: 20
bytes per entry.

## DLBS: exclusive dialogue branches

One entry per speaker in an exclusive [dialogue](/engine/dialogue.md#branches) branch: the
speaker's key, the cell, and the uint32 FormID of the `DLBR`. The FormID is in the space of the
base plugin the dialogue store reads, which does not depend on the load order. Minimum size: 12
bytes per entry.

`SCNS`, `SMQS`, and `DLBS` merge into the `RDLT` deltas by key, like the other component
chunks.
