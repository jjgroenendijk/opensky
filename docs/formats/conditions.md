---
type: File Format
title: Conditions (CTDA, CITC, CIS1, CIS2)
description: The shared 32-byte CTDA condition payload, its sibling count and string
  subrecords, and OpenSky's decode-only policy.
tags: [format, plugin, conditions]
timestamp: 2026-07-28T00:00:00Z
---

# Conditions (CTDA, CITC, CIS1, CIS2)

A condition is the shared "is this true right now?" test that Skyrim attaches to
dozens of record types. Quests, dialogue, packages, music, perks, and magic
effects all gate behavior through the same `CTDA` subrecord, so one decoder
serves all of them.

This page documents the on-disk layout only. Evaluating a condition — resolving
the function index through a registry, applying comparison and OR-grouping
semantics, and binding a run-on target — is a separate concern that OpenSky does
not implement yet.

## Contents

* [CTDA payload](#ctda-payload)
* [Comparison operator and flags](#comparison-operator-and-flags)
* [Run-on type](#run-on-type)
* [Sibling subrecords](#sibling-subrecords)
* [Decode policy](#decode-policy)
* [Observed in Skyrim.esm](#observed-in-skyrimesm)
* [References](#references)
* [See also](#see-also)

Decoder: `Condition` and `ConditionList` in
`opensky/Formats/ESM/Records/Condition.swift`. `MusicTrack` is the first
consumer; other record types adopt the same accumulator as they land.

## CTDA payload

Every `CTDA` payload is exactly 32 bytes, little-endian.

| offset | size | on-disk type | field | notes |
| --- | --- | --- | --- | --- |
| 0 | 1 | uint8 | operator and flags | top 3 bits comparison operator, low 5 bits flags |
| 1 | 3 | bytes | unused | may hold nonzero garbage, never validated |
| 4 | 4 | float32 or FormID | comparison value | a `GLOB` FormID when the use-global flag is set, otherwise a float |
| 8 | 2 | uint16 | function index | stored already offset by -4096 against Creation Kit numbering |
| 10 | 2 | bytes | padding | may hold nonzero garbage, never validated |
| 12 | 4 | raw word | parameter #1 | typed per function; kept raw |
| 16 | 4 | raw word | parameter #2 | typed per function; kept raw |
| 20 | 4 | uint32 | run-on type | see below |
| 24 | 4 | FormID | reference | meaningful only when the run-on type is Reference |
| 28 | 4 | int32 | parameter #3 | -1 when unused |

The function index decides how the two parameter words and the comparison value
should be read, and OpenSky has no function registry yet, so `Condition` stores
both parameters verbatim as a `Parameter` wrapper exposing `asFloat`,
`asFormID`, and `asInt32`. Callers reinterpret a word once they know the
function.

The -4096 offset is a numbering difference, not an encoding one: the Creation
Kit documents `GetWantBlocking` as function 4096, and the same function is
stored as 0 on disk. OpenSky keeps the raw on-disk value and does not adjust it.

The field at offset 28 is named "Parameter #3" by xEdit and described by UESP as
the index of the package data or quest alias to run on. The two readings cover
the same bytes; OpenSky stores the signed value without interpreting it.

## Comparison operator and flags

The operator occupies the top 3 bits of byte 0, so the enumerated value is the
byte shifted right by five.

| value | operator |
| --- | --- |
| 0 | equal to |
| 1 | not equal to |
| 2 | greater than |
| 3 | greater than or equal to |
| 4 | less than |
| 5 | less than or equal to |
| 6, 7 | undefined |

The low 5 bits are flags.

| bit | meaning |
| --- | --- |
| `0x01` | OR with the next condition instead of AND |
| `0x02` | use aliases: reference-typed parameters are quest alias indices |
| `0x04` | use global: the comparison value is a `GLOB` FormID |
| `0x08` | use pack data: reference-typed parameters are package data indices |
| `0x10` | swap subject and target |

Flags `0x02` and `0x08` are mutually exclusive. UESP marks the swap flag with a
question mark; xEdit names it without qualification.

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

## Sibling subrecords

`CITC` is a uint32 stating how many `CTDA` fields follow it. It is optional on
`FACT` and `MUST`, and required on `SMBN`, `SMQN`, `SMEN`, and inside each
`PACK` procedure-tree branch — required even when the count is zero, so `CITC`
presence correlates poorly with `CTDA` presence.

`CIS1` and `CIS2` are zero-terminated strings that override parameter #1 and
parameter #2 of the immediately preceding `CTDA`. When one is present the
corresponding raw parameter word in the `CTDA` is arbitrary and carries no
meaning.

## Decode policy

Plugin data from mods is not trustworthy, so the decoder degrades instead of
throwing:

* A `CTDA` payload that is not exactly 32 bytes is skipped. `Condition.init?`
  returns nil rather than throwing, and the surrounding fields decode normally.
* Operator values 6 and 7, and run-on values above 7, round-trip through an
  `unknown` case that keeps the raw byte or word.
* A `CIS1` or `CIS2` with no preceding condition — because the `CTDA` it
  belonged to was skipped — is dropped.
* A wrong-width `CITC` is consumed and ignored.
* The reference word at offset 24 is never validated, in any run-on type.

`ConditionList` is the accumulator each record decoder forwards its unmatched
fields to. Its `decode(field:)` returns false for anything that is not part of a
condition run, so an owning record keeps matching its own fields afterwards and
no record type reimplements this logic.

The declared `CITC` count is recorded as `declaredCount` but never trusted over
the `CTDA` fields actually decoded, for the reason in the next section.

## Observed in Skyrim.esm

`ConditionRealDataTests` sweeps every record in the shipped `Skyrim.esm` and
decodes every `CTDA` it finds. Observed 2026-07-28 against the retail Special
Edition install: 83,759 conditions over 32,501 records, with zero skipped
payloads and zero errors. No unknown operator and no unknown run-on value
appears in vanilla data, so both `unknown` cases exist purely for mod tolerance.

Carriers, by condition count: `INFO` 24,328, `PACK` 2,442, `IDLE` 1,757, `QUST`
1,307, `COBJ` 526, `SCEN` 498, `SMQN` 379, `PERK` 338, `MGEF` 318, `SNDR` 198,
`SPEL` 106, `SMBN` 78. Of those conditions, 1,681 use a global comparison value,
11,666 carry the OR flag, and 4,774 carry a `CIS1` or `CIS2` override.

Raw function indices span 0 to 726 across 244 distinct values. Index 0 being
present confirms the on-disk -4096 offset, since Creation Kit numbering starts
at 4096.

Two points the open references leave ambiguous were resolved by this sweep:

`CITC` counts one condition run, not every condition in the record. 142 records
disagree between their declared count and the number of `CTDA` fields present,
and every one of them is a `PACK`: the `CITC` covers the package's own
conditions while the remaining `CTDA` fields belong to nested package-data
blocks. The decoder therefore keeps the declared count as information and
always reports the conditions it actually decoded.

The reference word at offset 24 is clean in vanilla data. No condition whose
run-on type is anything other than Reference carries a nonzero reference,
so xEdit marking the field ignored is a tolerance allowance rather than
something the shipped plugin exercises. OpenSky still never validates it,
because mods may.

## References

* UESP, "Skyrim Mod:Mod File Format/CTDA Field" —
  <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CTDA_Field>. Note the
  page name is `CTDA_Field`; the bare `CTDA` page is empty.
* xEdit (TES5Edit), `wbDefinitionsTES5.pas`, `wbCTDA` and the surrounding
  deciders — <https://github.com/TES5Edit/TES5Edit>.

## See also

* [Music records (MUSC, MUST)](/formats/music.md) — the first record type to
  decode conditions through this model.
* [ESM plugin format](/formats/esm.md) — the record and field framing conditions
  arrive in.
* [FormID](/formats/formid.md) — how the comparison-value and reference FormIDs
  resolve against the load order.
