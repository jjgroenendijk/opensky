---
type: File Format
title: Navmesh records (NAVM, NAVI)
description: NVNM navmesh geometry and the NAVI index, the parent-cell union rule, and what
  OpenSky skips.
tags: [format, plugin, records, navmesh, ai, pathing]
---

# Navmesh records (NAVM, NAVI)

A navmesh is the walkable surface that actors find paths on. Two records hold it:

- `NAVM` holds the geometry of one navmesh. It sits in the children group of the cell it
  covers.
- `NAVI` is one record per plugin. It lists every navmesh, where it is, and which navmeshes
  connect.

The runtime is on the [navigation](/engine/navigation.md) page.

Sources:

- UESP [NAVM](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NAVM),
  [NVNM Field](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVNM_Field),
  [NAVI](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NAVI),
  [NVMI Field](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVMI_Field),
  [NVPP Field](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NVPP_Field).
- xEdit `dev-4.1.6` `Core/wbDefinitionsTES5.pas`: `wbNVNM` (line 5557), `wbRecord(NAVM, ...)`
  (5655), `wbRecord(NAVI, ...)` (5672). In `Core/wbDefinitionsCommon.pas`:
  `wbNavmeshGridCounter` (1643), `wbNAVIIslandDataDecider` (5329), `wbNAVIParentDecider`
  (5350), `wbNVNMParentDecider` (5372).
- The user's install. Where the two sources disagree, xEdit was right and the real data
  confirmed it.

## NAVM

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID. Rarely set |
| `NVNM` | struct | Geometry. Required |
| `ONAM` | FormID list | Base objects. Skipped |
| `PNAM` | uint16 list | Preferred connector vertices. Skipped |
| `NNAM` | uint16 list | Non-connector vertices. Skipped |

Record header flags: bit 26 "AutoGen" and bit 31 "Navmesh Gen Cell". OpenSky reads neither.

`NVNM` in `Skyrim.esm` is often larger than 64 KB. So it comes after an `XXXX` size field (see
[ESM container](/formats/esm.md)).

A `NAVM` without `NVNM` is an error. A navmesh with no surface cannot be used.

## NVNM geometry

Each count is a uint32 right before its list. Lists have no padding.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | uint32 | Version. 12 in all vanilla records |
| 0x04 | uint32 | CRC32 of the text `"PathingCell"`. A constant |
| 0x08 | FormID | Parent worldspace. Null for an interior |
| 0x0C | union | Parent `CELL`, or int16 grid Y then int16 grid X |
| then | count + list | Vertices: float32 x, y, z |
| then | count + list | Triangles, 16 bytes each |
| then | count + list | Edge links, 10 bytes each |
| then | count + list | Door links, 10 bytes each |
| then | count + list | Cover triangles, int16 each |
| then | struct | Navmesh grid |

Triangle (16 bytes):

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | uint16 | Vertex 0 |
| 0x02 | uint16 | Vertex 1 |
| 0x04 | uint16 | Vertex 2 |
| 0x06 | int16 | Neighbor across edge 0-1, or -1 |
| 0x08 | int16 | Neighbor across edge 1-2, or -1 |
| 0x0A | int16 | Neighbor across edge 2-0, or -1 |
| 0x0C | uint16 | Flags |
| 0x0E | uint16 | Cover flags |

Flag bits (xEdit `wbNavmeshTriangleFlags`): 0 edge 0-1 link, 1 edge 1-2 link, 2 edge 2-0 link,
3 deleted, 4 no large creatures, 5 overlapping, 6 preferred, 9 water, 10 door, 11 found.

The three edge bits change what the neighbor value means. With the bit set, the value is an
index into this navmesh's edge-link list. Without it, the value is a triangle index.

xEdit says the published names of the cover flag bits are wrong. OpenSky keeps cover flags
raw.

## Edge and door links

Edge link (10 bytes): uint32 type, FormID of the neighbor `NAVM`, int16 triangle. Types: 0
portal, 1 ledge up, 2 ledge down, 3 enable/disable portal.

The triangle belongs to the navmesh the link names, not to the navmesh that holds the link.
Neither source says this clearly. UESP says "the triangle that connects to the external
navmesh", which can be read both ways. The real data decides it: checking the value against
the local triangle list rejects more than half the vanilla navmeshes near Whiterun, with
values far past the local count (for example triangle 466 in a mesh with 172 triangles).
xEdit agrees by omission: the door link's triangle has a `wbTriangleLinksTo` callback, and
this field has none. So this is the one index OpenSky cannot check at decode time.

Door link (10 bytes): int16 triangle, uint32 CRC32 of `"PathingDoor"`, FormID of the door
`REFR`.

## Navmesh grid

uint32 divisor, float32 grid size X and Y, float32 x 3 bounds minimum, float32 x 3 bounds
maximum, then `divisor * divisor` lists of (uint32 count, then int16 triangle indices). A
divisor outside 0 to 12 means no lists follow (xEdit `wbNavmeshGridCounter`).

The grid speeds up a lookup that OpenSky does not do. OpenSky keeps the divisor, size, and
bounds, and skips the lists.

## The parent-cell union

The four bytes at 0x0C are either a `CELL` FormID or two int16 grid coordinates. The sources
disagree on which:

- xEdit `wbNVNMParentDecider`: if the parent worldspace is null, it is an interior and a
  `CELL` FormID follows. Otherwise the grid pair follows.
- UESP: the switch is whether the worldspace is `0x0000003C` (Tamriel). That cannot work for
  other worldspaces.

OpenSky uses the xEdit rule. It was checked on real data: for each navmesh, the parent from
`NVNM`, the cell the record was found under, and the `NAVI` entry all agree.

The grid pair stores Y first, like exterior cell group labels.

## NAVI

`Skyrim.esm` has one `NAVI` record.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `NVER` | uint32 | Version, `0x0C` |
| `NVMI` | struct | One per navmesh. Repeats |
| `NVPP` | struct | Precomputed preferred paths. Skipped |
| `NVSI` | FormID list | Deleted navmeshes. No count: the FormIDs fill the field |

`NVPP` is a uint32 path count, then per path a uint32 FormID count and that many `NAVM`
FormIDs, then a uint32 road-marker count and per marker a navmesh FormID and a uint32 index.
It is a routing preference, not a connection fact, so OpenSky only counts it.

## NVMI entry

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | FormID | The `NAVM` described |
| 0x04 | uint32 | Flags: bit 5 island, bit 6 not edited |
| 0x08 | float32 x 3 | Approximate center |
| 0x14 | float32 | Preferred pathing percentage |
| then | count + FormID list | Navmeshes that share an edge |
| then | count + FormID list | The preferred ones among them |
| then | count + list | Door links: uint32 CRC marker, `REFR` FormID |
| then | uint8 | Has island data |
| then | struct | Island block, only if the byte is not 0 |
| then | union | The same parent-cell union as `NVNM` |

The island block is float32 x 3 bounds minimum, float32 x 3 bounds maximum, a counted list of
triangles (3 uint16 each), and a counted list of vertices (float32 x 3). It is a rough summary
mesh. OpenSky reads past it to reach the parent union.

A broken `NVMI` entry is counted and skipped. One bad entry must not lose every other navmesh.

## Bad input

- Every count is checked against the bytes left before it sizes a list. A broken count is an
  error, not a huge allocation.
- Every local index (vertex, triangle, door, cover, grid) is range-checked when decoded. A bad
  index is a decode error, not a crash in pathfinding later. The edge-link triangle is the one
  exception, as explained above.

## Vanilla facts

- Every `NVNM` is version 12.
- Near Whiterun, almost all edge links are portals. Ledge links are rare.
- `NVSI` is empty in `Skyrim.esm`.
