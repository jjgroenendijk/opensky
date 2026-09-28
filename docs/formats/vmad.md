---
type: File Format
title: Papyrus attachment data (VMAD)
description: Script attachments on ESM records, typed property values, object references, the
  QUST and INFO fragment tables, and how values bind to PEX backing variables.
tags: [format, plugin, papyrus, vmad, formid]
---

# Papyrus attachment data (VMAD)

A `VMAD` field attaches compiled Papyrus scripts to a record. It also holds the property values
set for each script. OpenSky decodes the script list, turns object values into
[reference keys](/formats/formid.md), and binds values to the backing variables stored in the
[PEX](/formats/pex.md) file.

Sources:

- xEdit `dev-4.1.6`
  [`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas):
  `wbScriptPropertyObject`, `wbScriptEntry`, `wbVMAD`, and the five fragment variants.
- UESP [VMAD Field](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VMAD_Field), for the
  status bytes and array support that depend on the version.

## Header and scripts

All integers are little-endian.

| Type | Field | Rule |
| --- | --- | --- |
| int16 | Version | 2 to 5 |
| int16 | Object format | 1 or 2. Sets the word order of object values |
| uint16 | Script count | Checked against the bytes left |

Each script:

| Type | Field |
| --- | --- |
| uint16 + bytes | Script name |
| uint8 | Flags, from version 4 |
| uint16 | Property count |
| repeated | Properties |

Script flag bit 0 means inherited. Bit 1 means removed. A removed script is kept for
diagnostics but never created.

Strings have no encoding marker, so they use the
[string decoding](/decisions/string-decoding.md) rules and cannot fail. Vanilla names are
ASCII.

## Properties

A property is a length-prefixed name, a one-byte type, a one-byte flags field (from version 4),
and a value. Property flag bit 0 means edited, bit 1 means removed. A removed property is read
to stay aligned, then counted and not bound.

| Type | Value | Data |
| --- | --- | --- |
| 0 | none | none |
| 1 | object | 8-byte object value |
| 2 | string | uint16 length and bytes |
| 3 | integer | int32 |
| 4 | float | binary32 |
| 5 | boolean | One byte. 0 is false |
| 11 | object array | uint32 count, objects |
| 12 | string array | uint32 count, strings |
| 13 | integer array | uint32 count, int32 values |
| 14 | float array | uint32 count, binary32 values |
| 15 | boolean array | uint32 count, bytes |

Arrays exist from version 5. Each count is checked against a minimum element size before
memory is allocated. So a huge count in a short field is an error, not a huge allocation.
Vanilla uses only boolean arrays, and rarely.

## Object values

Both formats use 8 bytes. Only the word order differs:

| Format | Bytes 0-3 | Next 2 bytes | Last bytes |
| --- | --- | --- | --- |
| 1 | FormID | int16 alias | unused uint16 |
| 2 | unused uint16 | int16 alias | FormID |

Alias -1 means the FormID is the object itself. Any other alias picks an alias on the quest
that the FormID names. A direct FormID is resolved through the owning plugin's master list and
becomes a reference key. A raw FormID is never used as an identity.

FormID 0 is Papyrus `None`. An alias value, a FormID that does not resolve, or a key with no
live object does not create an object. The property keeps its compiled default, and the skip is
counted with its reason.

## Fragments

`INFO`, `PACK`, `PERK`, `QUST`, and `SCEN` add a record-specific fragment table after the
script list. OpenSky decodes the `QUST` and `INFO` tables. For the other three it counts the
table as skipped and consumes the rest of the field. Extra bytes on any other record type are
an error.

A broken fragment table is not fatal. The decoder goes back, counts a skip, and consumes the
rest. The record keeps its normal scripts.

## The QUST table

Quest stage scripts are not attached scripts. The Creation Kit compiles all stage fragments of
a quest into one script named `QF_<editorID>_<formID>`. Each fragment is a function named
`Fragment_<n>`, numbered in the order it was written, not by stage. This table is the only link
from a fragment to its stage and log entry. Without it, stage scripts cannot run.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | int8 | Version, always 2 |
| 1 | uint16 | Fragment count |
| 3 | wstring | Name of the `QF_` script, without extension |
| .. | fragments | The stage fragments, below |
| .. | uint16 | Alias count |
| .. | alias sections | Below |

One stage fragment:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint16 | Stage index, the same as `QUST INDX` |
| 2 | int16 | Unused, always 0 |
| 4 | int32 | Log entry index in that stage |
| 8 | int8 | Unused, always 1 |
| 9 | wstring | Script name, normally the file name |
| .. | wstring | Function name, such as `Fragment_5` |

xEdit reads the stage index and the log entry index as two uint32 values. UESP splits each into
a value and a constant half. In little-endian both read the same bytes.

One alias section:

| Type | Meaning |
| --- | --- |
| object (8 bytes) | The quest and alias, read with the main object format |
| int16 | Version, repeated for this alias |
| int16 | Object format, repeated for this alias |
| uint16 | Script count, then normal script entries |

The repeated version and format are used for that alias's scripts, then the main values are
restored. In vanilla they never differ.

## The INFO table

A dialogue result script is also not an attached script. The Creation Kit compiles the two
result boxes of a response into one script named `TIF_<editorID>_<formID>`. In vanilla it is
usually `TIF__<formID>`, with two underscores, because most `INFO` records have no editor ID.
Each box is a function `Fragment_<n>`. The name does not say which box it is. Only the position
in this table and the flag byte do. So the [dialogue runtime](/engine/dialogue.md) needs this
table.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | int8 | Version, always 2 |
| 1 | uint8 | Flags: `0x1` has a begin fragment, `0x2` has an end fragment |
| 2 | wstring | Name of the `TIF_` script, without extension |
| .. | fragments | One per set flag bit: begin first, then end |

One fragment: int8 unused (always 1), wstring script name, wstring function name.

The count is not stored. It is the number of set bits in the flag byte. UESP says so ("Variable
flagsCount is the number of bit flags activated in flags"), and xEdit uses
`wbScriptFragmentsInfoCounter` with no count field. In vanilla the flag byte is only 1, 2, or 3.
A flag bit outside those two cannot be matched to a phase. So such a table is refused and
counted, and the response keeps its normal scripts.

## Binding values to PEX

A property is found by name, case-insensitively, along the script's parent chain in the PEX
files. It binds only when the PEX property is automatic and names a backing variable. The value
goes into that exact variable name. OpenSky never builds the name from the property name.

In vanilla, every automatic property uses the backing name `::<Property>_var`. That is a habit
of the compiler, not a rule. OpenSky reads the real name from the PEX file, so any other name
also works.

Scalar and array values become Papyrus values and must match the declared type. An object value
goes FormID, then reference key, then a live object handle from the caller. A removed, missing,
non-automatic, or wrong-typed property, or an object that does not resolve, keeps the PEX
default. Each skip is counted with its reason.

## Errors

The decoder rejects: a short value, a version outside 2 to 5, an object format other than 1 or
2, a bad string, a count too large for the bytes left, an array before version 5, an unknown
property type, and extra bytes on a record type without fragments.

`VMAD` fields larger than 64 KB arrive through the normal `XXXX` size field, already expanded.

## Scope

This layer decodes attachments and creates one script instance. The instance runs in the
[Papyrus world runtime](/engine/papyrus-world.md). `VMAD` does not send events, manage object
handles, run fragments, or fill quest aliases. Other runtime parts do that.
