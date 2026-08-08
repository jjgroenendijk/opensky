---
type: File Format
title: Navmesh records (NAVM, NAVI)
description: NVNM navmesh geometry and the NAVI index map — byte layouts, the parent-cell
  union rule, what OpenSky decodes and what it deliberately skips.
tags: [format, plugin, records, navmesh, ai, pathing]
timestamp: 2026-08-08T00:00:00Z
---

# Navmesh records, Skyrim SE

The walkable surface an actor paths across. Two records carry it: `NAVM` holds one
navmesh's geometry and lives in the children group of the cell it covers, and the
single `NAVI` record holds a plugin-wide index saying which navmeshes exist, where
each one is, and which link to which.

Decoded by `opensky/Engine/Formats/ESM/Records/Navmesh.swift`,
`NavmeshGeometry.swift` and `NavmeshInfoMap.swift`, over the
[ESM container](/formats/esm.md). The plugin-wide store is
`opensky/Engine/World/NavmeshIndex.swift`; the per-cell walk is
`CellSceneBuilder.collectNavmeshes`.

## Contents

* References
* NAVM record
* NVNM geometry
* The parent-cell union
* NAVI record
* NVMI index entry
* What OpenSky skips
* Engine types
* Verification

## References

* UESP "Skyrim Mod:Mod File Format" subpages
  [`/NAVM`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NAVM),
  [`/NVNM Field`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVNM_Field),
  [`/NAVI`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NAVI),
  [`/NVMI Field`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVMI_Field),
  [`/NVPP Field`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVPP_Field).
* xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`: `wbNVNM` at line 5557,
  `wbRecord(NAVM, ...)` at 5655, `wbRecord(NAVI, ...)` at 5672. The union and
  counter callbacks are in `Core/wbDefinitionsCommon.pas`:
  `wbNavmeshGridCounter` (1643), `wbNAVIIslandDataDecider` (5329),
  `wbNAVIParentDecider` (5350), `wbNVNMParentDecider` (5372).
* Cross-checked against the user's own install by the census probe below.

Where the two sources disagree, xEdit won and the census confirmed it — see
"The parent-cell union".

## NAVM record

| field | type   | decoded                                   |
| ----- | ------ | ----------------------------------------- |
| EDID  | zstring| `editorID`, rarely authored               |
| NVNM  | struct | `geometry`; required                      |
| ONAM  | FormID[]| base objects — skipped                   |
| PNAM  | uint16[]| preferred connector vertices — skipped   |
| NNAM  | uint16[]| non-connector vertices — skipped         |

The record-header flags NAVM overloads are bit 26 "AutoGen" and bit 31
"Navmesh Gen Cell"; OpenSky reads neither. Bit 18 "Compressed" is handled by
`ESMRecord.fieldData()` like any other record.

NVNM in `Skyrim.esm` routinely exceeds the 16-bit field size, so it arrives
through the `XXXX` size-extension pair that `ESMField.parseAll` folds into the
following field. That code exists because of this record.

## NVNM geometry

Variable size. Every count is a uint32 immediately preceding its array, and
every array is tightly packed with no padding.

| offset | type      | meaning                                       |
| ------ | --------- | --------------------------------------------- |
| 0x00   | uint32    | version; 12 in every vanilla record           |
| 0x04   | uint32    | CRC32 of the literal `"PathingCell"`, constant |
| 0x08   | FormID    | parent worldspace, null on an interior        |
| 0x0C   | union     | parent CELL, or int16 grid Y then int16 grid X |
| then   | uint32 + array | vertices: float32 x, y, z each           |
| then   | uint32 + array | triangles, 16 bytes each                 |
| then   | uint32 + array | edge links, 10 bytes each                |
| then   | uint32 + array | door links, 10 bytes each                |
| then   | uint32 + array | cover triangles, int16 each              |
| then   | struct    | navmesh grid                                  |

Triangle, 16 bytes:

| offset | type   | meaning                                          |
| ------ | ------ | ------------------------------------------------ |
| 0x00   | uint16 | vertex 0                                         |
| 0x02   | uint16 | vertex 1                                         |
| 0x04   | uint16 | vertex 2                                         |
| 0x06   | int16  | triangle bordering edge 0-1, or -1               |
| 0x08   | int16  | triangle bordering edge 1-2, or -1               |
| 0x0A   | int16  | triangle bordering edge 2-0, or -1               |
| 0x0C   | uint16 | flags                                            |
| 0x0E   | uint16 | cover flags                                      |

Triangle flag bits, from xEdit `wbNavmeshTriangleFlags`: 0 edge 0-1 link, 1
edge 1-2 link, 2 edge 2-0 link, 3 deleted, 4 no large creatures, 5 overlapping,
6 preferred, 9 water, 10 door, 11 found. The three edge bits change what the
matching neighbour value indexes: with the bit set it is an index into this
navmesh's edge-link array, without it an index into the triangle array. OpenSky
range-checks against whichever the bit selects.

Edge link, 10 bytes: uint32 type, FormID of the neighbouring NAVM, int16
triangle. Types are 0 portal, 1 ledge up, 2 ledge down, 3 enable/disable
portal; an undocumented value is kept as `rawType`.

The triangle index belongs to the navmesh the link **names**, not to the mesh
carrying the link. Neither published source says so outright — UESP describes
it as "the triangle that connects to the external navmesh", which reads either
way. The census settled it: validating the value against the local triangle
array rejected more than half the vanilla navmeshes in the Whiterun area,
always on this field, with values far past the local count (triangle 466 in a
172-triangle mesh, and so on). xEdit agrees by omission, giving the door link's
triangle a `wbTriangleLinksTo` callback and this one none. Nothing local can
range-check it, so the decoder does not; the pathing graph resolves it against
the navmesh it names.

Door link, 10 bytes: int16 triangle, uint32 CRC32 of `"PathingDoor"`, FormID of
the DOOR REFR.

Navmesh grid: uint32 divisor, float32 grid size X and Y, float32[3] bounds
minimum, float32[3] bounds maximum, then `divisor * divisor` lists of
(uint32 count + count int16 triangle indices). A divisor outside `0...12` means
no lists follow, matching xEdit's `wbNavmeshGridCounter`.

## The parent-cell union

The four bytes at 0x0C are either a CELL FormID or a pair of int16 grid
coordinates, and the two published sources disagree on which:

* xEdit `wbNVNMParentDecider` switches on the parent worldspace being **null**:
  null means interior, so a CELL FormID follows; otherwise the grid pair does.
* UESP claims the switch is the worldspace equalling `0x0000003C` (Tamriel),
  which cannot generalise to the other worldspaces.

OpenSky implements xEdit's rule. The census probe checks it directly: it walks
the target area, and for every navmesh compares the parent the NVNM payload
decodes to against the CELL the record was actually found under, and against
the NVMI entry NAVI holds for the same navmesh. All three agree.

The grid pair is stored Y first, the same reversal exterior-cell GRUP labels
use (see [ESM container](/formats/esm.md)).

## NAVI record

There is one NAVI record in `Skyrim.esm`.

| field | type    | decoded                                         |
| ----- | ------- | ----------------------------------------------- |
| EDID  | zstring | `editorID`                                      |
| NVER  | uint32  | `version`; `0x0C`                               |
| NVMI  | struct  | one per navmesh, repeated; `infos`              |
| NVPP  | struct  | precomputed preferred pathing — tallied, skipped |
| NVSI  | FormID[]| `deletedNavmeshes`, no leading count            |

NVSI has no count of its own: the FormIDs fill the field.

NVPP is a uint32 path count followed by that many (uint32 FormID count + that
many NAVM FormIDs), then a uint32 road-marker count followed by that many
(FormID navmesh + uint32 index).

## NVMI index entry

| offset | type       | meaning                                      |
| ------ | ---------- | -------------------------------------------- |
| 0x00   | FormID     | the NAVM this entry describes                |
| 0x04   | uint32     | flags: bit 5 is-island, bit 6 not-edited     |
| 0x08   | float32[3] | approximate centre, in game units            |
| 0x14   | float32    | preferred-pathing percentage                 |
| then   | uint32 + FormID[] | navmeshes sharing an edge             |
| then   | uint32 + FormID[] | the preferred subset of those         |
| then   | uint32 + array | door links: uint32 CRC marker + REFR     |
| then   | uint8      | has-island-data                              |
| then   | struct     | island block, only when the byte is non-zero |
| then   | struct     | the same pathing-cell union NVNM opens with  |

The island block is float32[3] bounds minimum, float32[3] bounds maximum, a
counted array of 3 uint16 triangle vertex indices, and a counted array of
float32[3] vertices — a coarse summary mesh.

## What OpenSky skips

Skipped means named here and in the decoder's header, never silently dropped.

| skipped | why |
| ------- | --- |
| `NAVM` ONAM, PNAM, NNAM | base objects and connector-vertex hints; pathing (16.2) reads none of them |
| the two CRC-hash markers | constants the Creation Kit writes; nothing selects on them |
| cover-flag nibble layout | kept as a raw uint16; xEdit's own comment says the published bit names are wrong, and nothing reads cover yet |
| cover-triangle list | decoded and range-checked, then dropped; only `coverTriangleCount` is kept |
| navmesh-grid per-square lists | an acceleration structure for a query OpenSky does not run; divisor, extent and bounds are kept, the lists are tallied as `gridTriangleIndexCount` |
| NVMI island block | the coarse summary mesh; consumed to reach the pathing cell behind it, with `hasIslandData` kept |
| `NAVI` NVPP | a routing preference rather than a connectivity fact; tallied as `precomputedPathCount` and `roadMarkerCount` |

## Engine types

`Navmesh` is the record: FormID, optional editor ID, and a required
`NavmeshGeometry`. A NAVM with no NVNM throws — a navmesh with no surface is
structurally unusable, not an empty one.

`NavmeshGeometry` holds the decoded arrays plus `location`, a
`NavmeshLocation` (`.interior(cell:)` or `.exterior(world:x:y:)`).

`NavmeshInfo` is one NVMI entry and `NavmeshInfoMap` is the whole NAVI record.
`NavmeshIndex` is the plugin-wide store, built once in `CellProviderIndexes`
the way `MaterialTypeIndex` is: FormID to entry, location to navmeshes, plus
the NVSI deletion set. Geometry is deliberately not in the store — a navmesh's
vertices and triangles are decoded from its own cell through
`CellSceneBuilder.collectNavmeshes` when something needs them, which keeps the
cost off every cell build.

Defensive rules, both hard failures:

* Every count is checked against the bytes actually remaining before it sizes
  an allocation, so a corrupt count throws instead of asking for gigabytes.
* Every vertex, triangle, door, cover and grid index that points at something
  local is range-checked at decode time. An out-of-range index is a decode
  error here rather than a crash in the pathing graph later. The one index not
  checked is an edge link's triangle, which belongs to the navmesh the link
  names — see "NVNM geometry".

A malformed NVMI entry is the one exception: it is counted in
`malformedInfoCount` and skipped, because one bad index entry must not cost the
engine every other navmesh in the plugin.

## Verification

Synthetic decoder tests are `openskyTests/NavmeshRecordTests.swift` and
`NavmeshIndexTests.swift`, over fixtures built in code by
`openskyTests/NavmeshFixture.swift`: a two-triangle mesh, the interior and
exterior parent unions, an oversized payload forced through the `XXXX`
extension, truncated arrays, implausible counts, out-of-range vertex, neighbour
and door indices, and the skip policy for deleted and malformed records.

`openskyRealDataTests/NavmeshRealDataTests.swift` is the census over the user's
own install: it decodes every NAVM in the Whiterun target area — the hold's
interior cells, the WhiterunWorld city exteriors, and the Tamriel exteriors
around the first-render cell — and reports records, vertices, triangles, edge
links, door links, the skipped-subrecord tallies and the NAVI totals to
`logs/navmesh-census.log`. It fails on any decode failure, any NVNM/CELL or
NVNM/NVMI parent disagreement, and any navmesh absent from NAVI.

Run 2026-08-08 against vanilla `Skyrim.esm`:

| measure | value |
| ------- | ----- |
| NAVM records decoded, zero failures | 189 from 133 cells (149 exterior, 40 interior) |
| geometry | 24 113 vertices, 28 177 triangles |
| links | 2302 edge links (2274 portal, 14 ledge up, 14 ledge down), 96 door links |
| NVNM versions seen | 12 only |
| parent agreement | 0 NVNM/CELL, 0 NVNM/NVMI mismatches, 0 navmeshes absent from NAVI |
| skipped, decoded then dropped | 5527 cover triangles, 58 860 navmesh-grid triangle indices |
| NAVI | version 12, 15 462 NVMI entries, 0 malformed, 8664 islands, 1103 with doors, 0 NVSI deletions |
| NVPP, tallied only | 100 precomputed paths, 10 road markers |
