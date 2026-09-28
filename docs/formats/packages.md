---
type: File Format
title: AI packages (PACK, PKID)
description: PACK sections, schedules, template links, public data, procedures, and what the
  decoder skips.
tags: [format, plugin, ai, package, schedule, pack, pkid]
---

# AI packages (PACK, PKID)

A `PACK` record describes an activity for an actor, such as "sleep at home from 22:00". An
`NPC_` lists its packages in order with repeated `PKID` FormIDs. The first package whose
time window and conditions are true wins.

A template package defines the procedure (the steps). A concrete package points at a
template and gives the schedule, the conditions, and the data.

Runtime use: [package schedules](/engine/package-schedules.md). Condition layout:
[conditions](/formats/conditions.md).

Sources: UESP [PACK](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PACK) and xEdit
`dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).

## Sections

The same field name means different things in different parts of a `PACK`. So the decoder
walks the fields in order and tracks the section:

1. Header: `EDID`, `PKDT`, `PSDT`, `VMAD`, and the package's own conditions.
2. `PKCU` starts the public data.
3. `XNAM` starts the procedure tree.
4. `POBA`, `POEA`, or `POCA` starts the action fragments.

Only `CTDA` conditions before `PKCU` decide if the package runs. A `CTDA` inside the
procedure tree belongs to one branch. It must not join the header conditions.

## PKDT general data (12 bytes)

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint32 | Flags |
| 4 | uint8 | Kind: 18 package, 19 template |
| 5 | uint8 | Interrupt override |
| 6 | uint8 | Preferred speed: walk, jog, run, fast walk |
| 7 | uint8 | Not read |
| 8 | uint16 | Interrupt flags |
| 10 | uint16 | Not read |

OpenSky names these flags: must complete, maintain speed at goal, once per day, uses
preferred speed, always sneak, ignore combat, weapons unequipped, weapon drawn, and wear
sleep outfit. It keeps the other bits.

## PSDT schedule (12 bytes)

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | int8 | Month. -1 means any. Otherwise counts from 1 |
| 1 | int8 | Weekday. -1 any, 0 Sundas to 6 Loredas, 7 to 10 groups |
| 2 | int8 | Day of month. 0 means any. Otherwise counts from 1 |
| 3 | int8 | Start hour. -1 means any |
| 4 | int8 | Start minute. -1 means the start of the hour |
| 5 | byte[3] | Not read |
| 8 | uint32 | Duration in game minutes |

Weekday groups: 7 weekdays (1 to 5), 8 weekend (0 and 6), 9 Morndas, Middas, and Fredas,
10 Tirdas and Turdas.

A window includes its start and excludes its end. Example: start 22, duration 480 matches
22:00 up to 05:59, on both sides of midnight. The weekday comes from the game clock. Day 0 of
the clock is a Sundas, the vanilla start date.

## PKCU and public data

`PKCU` is 12 bytes: the input count, the template `PACK` FormID, and a version. OpenSky
follows the template link and reports a loop or a missing template.

Public data is a list. Each entry is an `ANAM` type name (a zstring) and a value field. After
the values, repeated `UNAM` bytes give each value its index.

| Type name | Value field | Value |
| --- | --- | --- |
| Bool | `CNAM` uint8 | Boolean |
| Int | `CNAM` int32 | Integer |
| Float, ObjectList | `CNAM` float32 | Float |
| Location | `PLDT`, 12 bytes | Kind, value, radius |
| SingleRef, TargetSelector | `PTDA`, 12 bytes | Kind, value, count or distance |
| Topic | `TPIC` FormID or `PDTO` pair | Topic FormID |

Location kinds: near reference, in cell, near package start, near editor location, near
linked reference, reference alias, location alias, near self.

Target kinds: specific reference, object ID, object type, linked reference, reference alias,
unknown selector, actor.

Unknown kind numbers and unknown types are kept as raw values. They are not guessed.

## Procedure tree

A template has `PNAM` procedure names (zstrings) after `XNAM`. OpenSky keeps them in order and
runs these: travel, wander, sandbox, sleep, and eat. Patrol uses travel. The branch graph and
the branch conditions are not decoded yet.

## What is skipped

- Idle animation header, combat style, owner quest.
- Template control fields: `BNAM`, `PRCB`, `FNAM`, `PKC2`, `PFO2`, `PFOR`.
- Procedure branches and their conditions.
- Public-data metadata other than type, value, and index.
- Action fragments (`POBA`, `POEA`, `POCA`), beyond the limited `VMAD` reading.

A missing `PKDT` or `PSDT`, or a wrong size in `PKDT`, `PSDT`, `PKCU`, `PLDT`, `PTDA`, or
`PDTO`, makes the record unusable. Unknown values do not.

## Vanilla example: Whiterun

The packages of Ysolda, Belethor, Hulda, and Heimskr, with every template they reach, are 21
`PACK` records. Their header conditions use three functions: `GetDisabled` (index 35),
`GetKeywordDataForLocation` (606), and `GetVMQuestVariable` (629).

`GetDisabled` decides between the home package and the camp package of Heimskr. The other
two belong to the siege of Whiterun. OpenSky treats them as false, so the siege package does
not run before the siege.
