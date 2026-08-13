---
type: File Format
title: Locations (LCTN, LCRT, CELL XLCN)
description: Location records, reference types, parent and keyword traversal, and cell links.
tags: [format, plugin, records, locations, formid, quests]
timestamp: 2026-08-13T00:00:00Z
---

# Locations (LCTN, LCRT, CELL XLCN)

`LCTN` records name a logical place and connect it to parent locations, keywords, cells,
actors and typed references. They are not geometry: WRLD and CELL remain the physical world.
`LCRT` records name the reference roles used inside an LCTN, such as `BossContainer`.

References:

* UESP [LCTN](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LCTN),
  [LCRT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LCRT), and
  [CELL](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL).
* xEdit `dev-4.1.6`, `Core/wbDefinitionsTES5.pas`, `wbRecord(LCTN, ...)` and
  `wbRecord(LCRT, ...)`.

## Scalar fields

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | display name |
| `KSIZ` / `KWDA` | uint32 + FormID[] | keyword list |
| `PNAM` | LCTN FormID | parent location |
| `NAM1` | MUSC FormID | music |
| `FNAM` | FACT FormID | unreported-crime faction |
| `MNAM` / `RNAM` | reference FormID + float | world marker and radius |
| `NAM0` | REFR FormID | horse marker |
| `CNAM` | uint8 RGBA | editor colour |

LCRT uses the same optional `EDID` plus editor-only `CNAM` shape as KYWD and AACT.

## Packed arrays

| fields | stride | element |
| --- | --- | --- |
| `ACPR` / `LCPR` | 12 | reference, world-or-cell, int16 grid Y/X |
| `RCPR` | 4 | removed reference |
| `ACUN` / `LCUN` | 12 | NPC_, ACHR and LCTN FormIDs |
| `RCUN` | 4 | removed actor |
| `ACSR` / `LCSR` | 16 | LCRT, reference, world-or-cell, int16 grid Y/X |
| `RCSR` | 4 | removed special reference |
| `ACEC` / `LCEC` / `RCEC` | 4 + 4n | WRLD then int16 grid Y/X pairs |
| `ACID` / `LCID` | 4 | initially-disabled reference |
| `ACEP` / `LCEP` | 12 | reference, enable parent, flags byte, three unused bytes |

The decoder derives every count from payload size. It reads whole elements only and records
the number of trailing bytes it dropped per field type. The 2026-08-13 active-load-order
probe found no partial tail: every observed payload matched its documented stride.

## Store and hierarchy

`LocationStore` layers LCTN and LCRT lookup over `RecordIndex`. It accepts
`ResolvedFormID` or a case-insensitive editor ID, resolves every raw link relative to the
plugin definition carrying it, and applies later-plugin-wins precedence.

`isWithin(_:ancestor:)` follows PNAM and treats a location as within itself. Both it and
`hasKeyword(_:in:)` keep a visited set, so a self-parent or longer malformed cycle
terminates. Keyword queries include ancestors. Real data demonstrates why: the pinned
`WhiterunLocation` does not directly carry `LocTypeHold`, while its
`WhiterunHoldLocation` parent does; the store answers true for the child.

CELL `XLCN` is a four-byte LCTN FormID. `Cell.location` decodes it and
`LocationStore.location(containing:fromPlugin:)` resolves it to the winning location.

## Quest aliases and inspection

An ALLS alias with ALFL names one LCTN directly. `QuestAliasFiller` now stores that stable
location identity in `QuestAliasState`; condition-driven and ALFA-plus-ALRT searches remain
counted as `location alias`. Location fills persist in the additive `QLOC` save chunk,
separate from reference-target `QALS` entries so older readers can skip the new targets.

`RecordTextDump` decodes LCTN and LCRT. With a `KeywordStore` context, an LCTN summary shows
resolved keyword editor IDs rather than opaque FormIDs.

## Verification

Synthetic tests cover every packed family, partial tails, LCRT, parent containment, cycles,
ancestor keywords, cross-plugin overrides, CELL XLCN, ALFL filling, text dumps and the QLOC
round trip. The real-data gate collected at least 829 LCTN and 481 LCRT definitions, pins
`WhiterunLocation -> WhiterunHoldLocation -> TamrielLocation`, and measured the Skyrim.esm
location-alias tally from 892 before this change to 730 after 162 direct ALFL fills.
