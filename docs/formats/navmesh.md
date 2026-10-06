---
type: File Format
title: Navmesh records (NAVM, NAVI)
description: NVNM navmesh geometry and the NAVI index - byte layouts, the parent cell rule,
  and what OpenSky skips.
tags: [format, plugin, records, navmesh, ai, pathing]
---

# Navmesh records (NAVM, NAVI)

A navmesh is the walkable surface actors find paths on. Two records hold it:

- `NAVM` holds the geometry of one navmesh. It sits in the children group of the cell it
  covers.
- `NAVI` is one record per plugin. It lists every navmesh, where it is, and which navmeshes
  connect.

See [navigation](/engine/navigation.md) for path finding.

## References

- UESP [`/NAVM`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NAVM),
  [`/NVNM Field`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVNM_Field),
  [`/NAVI`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NAVI),
  [`/NVMI Field`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVMI_Field),
  [`/NVPP Field`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVPP_Field).
- xEdit dev-4.1.6 `Core/wbDefinitionsTES5.pas`: `wbNVNM` at line 5557, `wbRecord(NAVM, ...)`
  at 5655, `wbRecord(NAVI, ...)` at 5672. The helpers are in `Core/wbDefinitionsCommon.pas`:
  `wbNavmeshGridCounter` (1643), `wbNAVIIslandDataDecider` (5329), `wbNAVIParentDecider`
  (5350), `wbNVNMParentDecider` (5372).
- Checked against the vanilla navmeshes around Whiterun.

Where the two sources disagree, xEdit was right. See "The parent cell rule".

## NAVM

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID. Rarely set |
| `NVNM` | struct | Geometry. Required |
| `ONAM` | FormID list | Base objects |
| `PNAM` | uint16 list | Preferred connector vertices |
| `NNAM` | uint16 list | Non-connector vertices |

Header flags: bit 26 "AutoGen" and bit 31 "Navmesh Gen Cell". OpenSky reads neither.

In `Skyrim.esm`, `NVNM` is often larger than 64 KB. So it comes through the `XXXX` size
field (see [ESM container](/formats/esm.md)). A `NAVM` without `NVNM` is an error, because a
navmesh with no surface cannot be used.

## NVNM geometry

Every count is a uint32 directly before its array. Arrays have no padding.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | uint32 | Version. 12 in all vanilla records |
| 0x04 | uint32 | CRC32 of the text `"PathingCell"`. Always the same |
| 0x08 | FormID | Parent worldspace. Null for an interior |
| 0x0C | 4 bytes | Parent cell, or int16 grid Y and int16 grid X. See below |
| then | uint32 + array | Vertices: float32 x, y, z |
| then | uint32 + array | Triangles, 16 bytes each |
| then | uint32 + array | Edge links, 10 bytes each |
| then | uint32 + array | Door links, 10 bytes each |
| then | uint32 + array | Cover triangles, int16 each |
| then | struct | Navmesh grid |

Triangle, 16 bytes:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | uint16 | Vertex 0 |
| 0x02 | uint16 | Vertex 1 |
| 0x04 | uint16 | Vertex 2 |
| 0x06 | int16 | Neighbor across edge 0-1, or -1 |
| 0x08 | int16 | Neighbor across edge 1-2, or -1 |
| 0x0A | int16 | Neighbor across edge 2-0, or -1 |
| 0x0C | uint16 | Flags |
| 0x0E | uint16 | Cover flags. Kept raw |

Triangle flags (xEdit `wbNavmeshTriangleFlags`): 0 edge 0-1 link, 1 edge 1-2 link, 2 edge
2-0 link, 3 deleted, 4 no large creatures, 5 overlapping, 6 preferred, 9 water, 10 door, 11
found.

The three edge link bits change what the neighbor value means. With the bit set, it is an
index into this navmesh's edge links. Without it, it is an index into the triangles.
OpenSky checks the range against the right array. xEdit says the published names of the
cover flag bits are wrong, so OpenSky keeps cover flags as a raw number.

Edge link, 10 bytes: uint32 type, FormID of the other `NAVM`, int16 triangle. Types: 0
portal, 1 ledge up, 2 ledge down, 3 enable/disable portal. OpenSky keeps unknown types.

The triangle index of an edge link belongs to the navmesh the link names, not to this one.
No source says this clearly. UESP says "the triangle that connects to the external navmesh",
which can be read both ways. The real data decides it. When OpenSky checked the value
against the local triangles, more than half the Whiterun navmeshes failed, always on this
field, with values far too large (for example triangle 466 in a mesh of 172). xEdit agrees
indirectly: it gives the door link triangle a `wbTriangleLinksTo` check, and this one none.
So OpenSky does not range-check this value when decoding. Path finding checks it against
the named navmesh.

Door link, 10 bytes: int16 triangle, uint32 CRC32 of `"PathingDoor"`, FormID of the door
`REFR`.

Navmesh grid: uint32 divisor, float32 grid size X and Y, 3 x float32 minimum, 3 x float32
maximum, then `divisor * divisor` lists, each a uint32 count and that many int16 triangle
indices. A divisor outside 0 to 12 means no lists follow, as in xEdit's
`wbNavmeshGridCounter`.

## The parent cell rule

The 4 bytes at 0x0C are either a `CELL` FormID or a pair of int16 grid values. The sources
disagree on how to tell:

- xEdit (`wbNVNMParentDecider`): if the parent worldspace is null, it is an interior and a
  `CELL` FormID follows. Otherwise the grid pair follows.
- UESP: the switch is whether the worldspace is `0x0000003C` (Tamriel). This cannot work for
  other worldspaces.

OpenSky uses the xEdit rule. For every navmesh around Whiterun, the parent from `NVNM`, the
cell the record was found under, and the `NAVI` entry all agree.

The grid pair is Y first, like exterior cell group labels.

## NAVI

`Skyrim.esm` has one `NAVI` record.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `NVER` | uint32 | Version, `0x0C` |
| `NVMI` | struct | One entry per navmesh. Repeats |
| `NVPP` | struct | Precomputed preferred paths. Counted, not used |
| `NVSI` | FormID list | Deleted navmeshes. No count; the FormIDs fill the field |

`NVPP` is a uint32 path count, then per path a uint32 count and that many `NAVM` FormIDs.
Then a uint32 road marker count, then per marker a navmesh FormID and a uint32 index.

## NVMI entry

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | FormID | The `NAVM` |
| 0x04 | uint32 | Flags: bit 5 is island, bit 6 not edited |
| 0x08 | 3 x float32 | Rough center, game units |
| 0x14 | float32 | Preferred path percentage |
| then | uint32 + FormID list | Navmeshes that share an edge |
| then | uint32 + FormID list | The preferred ones among them |
| then | uint32 + array | Door links: uint32 CRC marker, `REFR` FormID |
| then | uint8 | Has island data |
| then | struct | Island data, only when the byte is not 0 |
| then | struct | The same parent cell field that `NVNM` has |

Island data: 3 x float32 minimum, 3 x float32 maximum, a counted list of triangles (3 x
uint16 vertex indices), and a counted list of vertices (3 x float32). It is a rough summary
mesh.

## What OpenSky skips

| Skipped | Why |
| --- | --- |
| The two CRC markers | Constant values. Nothing depends on them |
| Cover triangle list | Checked, then dropped. Nothing uses cover yet |
| Navmesh grid lists | A speed-up structure for a search OpenSky does not do. Size and bounds are kept |
| `NVMI` island data | Read only to reach the parent cell after it |
| `NAVI NVPP` | A route preference, not a connection. Counted only |

## Safety

- Every count is checked against the bytes left before it sizes an array. A broken count
  is an error, not a huge allocation.
- Every vertex, triangle, door, cover, and grid index that points inside this navmesh is
  range-checked. The only unchecked index is the edge link triangle (see above).
- A broken `NVMI` entry is counted and skipped. One bad entry must not lose every other
  navmesh.

## Vanilla navmeshes around Whiterun

The Whiterun hold interiors, the WhiterunWorld city, and the Tamriel cells around the first
render cell:

| Measure | Value |
| --- | --- |
| `NAVM` records | 189, from 133 cells, no errors |
| Geometry | 24,113 vertices, 28,177 triangles |
| Edge links | 2,302: 2,274 portal, 14 ledge up, 14 ledge down |
| Door links | 96 |
| `NVNM` versions | 12 only |
| `NAVI` | version 12, 15,462 entries, 8,664 islands, 1,103 with doors, no deletions |
| `NVPP` | 100 paths, 10 road markers |
