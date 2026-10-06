---
type: File Format
title: Skyrim Save Papyrus Table
description: Global data table 1001 of a Skyrim SE save, the Papyrus script engine's state, and what OpenSky reads from it.
tags: [format, save, ess, papyrus]
---

# Skyrim save Papyrus table

Global data table type 1001 in the [save body](/formats/ess.md) holds the Papyrus script
engine's state: its strings, the scripts it loaded, every script instance with its
variables, arrays, and the stacks that were running.

Reference: UESP
[Save File Format/Papyrus](https://en.uesp.net/wiki/Skyrim_Mod:Save_File_Format/Papyrus).
Types are listed in [ESS](/formats/ess.md#basic-types).

## Strings and ids

| Field | Type |
| --- | --- |
| header | `uint16` |
| strCount | `uint16` |
| strings | `wstring` × strCount |

After this, every string is a `uint16` index into the table.

Object and array ids are 4 bytes in UESP. Some saves are said to use 8. OpenSky reads the
table with 4-byte ids first and, only if that fails, with 8-byte ids. The width that read
cleanly is kept and shown in the inspector.

## Sections in order

| Section | Layout |
| --- | --- |
| Scripts | `uint32` count. Each: name, parent name, `uint32` member count, members of name and type |
| Script instances | `uint32` count. Each: id, script name, 4 bytes, `refID` form, `uint8` |
| References | `uint32` count. Each: id, type name |
| Array info | `uint32` count. Each: id, `uint8` element type, a type name when the element type is 1, `uint32` length |
| Next active id | `uint32` |
| Active scripts | `uint32` count. Each: `uint32` id, `uint8` type |
| Script data | One block per instance, in instance order |
| Reference data | One block per reference, in reference order |
| Array data | Per array, in order: its id, then `length` values |
| Active script data | One per active script. See Stacks |
| Function messages, suspended stacks | See Stacks |

### Data blocks

An instance or reference block is: id, `uint8` flag, type name, 4 bytes (8 when flag bit
`0x04` is set), `uint32` member count, then the values. The id must match the list entry
it belongs to; a mismatch is an error.

### Values

| Type | Name | Data |
| --- | --- | --- |
| 0 | Null | 4 bytes |
| 1 | Object | type name, id |
| 2 | String | string index |
| 3 | Int | `int32` |
| 4 | Float | `float32` |
| 5 | Bool | `uint32`, nonzero is true |
| 11 | Object array | type name, id |
| 12 to 15 | String, int, float, bool array | id |

Array element types in the array info are 1 object, 2 string, 3 int, 4 float, 5 bool.

A script lists its own members. An instance's values come in member order: first those of
the script itself; when the count equals the whole parent chain, the parents' members come
first. OpenSky names the values that way and drops an instance whose count fits neither.

## Stacks

An active stack is a script that was running a function when the game saved. Its data holds
frames with the function's opcodes and arguments. OpenSky reads this data only to count the
stacks and name the script each one runs. It never runs them: OpenSky's VM cannot resume
another VM's half-run function.

A frame is read up to its opcodes. Each opcode's argument count comes from the Papyrus
opcode table; a call opcode adds a variadic count. A stack owner of type `QuestStage`,
`ScenePhaseResults`, `SceneActionResults`, or `SceneResults` has a fixed tail.

Where UESP leaves the layout open, the stack read stops and the table records
`partial(blockedBy:)` for the stacks only. Scripts, instances, and variables read before
it stay complete.

## Confirmed on real data

Not yet: see [ESS](/formats/ess.md#confirmed-on-real-data). The first real-data run must
check the id width and how often the stack read stops early.
