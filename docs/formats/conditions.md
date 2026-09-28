---
type: File Format
title: Conditions (CTDA, CITC, CIS1, CIS2)
description: The shared 32-byte CTDA condition payload, its count and string fields, and how
  OpenSky decodes bad input without failing.
tags: [format, esm, conditions]
---

# Conditions (CTDA, CITC, CIS1, CIS2)

A condition is a test: "is this true right now?" Many record types use it: quests, dialogue,
packages, music, perks, and magic effects. They all use the same `CTDA` field, so one decoder
serves them all. How OpenSky answers a condition is on the
[condition evaluation](/engine/condition-evaluation.md) page.

Sources:

- UESP [CTDA Field](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CTDA_Field). The page
  is `CTDA_Field`. The page named only `CTDA` is empty.
- xEdit `wbDefinitionsTES5.pas`, `wbCTDA` and the code around it.
- Creation Kit wiki [Conditions](https://ck.uesp.net/wiki/Category:Conditions).

## CTDA payload (32 bytes)

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint8 | Operator (top 3 bits) and flags (low 5 bits) |
| 1 | 3 bytes | Unused. Can hold garbage |
| 4 | float32 or FormID | Comparison value. A `GLOB` FormID when the "use global" flag is set |
| 8 | uint16 | Function index |
| 10 | 2 bytes | Padding. Can hold garbage |
| 12 | 4 bytes | Parameter 1. Its type depends on the function |
| 16 | 4 bytes | Parameter 2. Its type depends on the function |
| 20 | uint32 | Run-on type |
| 24 | FormID | Reference. Used only when the run-on type is "reference" |
| 28 | int32 | Parameter 3. -1 when unused |

The function decides how to read the two parameters. The decoder does not look at the function
table. It keeps both words raw, and the evaluator reads them later. So a plugin that names an
unknown function still decodes.

The stored function index is the Creation Kit number minus 4096. Example: the Creation Kit
calls `GetWantBlocking` function 4096. On disk it is 0. OpenSky keeps the stored value.

xEdit names offset 28 "Parameter #3". UESP says it is the index of the package data or quest
alias to run on. Both describe the same bytes.

## Operator and flags

The operator is byte 0 shifted right by 5.

| Value | Operator |
| --- | --- |
| 0 | Equal to |
| 1 | Not equal to |
| 2 | Greater than |
| 3 | Greater than or equal to |
| 4 | Less than |
| 5 | Less than or equal to |
| 6, 7 | Not defined |

| Bit | Flag |
| --- | --- |
| `0x01` | OR with the next condition, instead of AND |
| `0x02` | Use aliases: reference parameters are quest alias numbers |
| `0x04` | Use global: the comparison value is a `GLOB` FormID |
| `0x08` | Use package data: reference parameters are package data indices |
| `0x10` | Swap subject and target |

`0x02` and `0x08` never appear together. UESP puts a question mark on the swap flag. xEdit
names it with no doubt.

## Run-on type

The run-on type says which object the function tests.

| Value | Run on |
| --- | --- |
| 0 | Subject |
| 1 | Target |
| 2 | Reference (the FormID at offset 24) |
| 3 | Combat target |
| 4 | Linked reference |
| 5 | Quest alias |
| 6 | Package data |
| 7 | Event data |

## Count and string fields

`CITC` is a uint32: how many `CTDA` fields follow. It is optional on `FACT` and `MUST`. It is
required on `SMBN`, `SMQN`, `SMEN`, and in each `PACK` procedure branch, even when the count is
0. So `CITC` does not tell you whether a record has conditions.

`CITC` counts one run of conditions, not all conditions in the record. In vanilla, some records
have more `CTDA` fields than their `CITC` says, and all of them are `PACK`. The `CITC` counts
the package's own conditions. The other `CTDA` fields belong to package data blocks inside it.
So OpenSky keeps the declared count as information, but always uses the conditions it decoded.

`CIS1` and `CIS2` are zero-terminated strings. They replace parameter 1 and parameter 2 of the
`CTDA` just before them. The raw parameter word then has no meaning. The string names a quest
alias. It is matched without regard to case, as the Creation Kit does.

## Decoding bad input

Mod data is not trusted, so the decoder does not throw:

- A `CTDA` that is not exactly 32 bytes is skipped. The other fields still decode.
- Operators 6 and 7, and run-on values above 7, are kept raw.
- A `CIS1` or `CIS2` whose `CTDA` was skipped is dropped.
- A `CITC` of the wrong size is ignored.
- The reference at offset 24 is never checked.

Each record decoder passes the fields it does not know to one shared condition decoder. That
decoder takes only condition fields, so the record keeps reading its own fields after a
condition run.

## Vanilla facts

- Every vanilla `CTDA` is 32 bytes. None has an unknown operator or run-on type. The raw cases
  exist only for mods.
- Function index 0 is present. This confirms the -4096 offset, because Creation Kit numbers
  start at 4096.
- The reference at offset 24 is 0 on every condition whose run-on type is not "reference". So
  xEdit's "ignored" mark on the field is a tolerance for mods.
- `INFO` records carry by far the most conditions, then `PACK`, `IDLE`, and `QUST`.
