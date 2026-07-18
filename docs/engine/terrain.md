---
type: Subsystem
title: Terrain mesh build
description: LAND height field -> per-quadrant terrain patches with splat layers placed
  under a cell's objects; weight baking, texture resolution, fallback plane, placement math.
tags: [engine, world, terrain, rendering, esm]
timestamp: 2026-07-18T00:00:00Z
---

# Terrain mesh build

`opensky/World/TerrainMeshBuilder.swift` turns a decoded [LAND](/formats/land.md) record into
terrain `Patch` values — quadrant sub-mesh + BTXT base FormID + ATXT layers with dense-baked
VTXT opacities. `CellSceneBuilder.buildTerrain` resolves the textures, packs the splat
weights, and emits `TerrainDrawItem`s drawn by the dedicated splat pipeline
([metal4-renderer](/rendering/metal4-renderer.md), terrain splat section) under the cell's
objects (todo 3.1).

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
  is UNCONFIRMED — verifiable starting constant, visually plausible at Whiterun.
- Winding: two triangles per quad, `SW→SE→NE`, `SW→NE→NW` — counter-clockwise seen from
  above (+Z), the pipeline's front-face winding (matches the demo ground plane).

## Per-quadrant strategy

The cell splits into four 17x17 quadrants sharing the center row/col (index 16): 0 bottom-left
(SW), 1 bottom-right (SE), 2 top-left (NW... i.e. north-west), 3 top-right (NE). "bottom" =
south = low row, "left" = west = low col (docs/formats/land.md). Each quadrant becomes its own
sub-mesh with its own material slot.

Why per-quadrant: BTXT base and the ATXT layer stack are per-quadrant in LAND, so one mesh +
one splat draw per quadrant maps 1:1 onto the format. The shared center row/col means adjacent
quadrants carry duplicate edge vertices — expected, not a seam (positions are identical, so no
crack).

Splat inputs per quadrant (`TerrainMeshBuilder.Patch`):

- Layers filtered to the quadrant, sorted by ATXT layer number — the blend order (UESP LAND).
- `denseOpacities` bakes each layer's sparse VTXT onto the 17x17 grid: entry position 0-288
  indexes the quadrant grid row-major (UESP LAND VTXT) = exactly the sub-mesh vertex emission
  order, so sample -> vertex is a direct index. Out-of-range positions drop; opacities clamp
  to [0, 1].
- `packWeights` packs surviving layers into the per-vertex weight stream (two float4 lanes,
  `TerrainVertexLayout`), capped at `TerrainConstant.maxLayers` (8, format max).

`CellSceneBuilder` resolves LTEX `TNAM` -> TXST `TX00` diffuse via
`ESMWalk.record(withFormID:in:)` for the base and every layer. Paths are normalized through
`NIFShaderTextureSet.vfsKey` (same canonicalization the NIF material path takes) so terrain
and object textures share the [VFS](/formats/vfs.md) + `TextureLibrary` cache. Missing BTXT or
broken base chain -> `Material.fallback`; a broken layer chain drops that layer (and its
weight lane, keeping surviving lanes aligned) and counts into
`CellLoadSummary.terrainLayerSkipCount`. Drawn layers count into `terrainLayerCount`; the
summary line appends `(N splat layers[, K dropped])`. Normal maps (`TX01`) stay unsampled —
the splat path is diffuse-only like the M2 static pipeline (deferred).

Force-hidden quadrants: CELL `XCLC` quad-flags bits `0x1`-`0x8` hide the matching land quad
(UESP CELL). Hidden quadrants emit no mesh.

## Placement

`CellSceneBuilder.buildTerrain` puts the cell's south-west corner at world
`(gridX*4096, gridY*4096, 0)` via `MatrixMath.translation`, so vertex local `(c*128, r*128,
height)` lands at absolute world position — the same coordinate frame REFR placements use
(their DATA positions fall inside `[grid*4096, grid*4096+4096)`, verified in
[coordinates](/decisions/coordinates.md)). Terrain draws through `RenderScene.terrain` (its
own splat draw list — ref DrawItem instancing-ready grouping untouched) and feeds the cell
world AABB (per-patch `ModelBounds`, transformed) like every other instance.

`CellLoadSummary.terrainQuadrantCount` records the drawn patch count (0-4 quadrants, or 1
fallback plane, else 0). The summary line appends `, N terrain quads` only when non-zero, so a
terrain-free cell logs byte-identically to before.

## Fallback plane

An exterior cell with no LAND record draws a flat 33x33 plane at the worldspace default land
height from WRLD `DNAM` (first float; Tamriel reads -27000). When `DNAM` is absent OpenSky
draws no ground at all rather than guess a floor height — the correct engine behavior in that
case is UNCONFIRMED (todo: probe). `TerrainMeshBuilder.fallbackPatch(defaultLandHeight:)`
itself takes a plain height, so a caller that wanted a 0-height default could pass it; the
builder gates on `DNAM` presence today. The fallback patch has no base texture and no layers
-> fallback material, zero weights, same splat pipeline.

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
  quads, height passthrough), VNML normalization + zero/absent fallback, quadrant counts +
  shared edge vertices, hidden-quadrant omission, base-FormID routing, layer sort by layer
  number, VTXT dense bake (position mapping, out-of-range drop, clamp), weight packing
  (lane layout, over-cap ignore), fallback-plane height.
- `openskyTests/CellSceneTerrainTests.swift` — synthetic plugin with a compressed LAND +
  LTEX/TXST chains: terrain splat items, resolved base + layer diffuses from the VFS, layer
  blend order, broken-layer-chain drop + count, XCLC quad-hiding, DNAM fallback plane, and
  no-terrain when neither LAND nor DNAM present.
- `openskyTests/TerrainSplatRenderTests.swift` — GPU offscreen render of a synthetic
  two-texture terrain quad: west (weight 0) pixels read the base, east (weight 1) pixels
  read the layer — VTXT-driven blending proven at pixel level.
- `openskyTests/LandRealDataTests.swift` — env-gated edge-overlap probe (above).

Real-data visual check (2026-07-18, M1): `openskycli render` of WhiterunExterior06 (Tamriel
6,-2) — 4 terrain quads, 14 splat layers resolved, 0 missing textures; dirt/grass/rock/snow
transitions visible under the M2 walls, no flat single-texture quadrants.
