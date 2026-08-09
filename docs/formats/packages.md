---
type: File Format
title: AI packages (PACK, PKID)
description: Skyrim SE PACK framing, schedules, package data, template links, procedures,
  and the bounded decode policy used by resident-actor AI.
tags: [format, plugin, ai, package, schedule, pack, pkid]
timestamp: 2026-08-09T00:00:00Z
---

# AI packages (PACK, PKID)

`PACK` records describe an actor's scheduled activity. An NPC_ names an ordered stack with
repeated `PKID` FormIDs; the first package whose calendar window and header conditions are
true wins. Template packages supply the procedure definition while the concrete package
supplies schedule, conditions, and bound data.

Decoder: `Package` and `PackageDecoder` under
`opensky/Engine/Formats/ESM/Records/`. Runtime use:
[package schedules](/engine/package-schedules.md). Shared condition layout:
[conditions](/formats/conditions.md).

## Contents

* [Sources and section framing](#sources-and-section-framing)
* [General data and schedule](#general-data-and-schedule)
* [Template and public data](#template-and-public-data)
* [Procedure tree](#procedure-tree)
* [Decode boundary](#decode-boundary)
* [Whiterun census](#whiterun-census)

## Sources and section framing

The byte layouts were checked against UESP's `PACK` page and xEdit dev-4.1.6
`wbDefinitionsTES5.pas`. Field names repeat with different meanings, so decoding is a
positioned walk rather than a flat field switch:

1. Header: `EDID`, `PKDT`, `PSDT`, VMAD, and the package's own condition run.
2. `PKCU` opens the public-data section.
3. `XNAM` opens the procedure tree.
4. `POBA`, `POEA`, or `POCA` begins the action-fragment tail.

Only CTDAs before `PKCU` belong to package selection. CTDAs inside the procedure tree are
branch-local and must not silently join the header condition list.

## General data and schedule

`PKDT` is exactly 12 bytes.

| offset | type | decoded value |
| --- | --- | --- |
| 0 | uint32 | flags |
| 4 | uint8 | kind: 18 package, 19 template, otherwise raw unknown |
| 5 | uint8 | interrupt override |
| 6 | uint8 | preferred speed: walk, jog, run, fast walk, or raw unknown |
| 7 | uint8 | skipped byte |
| 8 | uint16 | interrupt flags |
| 10 | uint16 | skipped word |

Named general flags are the subset consumed or useful to inspection: must complete,
maintain speed at goal, once per day, uses preferred speed, always sneak, ignore combat,
weapons unequipped, weapon drawn, and wear sleep outfit. Other bits remain in `rawValue`.

`PSDT` is exactly 12 bytes.

| offset | type | meaning |
| --- | --- | --- |
| 0 | int8 | month; -1 any, otherwise 1-based |
| 1 | int8 | weekday; -1 any, 0 Sundas through 6 Loredas, 7-10 groups |
| 2 | int8 | date; 0 any, otherwise 1-based day |
| 3 | int8 | start hour; -1 any |
| 4 | int8 | start minute; -1 means start of the hour |
| 5 | byte[3] | skipped |
| 8 | uint32 | duration in game minutes |

Weekday groups are weekdays (1-5), weekends (0 and 6), Morndas/Middas/Fredas, and
Tirdas/Turdas. A positive duration is half-open: start inclusive, end exclusive. A window
crossing midnight matches both sides of midnight. The runtime derives weekday from
`GameClock.daysPassed`, whose zero is the vanilla Sundas start date.

## Template and public data

`PKCU` is exactly 12 bytes: input count, template PACK FormID, and version. OpenSky keeps
the template link and follows it with cycle and missing-target errors.

Public data repeats an `ANAM` zero-terminated type name followed by a value field. Repeated
`UNAM` bytes assign the value indices after the values. The bounded types are:

| type name | value field | decoded value |
| --- | --- | --- |
| Bool | CNAM uint8 | Boolean |
| Int | CNAM int32 | integer |
| Float / ObjectList | CNAM float32 | float |
| Location | PLDT, 12 bytes | kind, value, radius |
| SingleRef / TargetSelector | PTDA, 12 bytes | kind, value, count or distance |
| Topic | TPIC FormID or PDTO pair | topic FormID |

Location kinds decoded by name are near reference, in cell, near package start, near editor
location, near linked reference, reference alias, location alias, and near self. Target
kinds decoded by name are specific reference, object ID, object type, linked reference,
reference alias, unknown selector, and actor. Unknown kind numbers stay raw; an unknown
type/value pair becomes an explicit `.unknown(type:bytes:)` rather than a guessed value.

## Procedure tree

Template packages carry zero-terminated `PNAM` procedure names after `XNAM`. OpenSky keeps
those names in record order and classifies the initial runtime subset as travel, wander,
sandbox, sleep, or eat. Patrol templates use the travel machine. The procedure tree's
branch graph, branch CTDAs, and embedded metadata are not decoded yet.

## Decode boundary

Malformed required fixed-width `PKDT`, `PSDT`, `PKCU`, `PLDT`, `PTDA`, or `PDTO` values
throw typed `ESMError.malformed` failures. A PACK missing `PKDT` or `PSDT` is unusable and
also throws. Unknown enum values and public-data types are preserved without failing the
record.

Deliberately skipped today:

* idle animation header, combat style, and owner quest;
* template `BNAM`, `PRCB`, `FNAM`, `PKC2`, `PFO2`, and `PFOR` control metadata;
* procedure branch structure and its CTDAs;
* public-data metadata beyond the type, value, and index;
* `POBA`/`POEA`/`POCA` action fragments beyond bounded VMAD handling.

## Whiterun census

The issue #201 real-data gate follows the stacks of Ysolda, Belethor, Hulda, and Heimskr,
including every reachable template: 21 unique PACK records. Their combined field surface is
`ANAM BNAM CIS2 CITC CNAM CTDA EDID FNAM INAM PDTO PKC2 PKCU PKDT PLDT PNAM POBA POCA
POEA PRCB PSDT PTDA SCHR UNAM VMAD XNAM`.

Their header condition-function tally is `GetDisabled` (stored index 35) three times,
`GetKeywordDataForLocation` (606) once, and `GetVMQuestVariable` (629) once. The two siege
conditions remain unsupported and therefore false; their jailed package does not select in
the pre-siege baseline. `GetDisabled` is implemented because it determines Heimskr's home
versus camp packages in that baseline.

References:

* <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PACK>
* <https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas>
