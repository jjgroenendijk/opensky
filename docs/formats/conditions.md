---
type: File Format
title: Conditions (CTDA, CITC, CIS1, CIS2)
description: The 32-byte CTDA condition payload, its count and string subrecords, and what
  the vanilla plugins contain.
tags: [format, plugin, conditions]
---

# Conditions (CTDA, CITC, CIS1, CIS2)

A condition is a "is this true right now?" test. Quests, dialogue, packages, music, perks,
magic effects, and many other records use the same `CTDA` subrecord. How OpenSky answers a
condition is on [condition evaluation](/engine/conditions.md). The functions it answers are
on [condition functions](/engine/condition-functions.md).

Sources:

- UESP, "Skyrim Mod:Mod File Format/CTDA Field"
  (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CTDA_Field>). The page name is
  `CTDA_Field`; the bare `CTDA` page is empty.
- xEdit (TES5Edit), `wbDefinitionsTES5.pas`, `wbCTDA` and the deciders around it
  (<https://github.com/TES5Edit/TES5Edit>).
- Creation Kit wiki, Conditions category (<https://ck.uesp.net/wiki/Category:Conditions>).

## CTDA payload

Every `CTDA` is exactly 32 bytes, little-endian.

| offset | size | type | field | notes |
| --- | --- | --- | --- | --- |
| 0 | 1 | uint8 | operator and flags | top 3 bits operator, low 5 bits flags |
| 1 | 3 | bytes | unused | may hold garbage |
| 4 | 4 | float32 or FormID | comparison value | a `GLOB` FormID when the use-global flag is set |
| 8 | 2 | uint16 | function index | Creation Kit number minus 4096 |
| 10 | 2 | bytes | padding | may hold garbage |
| 12 | 4 | raw word | parameter 1 | type depends on the function |
| 16 | 4 | raw word | parameter 2 | type depends on the function |
| 20 | 4 | uint32 | run-on type | see below |
| 24 | 4 | FormID | reference | used only when the run-on type is reference |
| 28 | 4 | int32 | parameter 3 | -1 when unused |

The function decides whether a parameter word is a FormID, an integer, or a float. So the
decoder keeps both words raw.

The -4096 offset is only a numbering difference. The Creation Kit calls `GetWantBlocking`
function 4096, and the plugin stores it as 0.

xEdit names the field at offset 28 "Parameter #3". UESP describes it as the index of the
package data or quest alias to run on. Both describe the same bytes.

## Operator and flags

The operator is byte 0 shifted right by five.

| value | operator |
| --- | --- |
| 0 | equal to |
| 1 | not equal to |
| 2 | greater than |
| 3 | greater than or equal to |
| 4 | less than |
| 5 | less than or equal to |
| 6, 7 | undefined |

The low 5 bits are flags:

| bit | meaning |
| --- | --- |
| `0x01` | OR with the next condition, instead of AND |
| `0x02` | use aliases: reference parameters are quest alias indices |
| `0x04` | use global: the comparison value is a `GLOB` FormID |
| `0x08` | use pack data: reference parameters are package data indices |
| `0x10` | swap subject and target |

Flags `0x02` and `0x08` never appear together. UESP marks the swap flag with a question
mark; xEdit names it without one.

## Run-on type

| value | run-on |
| --- | --- |
| 0 | subject |
| 1 | target |
| 2 | reference |
| 3 | combat target |
| 4 | linked reference |
| 5 | quest alias |
| 6 | package data |
| 7 | event data |

## CITC, CIS1, and CIS2

`CITC` is a uint32: the number of `CTDA` fields after it. It is optional on `FACT` and
`MUST`. It is required on `SMBN`, `SMQN`, `SMEN`, and in each `PACK` procedure-tree branch,
even when the count is zero. So `CITC` and `CTDA` do not always appear together.

`CITC` counts one condition run, not all conditions in the record. In `Skyrim.esm`, 142
records have a count that differs from the number of `CTDA` fields, and all are `PACK`. The
`CITC` counts the package's own conditions. The other `CTDA` fields belong to nested package
data blocks. So OpenSky trusts the `CTDA` fields it finds, not the count.

`CIS1` and `CIS2` are zero-terminated strings. They replace parameter 1 and parameter 2 of
the `CTDA` just before them. When one is present, the raw parameter word means nothing. The
string names a quest alias. The Creation Kit matches alias names without regard to case.

## Decode rules

Mods can contain bad data, so the decoder skips instead of failing:

- A `CTDA` that is not 32 bytes is skipped. The other fields still decode.
- Operator 6 or 7 and a run-on type above 7 are kept as unknown values.
- A `CIS1` or `CIS2` whose `CTDA` was skipped is dropped.
- A `CITC` of the wrong size is ignored.
- The reference word at offset 24 is never checked.

## Observed in Skyrim.esm

`Skyrim.esm` (retail Special Edition) has 83,759 conditions in 32,501 records. None has the
wrong size, an unknown operator, or an unknown run-on type.

Records with the most conditions: `INFO` 24,328, `PACK` 2,442, `IDLE` 1,757, `QUST` 1,307,
`COBJ` 526, `SCEN` 498, `SMQN` 379, `PERK` 338, `MGEF` 318, `SNDR` 198, `SPEL` 106,
`SMBN` 78. Of all conditions, 1,681 use a global comparison value, 11,666 have the OR flag,
and 4,774 have a `CIS1` or `CIS2`. The run-on type is subject for 77,007 conditions and
combat target for 419.

Function indices run from 0 to 726, with 244 different values. Index 0 is present, which
confirms the -4096 offset: Creation Kit numbers start at 4096.

The reference word at offset 24 is always zero unless the run-on type is reference. xEdit
marks the field as ignored for the other types, and vanilla never tests that. Mods might.

The whole active load order (`Skyrim.esm`, the update and DLC masters, four Creation Club
plugins, and `_ResourcePack.esl`) has 118,494 conditions using 258 different function
indices.

## GetRandomPercent is index 77

Two sources disagree on `GetRandomPercent`. xEdit's TES5 table gives stored index 77. The
older gib.me list implies 76. Vanilla data decides it:

- Stored index 76 does not appear in `Skyrim.esm`.
- Stored index 77 has 1,203 conditions. Every one has zero parameter words.
- Their comparison values run from 0.0 to 100.0, with 36 different values. 1,152 compare
  against a number from 0 to 100, and 51 of the rest compare against a global.

A function with no parameters, compared against a percentage, fits 77.
