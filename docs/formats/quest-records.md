---
type: File Format
title: Quest records
description: The QUST record - its order-dependent field groups for stages, log entries,
  objectives, and aliases, the alias fill types, and how bad input is handled.
tags: [format, esm, records, quests]
---

# Quest records (QUST)

A quest holds journal stages, objectives, and aliases. An alias is a named slot that the quest
fills with a world object, such as "the person to talk to". The stage scripts are not in the
record. They are in the `QUST` part of `VMAD` (see [VMAD](/formats/vmad.md)). Quest state is on
the [runtime state](/engine/runtime-state.md) page.

Sources: UESP [QUST](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/QUST); xEdit
`dev-4.1.6` `wbDefinitionsTES5.pas` `wbRecord(QUST, 'Quest', ...)`: `DNAM` at line 8763, stages
at 8797, objectives at 8840, reference aliases at 8869, location aliases at 8971.

## Field order matters

`QUST` depends on field order more than any other record. Few of its fields are a complete
struct. Instead, a marker field opens a group, and every field after it belongs to that group
until the next marker. Three such groups follow each other, and two separator fields control
the rest.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `VMAD` | varies | Scripts, with the quest fragment part |
| `FULL` | lstring | Name |
| `DNAM` | 12 bytes | uint16 flags, uint8 priority, uint8 form version, 4 unused, uint32 type |
| `ENAM` | 4 chars | Story manager event name |
| `QTGL` | FormID, repeats | Globals shown in journal text |
| `FLTR` | zstring | Creation Kit folder |
| `CTDA` | 32 bytes | Dialogue conditions before `NEXT`, story manager conditions after it |
| `NEXT` | empty | Separates the two condition runs |
| `INDX` | 4 bytes | Opens a stage: uint16 index, uint8 flags, 1 unused |
| `QSDT` | uint8 | Opens a log entry in the stage. Flags: `0x01` complete, `0x02` fail |
| `CNAM` | lstring | The log entry's journal text |
| `NAM0` | FormID | The log entry's next quest |
| `QOBJ` | uint16 | Opens an objective, and ends the stages |
| `FNAM` | uint32 | The objective's flags. `0x01`: OR with the previous one |
| `NNAM` | lstring | The objective's text. See below |
| `QSTA` | 8 bytes | Opens an objective target: int32 alias, uint8 ignores locks, 3 unused |
| `ANAM` | uint32 | Next alias ID. Ends the objectives and starts the aliases |
| `ALST`, `ALLS` | uint32 | Opens a reference alias or a location alias |
| `ALED` | empty | Closes the alias |

## Fields with two meanings

Inside an alias, some field names mean something else. `FNAM` is the alias flags. `CTDA` is the
alias's own match conditions. `KSIZ` and `KWDA` are keywords, and `COCT` and `CNTO` are items,
given to the alias target while the quest runs. So the decoder gives every field to the open
alias first.

`NNAM` is an lstring objective text inside the objectives. After `ANAM` it is a plain zstring
quest description. `QSTA` after `ANAM` is an old record-level target, whose value is a reference
FormID, not an alias ID. Vanilla `Skyrim.esm` has none.

## Alias fill types

The Creation Kit shows one "fill type" per alias. On disk, the type follows from which fields
are present. The decoder reads each field into its own property, and works out the fill type
afterwards, in the Creation Kit's order.

| Fill type | Fields | For |
| --- | --- | --- |
| Specific reference | `ALFR` | Reference |
| Unique actor | `ALUA` | Reference |
| Specific location | `ALFL` | Location |
| Location alias reference | `ALFA` + `ALRT` | Reference |
| Reference alias location | `ALFA` + `KNAM` | Location |
| External alias | `ALEQ` + `ALEA` | Both |
| Create reference to object | `ALCO` + `ALCA` + `ALCL` | Reference |
| Near alias | `ALNA` + `ALNT` | Reference |
| From event | `ALFE` + `ALFD` | Both |
| None | - | Filled by script, by `ALFI`, or by conditions alone |

Vanilla uses every fill type in this table.

## Bad input

- A field with the wrong size costs only its own entry.
- A field that arrives with no group open costs only itself.
- An alias with no closing `ALED` is kept, and counted.
- An unknown field is skipped.

Each case is counted, so a sweep can check for zero. Only a record that is not `QUST` throws.

Vanilla has no bad cases. The only skipped fields are `SCHR`, `SCTX`, and `QNAM` in log entries.
An older Creation Kit wrote them, and xEdit marks them unused.

Three links prove the groups are read right. In vanilla, every objective target names an alias
its own quest has. Every fragment names a stage its own quest has. Every alias script section
names its own quest.

`openskycli record --type QUST` and the Asset Browser show a quest's name, type, priority,
flags, and its numbers of stages, objectives, aliases, and fragments.
