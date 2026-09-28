---
type: Subsystem
title: Terrain mesh build
description: How a LAND record becomes four terrain patches with blended texture layers, where
  terrain sits in the world, the fallback plane, and why cell edges weld exactly.
tags: [engine, world, terrain, rendering, esm]
---

# Terrain mesh build

A [LAND](/formats/land.md) record becomes up to four terrain patches, one per cell quarter. Each
patch has a base texture and up to eight blended layers. The splat pipeline draws them under the
cell's objects ([scene drawing](/rendering/scene-drawing.md)).

## Grid

An exterior cell is 4096 units wide: 32 quads of 128 units, so a 33 x 33 vertex grid. Vertex
(column c, row r) is at `(c * 128, r * 128, height)`, with +X east, +Y north, +Z up
([coordinates](/decisions/coordinates.md)). Row 0 is the south edge and column 0 the west edge.
The height is used as the decoder gives it. It is already scaled by 8.

- Normals: `VNML` bytes divided by 127, then normalized. A missing or zero normal is up (0, 0, 1).
- Colors: `VCLR` bytes divided by 255. Missing is white.
- UVs: `(c, r) / 2`, so a texture repeats every 2 quads. The real game's tiling is not
  confirmed. This value looks right at Whiterun.
- Winding: two triangles per quad, `SW, SE, NE` and `SW, NE, NW`. That is counter-clockwise seen
  from above, the pipeline's front face.

## One patch per quarter

The cell splits into four 17 x 17 quarters that share the middle row and column (index 16):
0 south-west, 1 south-east, 2 north-west, 3 north-east.

`LAND` gives the base texture and the layer stack per quarter. So one mesh and one draw per
quarter match the format exactly. Neighbor quarters repeat the shared edge vertices at the same
positions, so there is no crack.

For each quarter:

- Layers are sorted by their `ATXT` layer number. This is the blend order.
- Each layer's sparse `VTXT` opacities are spread over the 17 x 17 grid. A `VTXT` position from
  0 to 288 is a row-major index into the quarter, which is the same order the vertices are
  written. A position out of range is dropped. Opacities are clamped to 0 to 1.
- Layer weights go into a per-vertex stream of two float4 values, at most 8 layers.

A land texture resolves through `LTEX` `TNAM` to `TXST` `TX00`. The path is normalized the same
way as NIF texture paths, so terrain and objects share one texture cache. A missing base texture
gives the fallback material. A broken layer is dropped with its weight, and the other weights stay
in line. The cell summary counts drawn and dropped layers. Normal maps (`TX01`) are not used yet.

A cell's `XCLC` quad flags `0x1` to `0x8` hide the matching quarter. A hidden quarter has no
mesh.

## Placement

The cell's south-west corner goes to `(gridX * 4096, gridY * 4096, 0)`. So a vertex lands at its
real world position, in the same frame as reference positions. Terrain feeds the cell's bounds
like any other object.

[Grass](/engine/grass.md) uses the same height triangles, colors, hidden quarters, and layer
blending. One source of truth keeps grass on the ground, and off textures that were painted
over.

## Fallback plane

An exterior cell with no `LAND` gets a flat 33 x 33 plane at the worldspace's default land height,
the first float of `WRLD` `DNAM`. Tamriel's is -27000. If `DNAM` is missing, OpenSky draws no
ground. It does not guess a height. What the game does in that case is not confirmed.

## Cell edges weld exactly

UESP says a cell's grid overlaps its neighbors: row 32 of (x, y) equals row 0 of (x, y + 1), and
column 32 equals column 0 of (x + 1, y). The vanilla data agrees: in the Whiterun area, shared
edges match exactly. So neighbor cells join with no gaps, and streaming can drop one cell's
shared row instead of averaging.

`openskycli render --neighbors` draws a cell with its 8 neighbors, to check the joins
([CLI](/tools/cli.md)).
