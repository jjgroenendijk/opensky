---
type: File Format
title: Papyrus compiled script container (.pex)
description: Big-endian Skyrim SE PEX 3.2 framing, typed object and function
  models, bytecode operands, VFS path policy, and vanilla census evidence.
tags: [format, papyrus, pex, bytecode]
timestamp: 2026-07-30T00:00:00Z
---

# Papyrus compiled script container (.pex)

Skyrim Special Edition stores compiled Papyrus programs under `scripts\` as
`.pex` files. OpenSky decodes the container into typed objects, properties,
variables, states, functions, instructions and values. Execution belongs to the
Papyrus virtual machine; this layer only validates and represents the file.

Layout source:
[UESP, Compiled Script File Format](https://en.uesp.net/wiki/Skyrim_Mod:Compiled_Script_File_Format).
The page is the source for the big-endian byte order, field widths, flags,
value encodings and opcode table. No Bethesda code or compiled script bytes are
copied into the repository.

Decoder: `opensky/Engine/Formats/PEX/PexFile.swift`, with the byte reader and top-level
framing in `PexDecoder.swift`, object framing in `PexDecoderObject.swift`, and
function and bytecode framing in `PexDecoderFunction.swift`.

## Contents

* [Observed revision](#observed-revision)
* [Container layout](#container-layout)
* [Objects and functions](#objects-and-functions)
* [Values and instructions](#values-and-instructions)
* [Decode policy](#decode-policy)
* [VFS loading](#vfs-loading)
* [Vanilla sweep evidence](#vanilla-sweep-evidence)
* [Native-call census](#native-call-census)
* [Scope](#scope)

## Observed revision

The UESP page labels the Skyrim layout as PEX 3.0 and notes 3.1 for later
Skyrim updates. A read-only probe on 2026-07-30 sampled the base-game, DLC and
Creation archives and found version bytes `3.2`, game ID 1, in all samples.
The complete sweep below then decoded all 14,302 files with the documented
Skyrim layout. This version label is the only observed deviation from the page:
OpenSky accepts major version 3 and minor versions 0 through 2, and rejects
newer revisions before their Fallout 4 additions can be mistaken for Skyrim
fields.

Every integer and float in a PEX file is big-endian. Strings are byte runs
prefixed by a big-endian `uint16` byte count; the page calls them UTF-8, but a
mod's compiler is free to emit anything, so they decode under the engine-wide
lenient text policy ([string decoding](/decisions/string-decoding.md)) and no
string can fail the file.

## Container layout

### Header

| type | field | policy |
| --- | --- | --- |
| `uint32` | magic | must be `0xFA57C0DE` |
| `uint8` | major version | must be 3 |
| `uint8` | minor version | 0 through 2 |
| `uint16` | game ID | must be 1 for Skyrim |
| `uint64` | compilation time | retained verbatim |
| `wstring` | source file name | lenient text decode |
| `wstring` | user name | lenient text decode |
| `wstring` | machine name | lenient text decode |

The metadata strings are part of the public in-memory header because tools may
need them, but OpenSky does not use them to locate source files.

### String table

| type | field | notes |
| --- | --- | --- |
| `uint16` | count | number of following entries |
| `wstring[count]` | strings | indexed by later `uint16` references |

All string indices resolve while decoding. Public models contain `String`
values, never table indices. An invalid reference throws
`PexError.stringIndexOutOfRange(index:count:)`, naming both the bad index and
the available count.

### Debug information

One byte says whether debug information follows. When present, it contains a
`uint64` modification time and a `uint16` function count. Each function entry
has string indices for object, state and function names, a one-byte function
kind, a `uint16` line count and that many `uint16` source line numbers.
Function kinds 0 through 3 are accepted; another value is malformed.

### User flags and objects

The debug section is followed by:

| type | field |
| --- | --- |
| `uint16` | user-flag count |
| repeated | string index plus one-byte flag bit index |
| `uint16` | object count |
| repeated | string index, `uint32` object size, object body |

The stored object size includes its own four-byte size word. OpenSky places a
bounded subreader around every body and requires the body to consume exactly
that declared span. This catches both an overrun and an otherwise invisible
under-read before the next object is decoded at the wrong offset.

## Objects and functions

An object body begins with string indices for its parent class and
documentation, a `uint32` user-flag mask, and a string index for its automatic
state. Three counted collections follow: variables, properties and states.

### Variables

A variable is a name index, type-name index, `uint32` user flags, and one typed
value. The initial value is retained even when its declared type and encoded
value differ; type checking is a virtual-machine concern.

### Properties

A property stores name, type and documentation indices, `uint32` user flags,
and a one-byte flag mask:

| bit | model flag | following data |
| --- | --- | --- |
| 0 | `readable` | getter function unless automatic |
| 1 | `writable` | setter function unless automatic |
| 2 | `automatic` | backing-variable name index |

Getter and setter bodies have the same shape as other functions but no
separate function-name field. Automatic properties carry the backing variable
instead and do not decode handlers.

### States and functions

A state has a name index and a counted list of named functions. A function
contains:

| type | field |
| --- | --- |
| string index | return type |
| string index | documentation |
| `uint32` | user flags |
| `uint8` | function flags: global bit 0, native bit 1 |
| counted typed names | parameters |
| counted typed names | local variables |
| counted instructions | bytecode body |

Each typed name is a name index followed by a type-name index. Native functions
normally have no bytecode body, but the decoder does not make that a structural
requirement.

## Values and instructions

Each operand begins with a one-byte value kind:

| kind | model | payload |
| --- | --- | --- |
| 0 | `null` | none |
| 1 | `identifier` | string-table index |
| 2 | `string` | string-table index |
| 3 | `integer` | `int32` |
| 4 | `float` | IEEE-754 binary32 bits |
| 5 | `boolean` | one byte, zero is false |

The opcode byte selects a fixed operand count for opcodes `0x00` through
`0x23`. The set covers no-op, integer and float arithmetic, comparisons,
branches, assignment and cast, calls, return, string concatenation, properties,
and array creation, length, element access, mutation and searches.

`callmethod`, `callparent` and `callstatic` have fixed target/result operands
followed by one typed value that must be a non-negative integer argument count,
then that many typed argument values. Keeping the count value in
`PexInstruction.operands` preserves the encoded stream shape for the
interpreter while the decoder still validates it.

An opcode outside `0x00...0x23` becomes `PexOpcode.unknown(rawByte)` rather
than aborting the script. Skyrim opcodes do not carry a length, so the decoder
cannot safely infer operands for an unknown byte; the preserved instruction
has no operands. The inventory can still expose the occurrence, and the
virtual machine can fault if execution reaches it.

## Decode policy

`PexFile.init(data:)` is bounds checked throughout and throws a typed
`PexError`. It rejects:

* truncated fields and declared object spans;
* wrong magic, non-Skyrim game ID or unsupported format versions;
* string-table indices outside the table;
* unknown value and debug-function kinds;
* invalid object sizes, object under-reads and file trailing bytes; and
* a call argument count that is not a non-negative integer.

The synthetic `PexFixture` constructs its bytes in code. It covers empty and
Unicode strings, all six value types, every Skyrim opcode and each call
encoding, debug information, flags, objects, variables, automatic properties,
states, function headers, truncation, invalid indices and headers, negative
argument counts, and unknown-opcode preservation. No `.pex` fixture or extracted
game data is tracked.

## VFS loading

`PexScriptLoader.canonicalScriptPath(_:)` is a pure transform:

* bare `NAME` becomes `scripts\name.pex`;
* `scripts\NAME`, `data\scripts\NAME.pex` and leading separators are accepted;
* separators and case normalize through the shared VFS policy; and
* any input containing `:` is rejected before normalization.

Loading uses an injectable `(String) throws -> Data` closure. Production passes
`VirtualFileSystem.contents(forPath:)`; unit tests pass a stub. Enumeration
filters the VFS archive inventory to `scripts\*.pex`, then returns its
path-sorted results. Loose files still win when a listed path is loaded because
resolution remains the VFS's responsibility.

## Vanilla sweep evidence

`PexRealDataTests` ran through `make realtest` on 2026-07-30 against the retail
Special Edition install. It enumerated every archive-provided PEX path, loaded
each through the VFS, decoded one file at a time, and wrote its aggregate report
to gitignored `logs/pex-census.log`.

| measure | observed |
| --- | ---: |
| script paths | 14,302 |
| decoded scripts | 14,302 |
| functions | 56,474 |
| instructions | 310,731 |
| external calls | 130,349 |
| unknown opcodes | 0 |
| decode failures | 0 |

The gate asserts a script floor of 10,000, instruction and call floors, exact
decoded/path equality, zero failures, and the unknown-opcode count pinned to
zero. Counts are uncapped. Name tables for calls and failure paths are bounded
to 1,024 distinct values by default.

The most frequent opcodes were `callmethod` 119,282, `cast` 48,084, `assign`
43,235, `jmpf` 20,761, `jmp` 17,724, `return` 16,447, `cmp_eq` 11,259 and
`callstatic` 10,980. The top external object/function targets were
`self.onBeginState` 14,302, `self.onEndState` 14,302,
`self.GetOwningQuest` 7,449 and `game.GetPlayer` 4,725. Rankings preserve
spelling and case because Papyrus source in the corpus uses several variants;
coalescing them here would hide the surface a native registry must accept.

## Native-call census

`PexNativeCensus` resolves native declarations across the decoded script
inheritance graph, then assigns a typed `(script, function)` target to method,
parent, and static call sites. Receiver types come from parameters, locals,
variables, automatic properties, `self`, and inherited declarations. The
result feeds the [Papyrus native registry](/engine/papyrus-vm.md) without
guessing from operand spelling.

The M11.1 retail gate observed 686 native declarations and 65,477 typed native
references. Those call sites name 508 distinct native pairs; 18 are present in
the standard registry, for 3.5% coverage. Counts and case-preserving rankings
remain evidence about the installed corpus, while dispatch lookup itself is
case-insensitive.

## Scope

This decoder is Skyrim-only. Fallout 4 additions documented on the same UESP
page, including structs and their newer debug metadata, are deliberately
outside M11. Execution semantics, scheduling and native function behavior
remain outside the container parser. The typed census is its read-only bridge
to those consumers.
