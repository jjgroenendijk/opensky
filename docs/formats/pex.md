---
type: File Format
title: Papyrus compiled script container (.pex)
description: Big-endian Skyrim SE PEX 3.2 layout - header, string table, objects,
  functions, values, and opcodes - and script path rules.
tags: [format, papyrus, pex, bytecode]
---

# Papyrus compiled script (.pex)

Skyrim SE stores compiled Papyrus scripts as `.pex` files under `scripts\`. OpenSky reads
the file into objects, properties, variables, states, functions, and instructions. The
[Papyrus VM](/engine/papyrus-vm.md) runs them.

Source:
[UESP, Compiled Script File Format](https://en.uesp.net/wiki/Skyrim_Mod:Compiled_Script_File_Format).
It gives the big-endian byte order, the field sizes, the flags, the value types, and the
opcode table.

## Version

UESP calls the Skyrim layout PEX 3.0, and 3.1 for later updates. Vanilla Skyrim SE files
(base game, DLC, and Creation Club) all have version 3.2 and game ID 1. All 14,302 vanilla
scripts decode with the documented layout. So OpenSky accepts major version 3 with minor
version 0 to 2. It rejects newer versions, so that Fallout 4 fields are never read as
Skyrim fields.

Every integer and float is big-endian. A string is a big-endian uint16 byte count, then the
bytes. UESP says UTF-8, but a mod's compiler can write anything. So strings follow the
[string decoding](/decisions/string-decoding.md) policy, and no string can fail the file.

## Header

| Type | Field | Check |
| --- | --- | --- |
| uint32 | Magic | Must be `0xFA57C0DE` |
| uint8 | Major version | Must be 3 |
| uint8 | Minor version | 0 to 2 |
| uint16 | Game ID | Must be 1 (Skyrim) |
| uint64 | Compile time | Kept |
| wstring | Source file name | Kept |
| wstring | User name | Kept |
| wstring | Machine name | Kept |

## String table

A uint16 count, then that many strings. Later fields refer to strings by uint16 index.
OpenSky resolves every index while reading, so the decoded model holds text, not indices.
An index outside the table is an error.

## Debug information

One byte says whether debug information follows. If it does: a uint64 modification time
and a uint16 function count. Each function entry has string indices for the object, state,
and function names, a one-byte function kind (0 to 3), a uint16 line count, and that many
uint16 source line numbers.

## User flags and objects

| Type | Field |
| --- | --- |
| uint16 | User flag count |
| repeats | String index and one-byte bit index |
| uint16 | Object count |
| repeats | String index, uint32 object size, object body |

The object size includes its own 4 bytes. OpenSky reads each body inside that size and
requires the body to use exactly all of it. This finds both reading too far and reading too
little, before the next object is read at the wrong offset.

## Objects

An object starts with string indices for its parent class and its documentation, a uint32
user flag mask, and a string index for its automatic state. Three counted lists follow:
variables, properties, and states.

A variable is a name index, a type name index, uint32 user flags, and one value. OpenSky
keeps the value even when it does not match the declared type. Type checks belong to the VM.

A property is name, type, and documentation indices, uint32 user flags, and a one-byte flag
mask:

| Bit | Flag | Data that follows |
| --- | --- | --- |
| 0 | Readable | Getter function, unless automatic |
| 1 | Writable | Setter function, unless automatic |
| 2 | Automatic | Index of the backing variable |

A getter or setter is a function without its own name field. An automatic property has a
backing variable instead of getter and setter.

A state is a name index and a counted list of named functions.

## Functions

| Type | Field |
| --- | --- |
| string index | Return type |
| string index | Documentation |
| uint32 | User flags |
| uint8 | Function flags: bit 0 global, bit 1 native |
| counted (name, type) pairs | Parameters |
| counted (name, type) pairs | Local variables |
| counted instructions | Body |

Native functions normally have no body, but OpenSky does not require this.

## Values

Each value starts with a one-byte kind:

| Kind | Value | Data |
| --- | --- | --- |
| 0 | null | none |
| 1 | identifier | string index |
| 2 | string | string index |
| 3 | integer | int32 |
| 4 | float | float32 |
| 5 | Boolean | one byte. 0 is false |

## Instructions

The opcode byte sets a fixed number of operands for opcodes `0x00` to `0x23`. They cover:
no-op, integer and float math, comparisons, jumps, assign and cast, calls, return, string
join, properties, and arrays (create, length, get, set, find).

`callmethod`, `callparent`, and `callstatic` have their fixed operands, then one value that
must be an integer of 0 or more: the argument count. That many argument values follow.
OpenSky keeps the count as an operand, so the instruction keeps its shape on disk.

An opcode above `0x23` is kept as unknown with no operands. Skyrim opcodes have no length,
so OpenSky cannot know how many operands to skip. The VM fails if it reaches one. Vanilla
has none.

## Errors

A cut field or object, a wrong magic, a game ID other than 1, an unsupported version, a
string index out of range, an unknown value or debug function kind, a wrong object size,
extra bytes at the end of the file, or an argument count that is not an integer of 0 or
more, is an error.

## Script paths

- A bare `NAME` becomes `scripts\name.pex`.
- `scripts\NAME`, `data\scripts\NAME.pex`, and a leading separator are accepted.
- Separators and case follow the [VFS](/formats/vfs.md) rules.
- A name with a `:` is rejected.

## Vanilla scripts

| Measure | Value |
| --- | ---: |
| Scripts | 14,302, all decode |
| Functions | 56,474 |
| Instructions | 310,731 |
| Calls to other scripts | 130,349 |
| Unknown opcodes | 0 |

The most common opcodes are `callmethod`, `cast`, `assign`, `jmpf`, `jmp`, `return`,
`cmp_eq`, and `callstatic`. The most called functions are `self.onBeginState`,
`self.onEndState`, `self.GetOwningQuest`, and `game.GetPlayer`. Scripts spell function
names with different case, but Papyrus looks names up without case.

## Not supported

Fallout 4 additions on the same UESP page, such as structs and newer debug data.
