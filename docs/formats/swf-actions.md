---
type: File Format
title: SWF actions
description: DoAction and DoInitAction, ACTIONRECORD framing, the opcode table, ActionPush value
  types, the DOUBLE word order, function bodies, and CLIPACTIONS event handlers.
tags: [format, swf, ui, actionscript, scaleform]
---

# SWF actions

Menus run ActionScript 1 and 2 bytecode. This page covers how the bytecode is stored. Running
it is on the [ActionScript 2 runtime](/engine/as2-runtime.md) page. The container is on the
[SWF](/formats/swf.md) page.

Source: Adobe SWF specification, version 19, chapter 5 "Actions": DoAction and ACTIONRECORD
(p. 63), DoInitAction (p. 108), and the action tables for SWF 3 (pp. 64-66), SWF 4 (pp. 68-88),
SWF 5 (pp. 89-107), SWF 6 (pp. 108-110), and SWF 7 (pp. 111-116). Clip actions are in chapter 3
(pp. 36-37 and 48-49).

## Action tags

| Tag | Name | Body |
| --- | --- | --- |
| 12 | DoAction | Action records, up to `ActionEndFlag` |
| 59 | DoInitAction | `Sprite ID` uint16, then the same records |

DoAction runs when its frame's `ShowFrame` is reached, wherever the tag sits in the frame. So
each block belongs to the frame being read. DoInitAction runs once, before the named sprite is
first created.

## ACTIONRECORD

| Field | Type | Meaning |
| --- | --- | --- |
| ActionCode | uint8 | 0 is `ActionEndFlag` and ends the stream |
| Length | uint16, only if code >= 0x80 | Operand bytes, header not counted |
| Operands | Length bytes | None when the code is below 0x80 |

Records are found by byte offset, because `ActionJump` (0x99) and `ActionIf` (0x9D) jump to byte
offsets, and function bodies are sized in bytes. Each record knows its start and its end. A
branch offset of 0 points at the end of the branch record. A jump into the middle of a record
finds no record.

A missing `ActionEndFlag` is not an error. Bytes after it are ignored. Other problems are counted
as warnings and do not throw:

| Warning | Cause | Result |
| --- | --- | --- |
| `truncatedRecord` | Header or operands run past the end | Stream stops |
| `malformedOperands` | Operands do not decode | Raw bytes kept, reading goes on |
| `bodySizeOutOfBounds` | A function, `with`, or `try` size runs past the end | Stream stops |
| `malformedClipActions` | Clip action framing failed | Handlers read so far are kept |

## Opcodes

The specification defines 100 codes: 99 actions and code 0. It prints code 0x08 as
`ActionToggleQualty`. That is a typing error, and OpenSky uses `ActionToggleQuality`.

Scaleform runs the same bytecode. Its extras are host objects, reached through
`ActionGetMember` and `ActionCallMethod`, not new opcodes. So an unknown code means a broken
stream, not a GFx feature. Vanilla menus use no unknown codes.

These codes have operands that OpenSky decodes. The others keep their raw bytes.

| Code | Action | Operands |
| --- | --- | --- |
| 0x81 | ActionGotoFrame | `Frame` uint16 |
| 0x83 | ActionGetURL | `UrlString`, `TargetString` |
| 0x87 | ActionStoreRegister | `RegisterNumber` uint8 |
| 0x88 | ActionConstantPool | `Count` uint16, then `Count` strings |
| 0x8A | ActionWaitForFrame | `Frame` uint16, `SkipCount` uint8 |
| 0x8B | ActionSetTarget | `TargetName` string |
| 0x8C | ActionGoToLabel | `Label` string |
| 0x8D | ActionWaitForFrame2 | `SkipCount` uint8 |
| 0x8E | ActionDefineFunction2 | Below |
| 0x8F | ActionTry | Below |
| 0x94 | ActionWith | `Size` uint16, the length of the body after it |
| 0x96 | ActionPush | Repeated `Type` uint8 and value, to the end of the operands |
| 0x99 | ActionJump | `BranchOffset` int16 |
| 0x9A | ActionGetURL2 | `SendVarsMethod` (2 bits), 4 reserved bits, load target, load variables |
| 0x9B | ActionDefineFunction | Name, `NumParams`, names, `codeSize` |
| 0x9D | ActionIf | `BranchOffset` int16 |
| 0x9F | ActionGotoFrame2 | 6 reserved bits, `SceneBiasFlag`, `Play`, optional `SceneBias` |

## ActionPush values

Types 2 to 9 exist from SWF 5 (p. 69).

| Type | Value |
| --- | --- |
| 0 | String, ending in a zero byte |
| 1 | float32 |
| 2 | null |
| 3 | undefined |
| 4 | Register number, uint8 |
| 5 | Boolean, uint8 |
| 6 | float64, word order below |
| 7 | int32 |
| 8 | Constant pool index, uint8 |
| 9 | Constant pool index, uint16 |

## The DOUBLE word order

The specification calls type 6 a "64-bit IEEE double-precision little-endian double value". That
reads like a plain little-endian 64-bit value. It is not. Flash writes the two 32-bit halves with
the high half first.

The vanilla menus prove it. Read with the halves swapped, the pushed doubles are normal numbers:
`0.5`, `0.55`, `147.3`, `4294967295`. Read as written in the specification, they are tiny
denormals such as `1.06e-314`, or huge values such as `-8.99e+307`. So OpenSky reads two uint32
values and joins them high half first.

## Function bodies

`ActionDefineFunction` (p. 92): `FunctionName` string, `NumParams` uint16, that many parameter
name strings, then `codeSize` uint16.

`ActionDefineFunction2` (p. 111) adds `RegisterCount` uint8 and a 16-bit word of preload and
suppress flags after `NumParams`. Its parameters are register records: `Register` uint8 and
`ParamName` string.

The body is not inside the record. It is the next `codeSize` bytes of the same stream.
`ActionWith` and `ActionTry` size their bodies the same way.

`ActionTry` (p. 115): a flag byte (5 reserved bits, `CatchInRegisterFlag`, `FinallyBlockFlag`,
`CatchBlockFlag`), then `TrySize`, `CatchSize`, and `FinallySize` as uint16. All three are always
present. Then `CatchName` as a string, or `CatchRegister` as a uint8.

Vanilla menus never use `ActionWith` or `ActionTry`.

Strings use the [string decoding](/decisions/string-decoding.md) rules.

## Clip actions

`HasClipActions` (bit `0x80` of the first flag byte) ends a PlaceObject2 or PlaceObject3 with the
object's event handlers, such as `onPress` and `onEnterFrame`.

| Field | Type | Meaning |
| --- | --- | --- |
| Reserved | uint16 | Must be 0 |
| AllEventFlags | CLIPEVENTFLAGS | All events handled |
| ClipActionRecords | repeated | One per handler |
| ClipActionEndFlag | uint16 up to SWF 5, uint32 from SWF 6 | All zero |

A handler record is `EventFlags`, then `ActionRecordSize` (uint32), then a `KeyCode` byte only
when the flags include `KeyPress`, then the action records. `ActionRecordSize` counts from the
end of that field, so it includes the `KeyCode` byte. For a key press handler the actions are
`ActionRecordSize - 1` bytes.

CLIPEVENTFLAGS is 2 bytes up to SWF 5 and 4 bytes from SWF 6. The specification lists it as
single bits. Read as a little-endian word, the bit numbers are:

| Bit | Event | Bit | Event | Bit | Event |
| --- | --- | --- | --- | --- | --- |
| 0 | Load | 7 | KeyUp | 14 | RollOut |
| 1 | EnterFrame | 8 | Data | 15 | DragOver |
| 2 | Unload | 9 | Initialize | 16 | DragOut |
| 3 | MouseMove | 10 | Press | 17 | KeyPress |
| 4 | MouseDown | 11 | Release | 18 | Construct |
| 5 | MouseUp | 12 | ReleaseOutside | | |
| 6 | KeyDown | 13 | RollOver | | |

The 2-byte form is the low half of the 4-byte form. `AllEventFlags` is kept as written, not
computed from the handlers, so a movie that disagrees with itself can be inspected.

A bad clip action block keeps the handlers read so far, adds a warning, and still places the
object.

In vanilla, almost every clip handler is `Construct`, the Scaleform component setup event.
`statsmenu.swf` has one `Load` and one `EnterFrame` handler. No vanilla movie uses a mouse or key
clip event. Buttons work through `addEventListener` calls inside DoAction code instead. Most names
the bytecode calls are in the `gfx` namespace: Scaleform's own component library, such as
`gfx.controls.Button`.
