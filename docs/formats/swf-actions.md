---
type: File Format
title: SWF actions (ActionScript 1/2 bytecode)
description: DoAction and DoInitAction, ACTIONRECORD framing, the opcode table, typed
  operands, CLIPACTIONS, and the vanilla bytecode census.
tags: [format, swf, ui, actionscript, scaleform]
---

# SWF actions

SWF movies carry ActionScript 1 and 2 bytecode. This page covers how the bytecode is stored.
The [AS2 runtime](/engine/as2-runtime.md) runs it. The container is on [SWF](/formats/swf.md).

Reference: Adobe SWF File Format Specification v19, chapter 5 "Actions": "DoAction" and
"ACTIONRECORD" (p. 63), "DoInitAction" (p. 108), and the action tables for SWF 3
(pp. 64-66), SWF 4 (pp. 68-88), SWF 5 (pp. 89-107), SWF 6 (pp. 108-110), and SWF 7
(pp. 111-116). CLIPACTIONS is in chapter 3 under "PlaceObject2" (pp. 36-37) and
"ClipEventFlags" (pp. 48-49).

## Action tags

| tag | name | body |
| --- | --- | --- |
| 12 | DoAction | ACTIONRECORD stream, ended by `ActionEndFlag` |
| 59 | DoInitAction | `Sprite ID` UI16, then the same stream |

DoAction runs when its frame's `ShowFrame` is reached, wherever the tag is in the frame.
DoInitAction runs once, before the named sprite is first created.

## ACTIONRECORD

| field | type | notes |
| --- | --- | --- |
| ActionCode | UI8 | 0 is `ActionEndFlag` and ends the stream |
| Length | UI16, only if code >= 0x80 | operand size, header not included |
| operands | UI8[Length] | absent when the code is below 0x80 |

Branches use byte offsets: `ActionJump` (0x99) and `ActionIf` (0x9D) jump by a byte count,
and function bodies are sized in bytes. A `BranchOffset` of 0 means the byte just after the
record. A branch into the middle of a record is invalid.

A missing `ActionEndFlag` at the end is not an error, and bytes after one are ignored.

## Opcodes

The spec defines 100 codes: 99 actions and code 0. The spec prints 0x08 as
`ActionToggleQualty`; that is a typing error for `ActionToggleQuality`. Scaleform GFx runs
the same bytecode. Its extensions are host objects reached through `ActionGetMember` and
`ActionCallMethod`, not new opcodes. So an unknown code means a broken stream.

Opcodes with operands that OpenSky decodes:

| code | action | operands |
| --- | --- | --- |
| 0x81 | ActionGotoFrame | `Frame` UI16 |
| 0x83 | ActionGetURL | `UrlString` STRING, `TargetString` STRING |
| 0x87 | ActionStoreRegister | `RegisterNumber` UI8 |
| 0x88 | ActionConstantPool | `Count` UI16, `ConstantPool` STRING[Count] |
| 0x8A | ActionWaitForFrame | `Frame` UI16, `SkipCount` UI8 |
| 0x8B | ActionSetTarget | `TargetName` STRING |
| 0x8C | ActionGoToLabel | `Label` STRING |
| 0x8D | ActionWaitForFrame2 | `SkipCount` UI8 |
| 0x8E | ActionDefineFunction2 | see below |
| 0x8F | ActionTry | see below |
| 0x94 | ActionWith | `Size` UI16, the length of the body that follows |
| 0x96 | ActionPush | repeated `Type` UI8 + value, filling the operands |
| 0x99 | ActionJump | `BranchOffset` SI16 |
| 0x9A | ActionGetURL2 | `SendVarsMethod` UB[2], UB[4], target flag, variables flag |
| 0x9B | ActionDefineFunction | name, `NumParams` UI16, names, `codeSize` UI16 |
| 0x9D | ActionIf | `BranchOffset` SI16 |
| 0x9F | ActionGotoFrame2 | UB[6], `SceneBiasFlag`, `Play`, optional `SceneBias` UI16 |

`ActionPush` value types (spec p. 69). Types 2 to 9 exist from SWF 5.

| type | value |
| --- | --- |
| 0 | STRING, zero-terminated |
| 1 | FLOAT, 32-bit IEEE |
| 2 | null |
| 3 | undefined |
| 4 | register number UI8 |
| 5 | Boolean UI8 |
| 6 | DOUBLE, 64-bit IEEE, see below |
| 7 | 32-bit integer, signed |
| 8 | constant pool index UI8 |
| 9 | constant pool index UI16 |

## DOUBLE word order

The spec calls the type-6 value a "64-bit IEEE double-precision little-endian double value".
That reads as a plain little-endian UI64, but it is not. Flash writes the two 32-bit halves
with the high word first. In the vanilla movies (16,607 pushed doubles), the swapped reading
gives normal constants such as `0.5`, `0.55`, `147.3`, and `4294967295`. The plain reading
gives values such as `1.06e-314` and `-8.99e+307`. So OpenSky reads two UI32 values and
joins them high word first.

## Functions, with, and try

`ActionDefineFunction` (p. 92) is `FunctionName` STRING, `NumParams` UI16, that many
parameter-name STRINGs, then `codeSize` UI16.

`ActionDefineFunction2` (p. 111) puts `RegisterCount` UI8 and a 16-bit preload and suppress
flag word after `NumParams`. It replaces the parameter names with REGISTERPARAM records
(`Register` UI8 and `ParamName` STRING).

The function body is not inside the record. It is the next `codeSize` bytes of the same
stream. `ActionWith` and `ActionTry` size their bodies the same way.

`ActionTry` (p. 115) is a flag byte (reserved UB[5], `CatchInRegisterFlag`,
`FinallyBlockFlag`, `CatchBlockFlag`), then `TrySize`, `CatchSize`, and `FinallySize` as
UI16 (always all three), then `CatchName` STRING or `CatchRegister` UI8.

STRINGs decode leniently ([string decoding](/decisions/string-decoding.md)).

## CLIPACTIONS

When `PlaceFlagHasClipActions` (0x80 of the first flag byte) is set, a PlaceObject2 or
PlaceObject3 body ends with the sprite's event handlers:

| field | type | notes |
| --- | --- | --- |
| Reserved | UI16 | must be 0 |
| AllEventFlags | CLIPEVENTFLAGS | all events used |
| ClipActionRecords | CLIPACTIONRECORD[] | one per handler |
| ClipActionEndFlag | UI16 (SWF 5 and older) or UI32 (SWF 6+) | all zero |

Each CLIPACTIONRECORD is `EventFlags` CLIPEVENTFLAGS, `ActionRecordSize` UI32, a `KeyCode`
UI8 only when `EventFlags` has `ClipEventKeyPress`, then the ACTIONRECORD stream. The size
counts from after its own field, so it includes the `KeyCode` byte. For a key-press handler
the action stream is `ActionRecordSize - 1` bytes.

CLIPEVENTFLAGS is 2 bytes up to SWF 5 and 4 bytes from SWF 6. The spec lists it as UB[1]
fields. Read as a little-endian word, the bits are: `ClipEventLoad` 0, `EnterFrame` 1,
`Unload` 2, `MouseMove` 3, `MouseDown` 4, `MouseUp` 5, `KeyDown` 6, `KeyUp` 7, `Data` 8,
`Initialize` 9, `Press` 10, `Release` 11, `ReleaseOutside` 12, `RollOver` 13, `RollOut` 14,
`DragOver` 15, `DragOut` 16, `KeyPress` 17, `Construct` 18. The short form is the low half
of the long form. OpenSky keeps `AllEventFlags` as written, even when it does not match the
handlers.

## Vanilla bytecode

Measured with `openskycli swf action-sweep` over the 53 vanilla movies:

- 3,414 action blocks: 2,163 DoAction, 1,127 DoInitAction, 124 CLIPACTIONS handlers.
- 533,562 ACTIONRECORDs using 56 different opcodes. No unknown opcode.
- Most used: `ActionPush` (191,644), `ActionGetMember` (83,487), `ActionPop` (37,127),
  `ActionSetMember` (30,757), `ActionNot` (28,569).
- 1,323 `ActionDefineFunction` and 10,575 `ActionDefineFunction2` (at most 23 registers),
  936 `ActionConstantPool` (at most 404 entries). No `ActionWith` and no `ActionTry`.
- The largest block is 32,240 bytes with 5,886 records. The largest users are
  `quest_journal.swf` (33,692 records in 250 blocks), `modmanager.swf` (29,383 in 62), and
  `inventorymenu.swf` (24,754 in 68).
- 3,382 different host names appear before member, method, and variable actions. The most
  common are `gfx` (8,094 uses in 41 movies), `_global`, `Shared`, `prototype`, `ui`,
  `NavigationCode`, `io`, `addProperty`, `GameDelegate`, and `length`. The `gfx.*`
  namespace is Scaleform's own component library (`gfx.controls.Button`,
  `EventDispatcher`, `Constraints`). Vanilla menus are built on it.
- CLIPACTIONS: 122 `construct` handlers in 24 movies, plus one `load` and one `enterFrame`
  handler in `statsmenu.swf`. No mouse or key events appear. Buttons react through
  `addEventListener` calls inside DoAction code instead.
