---
type: Subsystem
title: Terrain mesh build
description: LAND height field -> per-quadrant engine meshes placed under a cell's objects,
  base textures via the existing static pipeline; fallback plane, placement math, probes.
tags: [engine, world, terrain, rendering, esm]
timestamp: 2026-07-18T00:00:00Z
---

# Terrain mesh build

`opensky/World/TerrainMeshBuilder.swift` turns a decoded [LAND](/formats/land.md) record into
engine `Mesh`/`Model` values; `CellSceneBuilder` places them under the cell's objects and
draws them through the existing single-texture static pipeline (todo 3.1, first half). Splat
blending (ATXT/VTXT layers) is the next commit — this stage draws each quadrant's BTXT base
texture only.

## Topology

One exterior cell = 4096 game units per edge, 32 quads at 128 units each -> a 33x33 vertex
grid (`Land.dimension`). Vertex (col c, row r): local position `(c*128, r*128, height)` in
Skyrim Z-up world axes (+X east, +Y north, +Z up — [coordinates](/decisions/coordinates.md)).
Row 0 = south edge, col 0 = west edge (UESP LAND, row-major). Height is the LAND VHGT value
already `*8`-scaled by the decoder — used verbatim, no double scale.

- Normals: VNML int8 triples, `v/127` then normalized. Missing VNML or a degenerate zero
  triple -> `(0,0,1)` (up), no divide-by-zero.
- Colors: VCLR uint8 triples `/255` as RGBA (alpha 1); absent -> white.
- UVs: `(c, r) / uvQuadsPerRepeat`, `uvQuadsPerRepeat = 2`. The exact vanilla tiling density
  is UNCONFIRMED — this is a verifiable starting constant, tuned visually in the splat commit.
- Winding: two triangles per quad, `SW→SE→NE`, `SW→NE→NW` — counter-clockwise seen from
  above (+Z), the pipeline's front-face winding (matches the demo ground plane).

## Per-quadrant strategy

The cell splits into four 17x17 quadrants sharing the center row/col (index 16): 0 bottom-left
(SW), 1 bottom-right (SE), 2 top-left (NW... i.e. north-west), 3 top-right (NE). "bottom" =
south = low row, "left" = west = low col (docs/formats/land.md). Each quadrant becomes its own
sub-mesh with its own material slot.

Why per-quadrant now: each quadrant carries its own BTXT base texture, so one mesh per quadrant
lets the existing single-texture pipeline draw the right base per region today, and matches the
likely per-quadrant splat strategy later (each quadrant blends its own ATXT layer stack). The
shared center row/col means adjacent quadrants carry duplicate edge vertices — expected, not a
seam (positions are identical, so no crack).

Materials resolve BTXT (quadrant base) -> LTEX `TNAM` -> TXST `TX00` diffuse via
`ESMWalk.record(withFormID:in:)`. Paths are normalized through `NIFShaderTextureSet.vfsKey`
(same canonicalization the NIF material path takes: lowercase, `\`→`/`, `textures/` prefix
ensured) so terrain and object textures share the [VFS](/formats/vfs.md) + `TextureLibrary`
cache. A missing BTXT for a quadrant or any broken link in the chain -> `Material.fallback`
(TextureLibrary placeholders the unresolved texture). Normal maps (`TX01`) are resolved and
kept but not yet sampled — `RenderMaterial` loads diffuse only in the M2 material path.

Force-hidden quadrants: CELL `XCLC` quad-flags bits `0x1`-`0x8` hide the matching land quad
(UESP CELL). Hidden quadrants emit no mesh.

## Placement

`CellSceneBuilder.buildTerrain` puts the cell's south-west corner at world
`(gridX*4096, gridY*4096, 0)` via `MatrixMath.translation`, so vertex local `(c*128, r*128,
height)` lands at absolute world position — the same coordinate frame REFR placements use
(their DATA positions fall inside `[grid*4096, grid*4096+4096)`, verified in
[coordinates](/decisions/coordinates.md)). Terrain draws as opaque `DrawItem`s appended after
the object instances (so instancing-ready ref grouping is intact) and feeds the cell world AABB
(`ModelBounds` of the terrain model, transformed) like every other instance.

`CellLoadSummary.terrainQuadrantCount` records the drawn sub-mesh count (0-4 quadrants, or 1
fallback plane, else 0). The summary line appends `, N terrain quads` only when non-zero, so a
terrain-free cell logs byte-identically to before.

## Fallback plane

An exterior cell with no LAND record draws a flat 33x33 plane at the worldspace default land
height from WRLD `DNAM` (first float; Tamriel reads -27000). When `DNAM` is absent OpenSky
draws no ground at all rather than guess a floor height — the correct engine behavior in that
case is UNCONFIRMED (todo: probe). `TerrainMeshBuilder.fallbackModel(defaultLandHeight:)` itself
takes a plain height, so a caller that wanted a 0-height default could pass it; the builder
gates on `DNAM` presence today.

## Neighbor-edge overlap (streaming groundwork)

Spec (UESP LAND): a cell's 33x33 grid overlaps its neighbors — row 32 of (x,y) equals row 0 of
(x,y+1), col 32 equals col 0 of (x+1,y). Cross-cell stitching is not built here (streaming is
3.2); the claim is verified by `LandRealDataTests.adjacentCellEdgesMatch` (env-gated real-data
probe over Whiterun-area adjacent pairs).

Finding (vanilla Skyrim.esm, 2026-07-18): 4 adjacent Whiterun-area pairs checked, 0
mismatched edge vertices — shared edges match exactly. The overlap claim holds, so streaming
can weld neighbor cells by dropping one cell's shared row/col instead of averaging.

## Tests

- `openskyTests/TerrainMeshBuilderTests.swift` — synthetic LAND: grid->world mapping (128-unit
  quads, height passthrough), VNML normalization + zero/absent fallback, quadrant counts + shared
  edge vertices, per-quadrant material routing, hidden-quadrant omission, fallback-plane height.
- `openskyTests/CellSceneBuilderTests.swift` — synthetic plugin with a compressed LAND +
  LTEX/TXST chain: terrain draw items, resolved diffuse loaded from the VFS, XCLC quad-hiding,
  DNAM fallback plane, and no-terrain when neither LAND nor DNAM present.
- `openskyTests/LandRealDataTests.swift` — env-gated edge-overlap probe (above).
