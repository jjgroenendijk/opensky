---
type: File Format
title: AI packages (PACK, PKID)
description: Skyrim SE PACK sections, schedules, package data, template links, and
  procedures.
tags: [format, plugin, ai, package, schedule, pack, pkid]
---

# AI packages (PACK, PKID)

A `PACK` record describes something an actor does at a scheduled time, for example "sleep
in bed from 22:00 to 6:00". An NPC lists its packages in order in repeated `NPC_ PKID`
fields. The first package whose schedule and conditions are true wins. A template package
gives the procedure. The package that uses the template gives the schedule, the conditions,
and the data.

See [package schedules](/engine/package-schedules.md) for the runtime and
[conditions](/formats/conditions.md) for the `CTDA` layout.

References: UESP [PACK](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/PACK) and xEdit
dev-4.1.6
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).

## Sections

The same field name means different things in different parts of a `PACK`. So OpenSky reads
it in order, section by section:

1. Header: `EDID`, `PKDT`, `PSDT`, `VMAD`, and the package's conditions.
2. `PKCU` starts the public data.
3. `XNAM` starts the procedure tree.
4. `POBA`, `POEA`, or `POCA` starts the action fragments.

Only the `CTDA` conditions before `PKCU` decide whether the package runs. Conditions inside
the procedure tree belong to one branch.

## PKDT: general data, 12 bytes

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint32 | Flags |
| 4 | uint8 | Kind: 18 package, 19 template |
| 5 | uint8 | Interrupt override |
| 6 | uint8 | Preferred speed: walk, jog, run, fast walk |
| 7 | uint8 | Skipped |
| 8 | uint16 | Interrupt flags |
| 10 | uint16 | Skipped |

OpenSky names these flags: must complete, keep speed at goal, once per day, use preferred
speed, always sneak, ignore combat, weapons unequipped, weapon drawn, and wear sleep
outfit. It keeps the other bits as raw values.

## PSDT: schedule, 12 bytes

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | int8 | Month. -1 is any; otherwise starts at 1 |
| 1 | int8 | Weekday. -1 is any; 0 Sundas to 6 Loredas; 7 to 10 are groups |
| 2 | int8 | Day of the month. 0 is any; otherwise starts at 1 |
| 3 | int8 | Start hour. -1 is any |
| 4 | int8 | Start minute. -1 is the start of the hour |
| 5 | 3 bytes | Skipped |
| 8 | uint32 | Duration in game minutes |

The weekday groups are: weekdays (1 to 5), weekends (0 and 6), Morndas/Middas/Fredas, and
Tirdas/Turdas.

A window includes its start and excludes its end. A window that crosses midnight matches on
both sides of midnight. Day 0 of the game clock is a Sundas, as in vanilla.

## PKCU and public data

`PKCU` is 12 bytes: input count, template `PACK` FormID, and version. OpenSky follows the
template link. It reports a missing template or a loop.

Public data is a list. Each entry is an `ANAM` type name (zstring) followed by a value
field. After the values, repeated `UNAM` bytes give each value its index.

| Type name | Value field | Value |
| --- | --- | --- |
| Bool | `CNAM` uint8 | Boolean |
| Int | `CNAM` int32 | Integer |
| Float, ObjectList | `CNAM` float32 | Float |
| Location | `PLDT`, 12 bytes | Kind, value, radius |
| SingleRef, TargetSelector | `PTDA`, 12 bytes | Kind, value, count or distance |
| Topic | `TPIC` FormID or a `PDTO` pair | Topic FormID |

Location kinds: near reference, in cell, near package start, near editor location, near
linked reference, reference alias, location alias, near self.

Target kinds: specific reference, object ID, object type, linked reference, reference
alias, unknown selector, actor.

OpenSky keeps unknown kind numbers raw. An unknown type is kept as its type name and bytes.
OpenSky does not guess its value.

## Procedure tree

After `XNAM`, a template lists its branches. Each branch starts with an `ANAM` branch
type. Its conditions, `PRCB` root data (branch count and flags), `PNAM` procedure type,
`FNAM` success flag, `PKC2` data input indexes, `PFO2` flag overrides, and `PFOR` follow.
`PFOR` has no explained layout, so it stays raw. OpenSky recognizes travel, wander,
sandbox, sleep, and eat. Patrol uses travel.

After the branches come the template's own data inputs. Each one is a `UNAM` index, a
`BNAM` name, and a 4-byte `PNAM` public flag. The decoder tells this `PNAM` from a
procedure `PNAM` by position, not by size, because a short procedure name such as `Sit`
is also 4 bytes.

## Events

`POBA`, `POEA`, and `POCA` open the begin, end, and change events. Each has an `INAM`
idle and a `PDTO` topic. `SCHR`, `SCDA`, `SCTX`, `QNAM`, and `TNAM` there are left over
from older Creation Kit versions. xEdit marks them unused, so they stay raw.

## Errors and skipped fields

A `PKDT`, `PSDT`, `PKCU`, `PLDT`, `PTDA`, or `PDTO` of the wrong size is an error. A `PACK`
without `PKDT` or `PSDT` cannot be used and is an error.

The header also holds the idle animations (`IDLF`, `IDLC`, `IDLT`, `IDLA`), the combat
style (`CNAM`), and the owner quest (`QNAM`). AI does not run the branch graph, the idle
animations, or the events yet; the decoder only reads them.

## Whiterun example

The packages of Ysolda, Belethor, Hulda, and Heimskr, with every template they reach, are 21
`PACK` records. Together they use these fields:
`ANAM BNAM CIS2 CITC CNAM CTDA EDID FNAM INAM PDTO PKC2 PKCU PKDT PLDT PNAM POBA POCA POEA
PRCB PSDT PTDA SCHR UNAM VMAD XNAM`.

Their header conditions use `GetDisabled` (function 35) three times,
`GetKeywordDataForLocation` (606) once, and `GetVMQuestVariable` (629) once. The last two
belong to the siege of Whiterun. OpenSky does not support them, so they are false, and the
jail package is not picked before the siege. `GetDisabled` decides whether Heimskr uses the
home package or the camp package.
