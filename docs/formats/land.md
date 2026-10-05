---
type: File Format
title: Terrain records (LAND, LTEX, TXST)
description: Byte layouts of Skyrim SE landscape, land texture, and texture set records.
tags: [format, plugin, records, terrain, land]
---

# Terrain records (LAND, LTEX, TXST)

Three records describe terrain:

- `LAND`: the heights, normals, colors, and texture layers of one cell.
- `LTEX`: a land texture. It names a texture set, a material, and grasses.
- `TXST`: a texture set, which is a list of texture file paths.

Reference: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format),
pages `/LAND`, `/LTEX`, `/TXST`. Checked against xEdit dev-4.1.6 `wbDefinitionsCommon.pas`
(`wbLAND`, `wbLTEX`, `wbTXST`).

## LAND

A `LAND` record sits in the temporary children group (type 9) of its cell. Real `LAND`
records are almost always zlib-compressed (see [ESM container](/formats/esm.md)).

A cell has a grid of 33 x 33 vertices. 32 squares of 128 game units cover the 4096-unit
cell. Rows go from south to north. Columns go from west to east. Grid fields store rows one
after another in that order. The cell has 4 quadrants: 0 bottom left, 1 bottom right, 2 top
left, 3 top right. Each quadrant is a 17 x 17 grid.

| Field | Size (bytes) | Meaning |
| --- | --- | --- |
| `DATA` | 4 | Flags, uint32 |
| `VHGT` | 1096 | Heights, below |
| `VNML` | 3267 | Normals: 33 x 33 x int8 (x, y, z) |
| `VCLR` | 3267 | Vertex colors: 33 x 33 x uint8 (r, g, b). Optional |
| `BTXT` | 8 | Base texture of one quadrant |
| `ATXT` | 8 | One extra texture layer |
| `VTXT` | 8 x N | Alpha map of the `ATXT` before it |

The grid of a cell overlaps its neighbors. Row 32 of cell (x, y) equals row 0 of cell
(x, y+1). Column 32 of (x, y) equals column 0 of (x+1, y). In vanilla Whiterun cells, the
shared edges match exactly.

### VHGT heights

`VHGT` is a float32 start value, 33 x 33 int8 steps, and 3 unused bytes (4 + 1089 + 3 =
1096). Each step is a change from the vertex before:

- Column 0 of a row changes from column 0 of the row below. Row 0 column 0 changes from the
  start value.
- Columns 1 to 32 change from the column to their west.
- The height in game units is the running value times 8.

```text
columnZero = anchor
for row in 0..<33:
    columnZero += delta[row][0]          # from the row below (row 0: from the anchor)
    running = columnZero
    height[row][0] = running * 8
    for col in 1..<33:
        running += delta[row][col]       # from the west
        height[row][col] = running * 8
```

Morrowind and Oblivion used the same scheme with scale 8. Vanilla Tamriel heights run from
-37032 to 39392 game units.

### Texture layers

`BTXT` and `ATXT` share an 8-byte header: uint32 `LTEX` FormID, uint8 quadrant (0 to 3),
uint8 unused, int16 layer number.

`BTXT` is the base texture of a quadrant. Each `ATXT` is one extra layer and is directly
followed by a `VTXT`. `VTXT` is a list of 8-byte entries: uint16 position (0 to 288 on the
17 x 17 quadrant grid), uint16 unused, float32 opacity (0 to 1). Only painted vertices are
listed. The layer number sets the blend order.

In vanilla Tamriel, a cell has up to 23 extra layers across its four quadrants, so about 6
per quadrant. The largest `VTXT` position is 288.

A null `LTEX` (FormID `00000000`) in a `BTXT` or `ATXT` is the default ground texture,
not a broken link. UESP `LAND` says the engine falls back to `dirt02.dds`. xEdit
dev-4.1.6 (`wbLANDTextureToStr` in `wbDefinitionsCommon.pas`) shows it as the `LTEX` with
editor ID `LDirt02` for Skyrim. OpenSky resolves a null `LTEX` to `LDirt02`, for the
texture, the grass, and the ground material.

OpenSky does not read `MPCD` (multi-pass color data, rare).

## LTEX

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `TNAM` | FormID | Texture set (`TXST`) |
| `MNAM` | FormID | Material (`MATT`) of the ground |
| `GNAM` | FormID | A grass (`GRAS`). Repeats, in order |

`GNAM` drives [grass placement](/engine/grass.md). See [grass records](/formats/grass.md).

Exterior ground is not a collision mesh, so it has no Havok material. `MNAM` gives its
material instead. For footsteps, OpenSky takes the texture with the most weight at a
vertex and uses its material. See [material types](/formats/material-type.md).

Not read yet: `HNAM` (Havok friction and restitution), `SNAM` (specular exponent), and
`INAM` (Skyrim SE snow flag).

## TXST

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `TX00` | zstring | Diffuse map |
| `TX01` | zstring | Normal map, with gloss |

Paths are relative to `Data/`, for example `textures\...`, and go through the
[VFS](/formats/vfs.md). Terrain needs only diffuse and normal maps. So OpenSky does not
read `TX02` to `TX07` (specular, environment, height, and other maps), `DODT` (decal data),
or `DNAM` (flags).
