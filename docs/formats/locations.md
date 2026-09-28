---
type: File Format
title: Locations (LCTN, LCRT, CELL XLCN)
description: Location records, reference types, parent and keyword lookups, and cell links.
tags: [format, plugin, records, locations, formid, quests]
---

# Locations (LCTN, LCRT, CELL XLCN)

An `LCTN` record names a place, such as a city or a dungeon. It links to a parent location,
keywords, cells, actors, and references. It holds no geometry. `WRLD` and `CELL` are still
the physical world. An `LCRT` record names a role that a reference plays inside a location,
for example `BossContainer`.

Sources: UESP [LCTN](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LCTN),
[LCRT](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/LCRT), and
[CELL](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL); xEdit `dev-4.1.6`,
`Core/wbDefinitionsTES5.pas`.

## Single fields

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `FULL` | lstring | Display name |
| `KSIZ`, `KWDA` | uint32, FormID list | Keywords |
| `PNAM` | `LCTN` FormID | Parent location |
| `NAM1` | `MUSC` FormID | Music |
| `FNAM` | `FACT` FormID | Faction for unreported crime |
| `MNAM`, `RNAM` | FormID, float | World marker and its radius |
| `NAM0` | `REFR` FormID | Horse marker |
| `CNAM` | uint8 RGBA | Editor color |

`LCRT` has the same shape as `KYWD`: an optional `EDID` and an editor-only `CNAM`.

## Packed arrays

These fields are arrays of fixed-size elements. The count comes from the field size.

| Fields | Element size | Element |
| --- | --- | --- |
| `ACPR`, `LCPR` | 12 | Reference, world or cell, int16 grid Y and X |
| `RCPR` | 4 | Removed reference |
| `ACUN`, `LCUN` | 12 | `NPC_`, `ACHR`, and `LCTN` FormIDs |
| `RCUN` | 4 | Removed actor |
| `ACSR`, `LCSR` | 16 | `LCRT`, reference, world or cell, int16 grid Y and X |
| `RCSR` | 4 | Removed special reference |
| `ACEC`, `LCEC`, `RCEC` | 4 + 4n | `WRLD`, then int16 grid Y and X pairs |
| `ACID`, `LCID` | 4 | Reference that starts disabled |
| `ACEP`, `LCEP` | 12 | Reference, enable parent, flags byte, three unused bytes |

OpenSky reads whole elements only and counts any extra bytes. In the vanilla load order no
field has extra bytes.

## Parents and keywords

A location is inside itself and inside every parent on its `PNAM` chain. A keyword check
also looks at the parents. Real data shows why: `WhiterunLocation` does not carry
`LocTypeHold`, but its parent `WhiterunHoldLocation` does. So "is `WhiterunLocation` in a
hold?" is true. Both walks stop on a loop.

A vanilla chain: `WhiterunLocation -> WhiterunHoldLocation -> TamrielLocation`.

## CELL XLCN

`CELL XLCN` is a 4-byte `LCTN` FormID. It says which location a cell belongs to.

## Quest aliases

A quest alias (`ALLS`) with an `ALFL` field names one `LCTN` directly. OpenSky fills that
alias with the location. Other location aliases, filled by conditions or by `ALFA` plus
`ALRT`, are not supported yet. Filled location aliases are saved in their own save chunk,
`QLOC`, so older readers can skip it (see [save format](/formats/opensky-save.md)).
