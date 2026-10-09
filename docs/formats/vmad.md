---
type: File Format
title: Papyrus attachment data (VMAD)
description: Script attachments on ESM records - scripts, typed property values, object
  references, QUST and INFO fragment tables - and how values bind to PEX variables.
tags: [format, plugin, papyrus, vmad, formid]
---

# Papyrus attachment data (VMAD)

A `VMAD` field attaches compiled Papyrus scripts to a record and gives the property values
set for each script. OpenSky reads the scripts, turns object values into stable reference
keys (see [FormID](/formats/formid.md)), and binds the values to the backing variables named
in the [PEX](/formats/pex.md) file.

Sources:

- [xEdit dev-4.1.6 `wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas),
  mainly `wbScriptPropertyObject`, `wbScriptEntry`, `wbVMAD`, and the five fragment
  variants.
- [UESP, VMAD Field](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VMAD_Field), for
  the version-dependent flag bytes and when arrays exist.

## Header and scripts

All integers are little-endian.

| Type | Field | Check |
| --- | --- | --- |
| int16 | Version | 2 to 5 |
| int16 | Object format | 1 or 2. Sets the word order of object values |
| uint16 | Script count | Must fit in the remaining bytes |

Each script:

| Type | Field |
| --- | --- |
| uint16 + bytes | Script name |
| uint8 | Flags, only from version 4 |
| uint16 | Property count |
| repeats | Properties |

Script flags: bit 0 inherited, bit 1 removed. A removed script is kept for inspection but
never run.

Strings have no encoding marker. They follow the
[string decoding](/decisions/string-decoding.md) policy and cannot fail. Vanilla names are
ASCII.

## Properties

A property is a length-prefixed name, a one-byte type, a one-byte flags field (from
version 4), and a value. Property flags: bit 0 edited, bit 1 removed. A removed property is
read, so the reader stays in step, but it is never bound.

| Type | Value | Data |
| ---: | --- | --- |
| 0 | None | none |
| 1 | Object | 8 bytes, below |
| 2 | String | uint16 length + bytes |
| 3 | Integer | int32 |
| 4 | Float | float32 |
| 5 | Boolean | one byte. 0 is false |
| 11 | Object array | uint32 count + objects |
| 12 | String array | uint32 count + strings |
| 13 | Integer array | uint32 count + int32 values |
| 14 | Float array | uint32 count + float32 values |
| 15 | Boolean array | uint32 count + bytes |

Arrays exist from version 5. Every count is checked against the smallest possible element
size before memory is allocated. A huge count in a short field is an error, not a huge
allocation. The only array type in vanilla is the Boolean array, in two properties.

## Object values

Both object formats are 8 bytes. Only the word order differs:

| Object format | First 4 bytes | Next 2 bytes | Last bytes |
| ---: | --- | --- | --- |
| 1 | FormID | int16 alias | unused uint16 |
| 2 | unused uint16 | int16 alias | FormID |

Alias -1 means the FormID is the object itself. Any other alias means an alias on the quest
that the FormID names. FormID 0 is Papyrus `None`.

A direct FormID resolves through the master list of its plugin. The raw FormID is never
used as an identity by itself. If a value names an alias, does not resolve, or has no world
object yet, OpenSky does not make up an object. The property keeps the default value from
the compiled script.

## Fragments

`INFO`, `PACK`, `PERK`, `QUST`, and `SCEN` add a record-specific fragment table after the scripts. A
fragment is a small script function that the Creation Kit generates. OpenSky reads all five. A tail
that does not decode to the end of the field is skipped and counted. Extra bytes after the scripts
on any other record type are an error.

### The QUST tail

Quest stage scripts are not normal attached scripts. The Creation Kit puts every stage
fragment into one generated script named `QF_<editorID>_<formID>`. Each fragment is a
function named `Fragment_<n>`, numbered in the order they were written, not by stage. This
table is the only place that says which stage and log entry a fragment belongs to.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | int8 | Version. Always 2 |
| 1 | uint16 | Fragment count |
| 3 | wstring | Name of the generated `QF_` script, without extension |
| .. | fragments | Below |
| .. | uint16 | Alias count |
| .. | alias sections | Below |

One fragment:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint16 | Quest stage, the same number as `QUST INDX` |
| 2 | int16 | Unused. Always 0 |
| 4 | int32 | Log entry index in that stage |
| 8 | int8 | Unused. Always 1 |
| 9 | wstring | Script name. Normally the file name |
| .. | wstring | Function name, for example `Fragment_5` |

xEdit reads the stage and the log entry as two uint32 values. UESP splits each into a value
and a constant half. In little-endian both readings give the same bytes.

One alias section: an 8-byte object value (the quest and alias), read with the main object
format; then an int16 version, an int16 object format, a uint16 script count, and that many
normal scripts. The scripts are read with the version and format this alias gives, and then
the main values return. Vanilla never uses different values here.

A broken `QUST` tail is not fatal. OpenSky counts it, skips the rest, and keeps the main
scripts.

### The INFO tail

A dialogue result script is also generated. The Creation Kit puts the two result boxes of a
response into a script named `TIF_<editorID>_<formID>`. In vanilla it is usually
`TIF__<formID>`, with two underscores, because most `INFO` records have no editor ID. Each
box is a function named `Fragment_<n>`. The name does not say which box it is. Its position
together with the flag byte does. See [dialogue runtime](/engine/dialogue.md).

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | int8 | Version. Always 2 |
| 1 | uint8 | Flags: `0x1` has a begin fragment, `0x2` has an end fragment |
| 2 | wstring | Name of the generated `TIF_` script, without extension |
| .. | fragments | One per set flag bit, begin first, then end |

One fragment: int8 unused (always 1), wstring script name, wstring function name.

The count is not stored. It is the number of set bits in the flag byte. UESP says so
directly ("Variable flagsCount is the number of bit flags activated in flags"), and xEdit's
`wbScriptFragmentsInfoCounter` does the same. A flag bit other than the two known ones
cannot be matched to a box. So OpenSky refuses such a tail and keeps the main scripts. In
vanilla, the flag byte is always 1, 2, or 3.

## Binding values to PEX variables

OpenSky finds a property by name, without case, in the script and then up its parent
scripts. An automatic property binds to the backing variable it names. The value goes to
that exact backing variable name. OpenSky never builds the name itself.

A full property, one with its own `Set` function, binds by running that function once on
the new instance, after the automatic values and before `OnInit`. The setter can write
other variables. Example: the trap trigger base script stores its use limit in a plain
variable that only the `TriggerCount` setter writes. A tripwire that sets `FiniteUse`
needs that limit, or it can never fire. The Creation Kit wiki does not state when the
game runs the setter. Running it before `OnInit` is an inference from this data.

In vanilla, every automatic property uses the name `::<Property>_var`. This is a habit of
the compiler, not a rule. So OpenSky reads the name from the PEX file.

A value is converted to a Papyrus value and must pass the declared type check. A property
that is removed, missing, full without a setter, or the wrong type, and an object that does not
resolve, keep the compiled default. OpenSky counts each kind of skip.

## Errors

A cut value, a version outside 2 to 5, an object format other than 1 or 2, a bad string
length, a count that cannot fit, an array before version 5, an unknown property type, or
extra bytes on a record without fragments, is an error.

A `VMAD` larger than 64 KB comes through the `XXXX` size field (see
[ESM container](/formats/esm.md)). The VMAD reader sees the full data and has no 64 KB limit.

## Vanilla Skyrim.esm

16,133 `VMAD` fields decode with no errors. Most use version 5 and object format 2. There
are 856 `QUST` fragment tables with 5,108 stage fragments and 2,149 alias sections. None
fails. Across the five masters, 7,661 `INFO` tails hold 8,009 fragments, and none has extra
bytes.

## The PERK, PACK, and SCEN tails

Source: xEdit `dev-4.1.6` (commit `9fb0168`), `wbVMADFragmentedPERK`, `wbVMADFragmentedPACK`, and
`wbVMADFragmentedSCEN`. Strings are uint16-length strings, like the script names.

| Record | Layout |
| --- | --- |
| `PERK` | int8 version, file name, uint16 count; per fragment: uint32 index, 1 unused byte, script name, function name |
| `PACK` | int8 version, uint8 flags, file name; per set flag bit (0x01 begin, 0x02 end, 0x04 change): 1 unused byte, script name, function name |
| `SCEN` | int8 version, uint8 flags, file name; per set flag bit (0x01 begin, 0x02 end): 1 unused byte, script name, function name; then uint16 count of phase fragments, each: uint8 phase flag (0x01 start, 0x02 completion), uint32 phase index, 1 unused byte, script name, function name |

A flag bit outside the listed ones fails the tail, so it is skipped and counted.
