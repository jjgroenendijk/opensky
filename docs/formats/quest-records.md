---
type: File Format
title: Quest records (QUST)
description: QUST layout — the grouped stage, objective, and alias runs, alias fill types,
  and what the vanilla quests contain.
tags: [format, plugin, records, quests]
---

# Quest records

A QUST holds a quest's journal stages, its objectives, and the aliases that point at world
objects. The stage scripts are not here. They are in the QUST part of `VMAD`
([VMAD](/formats/vmad.md)). Quest state at runtime is on
[runtime state](/engine/runtime-state.md). Shared decode rules are on
[record decoders](/formats/records.md).

Sources: UESP [`/QUST`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/QUST), and xEdit
`dev-4.1.6` `wbDefinitionsTES5.pas` `wbRecord(QUST, 'Quest', ...)` at line 8759: `DNAM`
8763, stages 8797, objectives 8840, reference aliases 8869, location aliases 8971.

## Field order

QUST depends on field order more than any other record. A marker field opens a group, and
every field after it belongs to that group until the next marker.

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `VMAD` | struct | scripts, with the quest fragment table |
| `FULL` | lstring | name |
| `DNAM` | 12 bytes | uint16 flags, uint8 priority, uint8 form version, 4 unused, uint32 type |
| `ENAM` | char[4] | story manager event |
| `QTGL` | FormID | global for text display; repeated |
| `FLTR` | zstring | Creation Kit folder |
| `CTDA` | 32 bytes | dialogue conditions before `NEXT`, story manager conditions after |
| `NEXT` | empty | separates the two condition runs |
| `INDX` | 4 bytes | opens a stage: uint16 index, uint8 flags, 1 unused |
| `QSDT` | uint8 | opens a log entry in the stage; flags `0x01` complete, `0x02` fail |
| `CNAM` | lstring | the log entry's journal text |
| `NAM0` | FormID | the log entry's next quest |
| `QOBJ` | uint16 | opens an objective and ends the stages |
| `FNAM` | uint32 | the objective's flags (`0x01` ORed with previous) |
| `NNAM` | lstring | the objective's display text |
| `QSTA` | 8 bytes | opens an objective target: int32 alias, uint8 ignores locks, 3 unused |
| `ANAM` | uint32 | next alias ID; ends the objectives and starts the aliases |
| `ALST` / `ALLS` | uint32 | opens a reference alias / location alias |
| `ALED` | empty | closes the alias |

A quest with `DNAM` type 0 does not appear in the journal. Vanilla runs many type-0
controller quests.

Inside an alias, some names mean something else: `FNAM` is alias flags, `CTDA` is the
alias's match conditions, and `KSIZ`/`KWDA` and `COCT`/`CNTO` are keywords and items given to
the alias target while the quest runs. So a field goes to the open alias first.

`NNAM` has two meanings. Inside the objectives, it is an lstring with the objective text.
After `ANAM`, it is a plain zstring with the quest description. `QSTA` after `ANAM` is an old
record-level target whose word is a reference FormID, not an alias ID. `Skyrim.esm` has none.

The journal text tables: quest `FULL` and objective `NNAM` come from `.strings`, and the
stage `CNAM` text comes from `.dlstrings` ([strings](/formats/strings.md)).

## Alias fill types

The Creation Kit shows one "fill type" per alias. On disk, the type follows from which
fields are present. The table uses the Creation Kit's order:

| fill type | fields | alias kind |
| --- | --- | --- |
| specific reference | `ALFR` | reference |
| unique actor | `ALUA` | reference |
| specific location | `ALFL` | location |
| location alias reference | `ALFA` + `ALRT` | reference |
| reference alias location | `ALFA` + `KNAM` | location |
| external alias | `ALEQ` + `ALEA` | both |
| create reference to object | `ALCO` + `ALCA` + `ALCL` | reference |
| near alias | `ALNA` + `ALNT` | reference |
| from event | `ALFE` + `ALFD` | both |
| none | none | filled by script, by `ALFI`, or by conditions |

## Decode rules

A field of the wrong size is dropped. A field that arrives with no open group is dropped.
An alias without `ALED` is kept. `SCHR`, `SCTX`, and `QNAM` inside a log entry are old
fields that xEdit marks unused (`wbUnused(SCHR/SCTX/QNAM)`); the log entry keeps them as raw
bytes.

## Vanilla quests

In `Skyrim.esm`:

| measure | value |
| --- | --- |
| quests | 1,811 |
| stages / with journal text | 5,220 / 726 |
| log entries / with `CNAM` text | 5,294 / 771 |
| objectives / objective targets | 1,452 / 1,808 |
| aliases (reference / location) | 12,891 (11,999 / 892) |
| fragment tables / stage fragments / alias script sections | 856 / 5,108 / 2,149 |
| legacy log entry fields | 53, all `SCHR`, `SCTX`, or `QNAM` |
| conditions / different function indices | 11,427 / 90 |

No quest repeats an alias ID. Every objective target names an alias of its own quest, every
fragment names a stage of its own quest, and every alias script section names its own quest.
This confirms that the groups are read correctly.

Fill types used: unique actor 2,900, specific reference 2,687, from event 2,065, none 2,062,
location alias reference 2,036, create reference to object 630, near alias 218, specific
location 162, external alias 83, reference alias location 48. Vanilla uses every fill type.

Simple quests with journal text and stage fragments include `MGRArniel01` (`0006A086`: 2
stages, 1 objective, 1 forced-reference alias, 2 fragments, no conditions), `DBEviction`
(`0006F9A5`), and `TGCrownMisc` (`0006D585`).
