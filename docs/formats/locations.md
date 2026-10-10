---
type: File Format
title: Locations (LCTN, LCRT, CELL XLCN)
description: Location records, reference types, parent and keyword lookup, and cell links.
tags: [format, plugin, records, locations, formid, quests]
---

# Locations (LCTN, LCRT, CELL XLCN)

An `LCTN` record names a place, for example `WhiterunLocation`. It links to a parent
location, keywords, cells, actors, and references with a role. It has no geometry. `WRLD`
and `CELL` still hold the physical world. An `LCRT` record names a reference role used
inside a location, for example `BossContainer`.

References: UESP [LCTN](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LCTN),
[LCRT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LCRT), and
[CELL](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL); xEdit `dev-4.1.6`,
`Core/wbDefinitionsTES5.pas`, `wbRecord(LCTN, ...)` and `wbRecord(LCRT, ...)`.

## Single fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Display name |
| `KSIZ` / `KWDA` | uint32 + FormID list | Keywords |
| `PNAM` | `LCTN` FormID | Parent location |
| `NAM1` | `MUSC` FormID | Music |
| `FNAM` | `FACT` FormID | Faction for unreported crime |
| `MNAM` / `RNAM` | reference FormID + float32 | World marker and its radius |
| `NAM0` | `REFR` FormID | Horse marker |
| `CNAM` | 4 x uint8 RGBA | Creation Kit color |

`LCRT` has the same shape as `KYWD`: an optional `EDID` and an editor-only `CNAM`. See
[keywords](/formats/keywords.md).

## Packed arrays

These fields are lists of fixed-size elements. The field size divided by the stride gives
the count.

| Fields | Stride (bytes) | Element |
| --- | --- | --- |
| `ACPR` / `LCPR` | 12 | Reference, world or cell, int16 grid Y, int16 grid X |
| `RCPR` | 4 | Removed reference |
| `ACUN` / `LCUN` | 12 | `NPC_`, `ACHR`, and `LCTN` FormIDs |
| `RCUN` | 4 | Removed actor |
| `ACSR` / `LCSR` | 16 | `LCRT`, reference, world or cell, int16 grid Y, int16 grid X |
| `RCSR` | 4 | Removed special reference |
| `ACEC` / `LCEC` / `RCEC` | 4 + 4n | `WRLD`, then int16 grid Y and X pairs |
| `ACID` / `LCID` | 4 | Reference that starts disabled |
| `ACEP` / `LCEP` | 12 | Reference, enable parent, flags byte, 3 unused bytes |

OpenSky reads whole elements only and ignores a partial tail. On the vanilla load order no
field has a partial tail.

## Parents and keywords

A location is inside itself and inside every location up its `PNAM` chain. The chain can
loop in a broken plugin, so the walk stops at a location it has already seen.

A keyword question also looks at the parents. Real data shows why this matters:
`WhiterunLocation` does not carry `LocTypeHold`, but its parent `WhiterunHoldLocation`
does. So "is `WhiterunLocation` a hold?" is true. The full chain is
`WhiterunLocation -> WhiterunHoldLocation -> TamrielLocation`.

## Cell link

`CELL XLCN` is a 4-byte `LCTN` FormID. It says which location a cell belongs to.

Most exterior cells have no `XLCN`. For those, the location lists the cell itself: its
`LCEC` and `ACEC` lists name a worldspace and grid cells, and `RCEC` removes cells again.
On the install, `HelgenLocation` lists its 8 town cells in `LCEC`, and
`FalkreathHoldLocation` lists none. So OpenSky reads `XLCN` first, then the cell lists.
When two locations list one cell, the one deeper in the `PNAM` chain wins, so a town wins
over its hold. [WARNING] That tie rule is inferred, not taken from an open spec. A cell
that no location claims has no location.

## Quest aliases

A quest alias (`ALLS`) with an `ALFL` field names one `LCTN` directly. OpenSky fills the
alias with that location. The save file stores these fills in the `QLOC` chunk, separate
from the `QALS` chunk for reference aliases. Older readers can then skip `QLOC`. See
[OpenSky save](/formats/opensky-save-world-chunks.md).
