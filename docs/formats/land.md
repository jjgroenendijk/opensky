---
type: File Format
title: Terrain records (LAND, LTEX, TXST)
description: Byte layouts of the landscape, land-texture, and texture-set records.
tags: [format, plugin, records, terrain, land]
---

# Terrain records (LAND, LTEX, TXST)

Three records describe the ground:

- `LAND` holds one cell's heights, normals, colors, and texture layers.
- `LTEX` is a landscape texture. It names a texture set, a material, and grass.
- `TXST` is a texture set. It names the texture files.

Sources: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format), pages
`LAND`, `LTEX`, and `TXST`. Checked against xEdit `dev-4.1.6` `wbDefinitionsCommon.pas`
(`wbLAND`, `wbLTEX`, `wbTXST`).

Unknown fields are skipped. A field with the wrong size is an error.

## LAND

`LAND` sits in the temporary-children group of its cell (group type 9). It is almost always
compressed (record flag bit 18).

A cell is a grid of 33 x 33 vertices. 32 quads of 128 units cover the 4096-unit cell. Rows go
from south to north, and columns from west to east. Grid fields are stored row by row in that
order. The cell has four quadrants, each a 17 x 17 sub-grid: 0 bottom-left, 1 bottom-right,
2 top-left, 3 top-right.

| Field | Size | Meaning |
| --- | --- | --- |
| `DATA` | 4 | Flags, uint32 |
| `VHGT` | 1096 | Heights |
| `VNML` | 3267 | Normals, 33 x 33 int8 (x, y, z) |
| `VCLR` | 3267 | Vertex colors, 33 x 33 uint8 (r, g, b). Optional |
| `BTXT` | 8 | Base texture of one quadrant |
| `ATXT` | 8 | Header of one extra texture layer |
| `VTXT` | 8 x N | Alpha values of the `ATXT` before it |

`MPCD` (multi-pass color data, rare) is not read.

Neighbor cells share their edge vertices. Row 32 of cell (x, y) equals row 0 of cell
(x, y+1). Column 32 of (x, y) equals column 0 of (x+1, y). This was confirmed on vanilla
cells near Whiterun: the shared edges match exactly.

## VHGT heights

`VHGT` is a float32 start value, then 33 x 33 int8 steps, then 3 unused bytes
(4 + 1089 + 3 = 1096). Each height is a running sum of steps:

- Column 0 of a row is a step from column 0 of the row before. Row 0 steps from the start
  value.
- Columns 1 to 32 add their steps from west to east, starting at column 0 of the row.
- The height in game units is the sum times 8.

```text
columnZero = start
for row in 0..<33:
    columnZero += step[row][0]
    running = columnZero
    height[row][0] = running * 8
    for col in 1..<33:
        running += step[row][col]
        height[row][col] = running * 8
```

Oblivion and Morrowind use the same scheme. In the vanilla Tamriel worldspace, heights run
from -37032 to 39392 units.

## Texture layers

`BTXT` and `ATXT` share an 8-byte header:

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | uint32 | `LTEX` FormID |
| 4 | uint8 | Quadrant, 0 to 3 |
| 5 | uint8 | Unused |
| 6 | int16 | Layer number |

`BTXT` is the base texture of a quadrant. Each `ATXT` adds one layer and is followed by its
`VTXT`. A `VTXT` is a list of 8-byte entries: uint16 position (0 to 288 on the 17 x 17
quadrant grid), uint16 unused, float32 opacity (0 to 1). Only painted vertices are listed.
The layer number sets the blend order.

In vanilla Tamriel, a cell has up to 23 extra layers across its four quadrants, about 6 per
quadrant. The largest `VTXT` position is 288, as the grid size predicts.

## LTEX

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `TNAM` | FormID | The `TXST` to draw |
| `MNAM` | FormID | The material (`MATT`) of this ground |
| `GNAM` | FormID | A `GRAS` record. Repeats, in order |

`GNAM` feeds [grass placement](/engine/grass.md). `MNAM` gives footsteps their material on
open ground, because `LAND` has no collision mesh to carry one (see
[material types](/formats/material-type.md)). Each ground point takes the material of its
heaviest texture.

Not read: `HNAM` (Havok friction and restitution), `SNAM` (specular exponent), `INAM` (snow
flag).

## TXST

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `TX00` | zstring | Diffuse (color) map |
| `TX01` | zstring | Normal and gloss map |

Paths are relative to `Data/`, for example `textures\...`, and go through the
[VFS](/formats/vfs.md). Not read: `TX02` to `TX07` (other maps), `DODT` (decal data), `DNAM`
(flags). Terrain needs only the diffuse and normal maps.
