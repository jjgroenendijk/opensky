---
type: File Format
title: Papyrus compiled script container (.pex)
description: Big-endian Skyrim SE PEX layout (header, string table, debug data, objects,
  functions, bytecode operands) and the script path rules.
tags: [format, papyrus, pex, bytecode]
---

# Papyrus compiled script (.pex)

Skyrim SE stores compiled Papyrus scripts under `scripts\` as `.pex` files. OpenSky decodes
a file into objects, properties, variables, states, functions, instructions, and values. The
[Papyrus VM](/engine/papyrus-vm.md) runs them. This page covers only the file.

Source: UESP
[Compiled Script File Format](https://en.uesp.net/wiki/Skyrim_Mod:Compiled_Script_File_Format).
It gives the byte order, field sizes, flags, value encodings, and opcode table.

## Version

UESP calls the Skyrim layout PEX 3.0, and 3.1 for later updates. The files in the SE, DLC, and
Creation Club archives say version 3.2 with game ID 1. They decode with the documented Skyrim
layout. That version number is the only difference from the page.

OpenSky accepts major version 3 with minor versions 0 to 2. It rejects newer versions, so
Fallout 4 additions are never read as Skyrim fields.

## Basics

Every integer and float is big-endian. A string (`wstring`) is a big-endian uint16 byte count,
then the bytes. UESP says UTF-8, but a mod's compiler can write anything. So strings use the
[string decoding](/decisions/string-decoding.md) rules, and a string cannot make the file fail.

## Header

| Type | Field | Rule |
| --- | --- | --- |
| uint32 | Magic | Must be `0xFA57C0DE` |
| uint8 | Major version | Must be 3 |
| uint8 | Minor version | 0 to 2 |
| uint16 | Game ID | Must be 1, Skyrim |
| uint64 | Compile time | Kept |
| wstring | Source file name | Kept |
| wstring | User name | Kept |
| wstring | Machine name | Kept |

## String table

A uint16 count, then that many `wstring`s. Later fields refer to strings by uint16 index.
OpenSky resolves every index while decoding. An index outside the table is an error that names
the index and the table size.

## Debug information

One byte says whether debug data follows. If it does: a uint64 modification time and a uint16
function count. Each function entry has string indices for object, state, and function names,
a one-byte function kind (0 to 3), a uint16 line count, and that many uint16 line numbers.

## User flags and objects

| Type | Field |
| --- | --- |
| uint16 | User flag count |
| repeated | String index, then one-byte flag bit index |
| uint16 | Object count |
| repeated | String index, uint32 object size, object body |

The object size includes its own 4 bytes. OpenSky reads each body inside that exact span and
requires the body to use all of it. This catches reading too far, and also reading too little,
which would otherwise start the next object at the wrong place.

## Object body

String indices for the parent class and the documentation, a uint32 user-flag mask, and a
string index for the automatic state. Then three counted lists: variables, properties, and
states.

A variable is a name index, a type-name index, uint32 user flags, and one value. The value is
kept even when it does not match the declared type. Type checks belong to the VM.

A property is name, type, and documentation indices, uint32 user flags, and one flag byte:

| Bit | Flag | Data that follows |
| --- | --- | --- |
| 0 | readable | Getter function, unless automatic |
| 1 | writable | Setter function, unless automatic |
| 2 | automatic | Name index of the backing variable |

Getters and setters are functions without a name field.

A state is a name index and a counted list of named functions.

## Function

| Type | Field |
| --- | --- |
| String index | Return type |
| String index | Documentation |
| uint32 | User flags |
| uint8 | Flags: bit 0 global, bit 1 native |
| counted (name, type) pairs | Parameters |
| counted (name, type) pairs | Local variables |
| counted instructions | Bytecode |

Native functions usually have no bytecode, but OpenSky does not require that.

## Values

Each operand starts with a one-byte kind:

| Kind | Value | Data |
| --- | --- | --- |
| 0 | null | none |
| 1 | identifier | String index |
| 2 | string | String index |
| 3 | integer | int32 |
| 4 | float | IEEE-754 binary32 |
| 5 | boolean | One byte. 0 is false |

## Instructions

The opcode byte decides a fixed operand count, for opcodes `0x00` to `0x23`. They cover no-op,
integer and float math, compares, jumps, assign and cast, calls, return, string concatenation,
properties, and arrays.

`callmethod`, `callparent`, and `callstatic` have their fixed operands, then one integer value
that is the argument count, then that many argument values. The count must be a non-negative
integer. OpenSky keeps the count in the operand list, so the stored shape matches the file.

An opcode above `0x23` is kept as an unknown opcode with no operands. Skyrim instructions have
no length field, so there is no safe way to skip its operands. The VM fails if it reaches one.
Vanilla has none.

## Errors

Decoding is bounds-checked. It rejects: short fields and object spans, a wrong magic, a
non-Skyrim game ID, an unsupported version, string indices out of range, unknown value or debug
function kinds, bad object sizes, objects that do not use their whole span, extra bytes at the
end of the file, and call argument counts that are not non-negative integers.

## Script paths

A script name becomes a VFS path like this:

- `NAME` becomes `scripts\name.pex`.
- `scripts\NAME`, `data\scripts\NAME.pex`, and a leading separator are accepted.
- Separators and case follow the [VFS](/formats/vfs.md) rules.
- A name with `:` is rejected.

Listing all scripts filters the archives for `scripts\*.pex`. Loose files still win when a
script is loaded, because the VFS decides.

## Vanilla facts

- Every vanilla script decodes, and none has an unknown opcode.
- `callmethod` is by far the most common opcode, then `cast` and `assign`.
- Every script calls `self.onBeginState` and `self.onEndState`.
- Scripts spell the same function with different case. Native lookup is case-insensitive.

## Native calls

OpenSky finds every native function declaration across the script inheritance tree. It then
gives each call site a typed (script, function) target. The receiver type comes from
parameters, locals, variables, automatic properties, `self`, and inherited declarations, not
from the spelling of the operand. This list feeds the native registry of the
[Papyrus VM](/engine/papyrus-vm.md).

Fallout 4 additions on the same UESP page, such as structs, are out of scope.
