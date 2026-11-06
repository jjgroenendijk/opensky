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
way as NIF texture paths, so terrain and objects share one texture cache. A quadrant with no
`BTXT` draws the default ground texture, the same as a null `LTEX`
([LAND](/formats/land.md#texture-layers)); Helgen has such quadrants. A base texture whose
link is broken gives the fallback material. A broken layer is dropped with its weight, and the
other weights stay in line. The cell summary counts drawn and dropped layers.

A cell's `XCLC` quad flags `0x1` to `0x8` hide the matching quarter. A hidden quarter has no
mesh.

## Normal maps

Each land texture's `TXST` `TX01` is its normal map. The base and every layer bind one, and the
splat shader blends the normal XY with the same layer weights as the color. Z is rebuilt from
XY. A missing normal map is a flat one, so that layer lights like the vertex normal.

The tangent frame follows the UVs: +u is east (+X) and +v is north (+Y). Green points along
+v. This was measured on the vanilla data: for 80 of the 82 terrain `_n.dds` maps, the curl
test (the change of red along v against the change of green along u) only holds with green
along +v. The other two are almost flat and give no answer.

Ray-traced shadows still test the vertex normal.

## Snow ground

A land texture with the Skyrim SE snow flag (`LTEX` `INAM`) is snow ground. With the game's
`[Display] bEnableImprovedSnow` on, the snow share of a pixel blends from the base and the
layers by the same weights as the colour, and so does the texture's alpha, the snow mask.

The game adds a white rim sheen to snow, times the mask and the snow share, whatever the light
(clean-room read of the game's shaders and of `SkyrimSE.exe` 1.7.104.0, 2026-11-06):

```text
rim = (1 - saturate(Ng . V))^fSnowGeometrySpecPower * (1 - saturate(N . V))^fSnowNormalSpecPower
      * fSnowRimLightIntensity                         (3, 2, and 0.3 by default)
```

`Ng` is the vertex normal, `N` the normal-mapped one, and `V` the direction to the eye. So snow
brightens toward the horizon and on slopes seen edge-on. The game drops the sun's specular on
snow and adds the point lights' specular to the rim; land has no specular in OpenSky, so neither
applies.

The game then adds sparkles, also times the snow mask. They depend only on the world
position, not on the view or the light:

1. `v = (noise(world * fSparklesSize * 0.07) + 1) / 2`, where the noise is 3D simplex noise in
   -1 to 1 and the size is 6, so about 0.42 noise cells per unit.
2. `s = v^fSparklesSpecularPower` (2). Below `fSparklesDensity` (0.85), `s` is 0, so "density"
   is a cut-off: with the defaults only `v` above 0.922 sparkles.
3. `s` is scaled by `fSparklesIntensity` (1), by `sh + (1 - sh) * fShadowSparkleIntensity`
   (0.25) with `sh` the sun shadow, and by `1 - smoothstep(0, fSparklesMaxDistance, d)` with a
   distance of 1000 units.
4. The sparkle adds `s` times the sparkle colour.

The game picks the sparkle colour from its lighting state by a setting whose meaning the read
did not settle; OpenSky uses the sun colour. OpenSky's noise is its own simplex noise, so the
sparkles fall in other places than the game's, at the same density. The same rim and
sparkles light a mesh under a snow directional material
([surface shading](/rendering/surface-shading.md#directional-materials)).

The game also turns ambient occlusion off where the snow mask is above zero. OpenSky does the
same: an opaque pixel with snow stores 0 in the scene colour's alpha, and the
[occlusion pass](/rendering/post-effects.md#ambient-occlusion) leaves such a pixel as it is.

## Placement

The cell's south-west corner goes to `(gridX * 4096, gridY * 4096, 0)`. So a vertex lands at its
real world position, in the same frame as reference positions. Terrain feeds the cell's bounds
like any other object.

[Grass](/engine/grass.md) uses the same height triangles, colors, hidden quarters, and layer
blending. One source of truth keeps grass on the ground, and off textures that were painted
over.

## Fallback plane

An exterior cell with no `LAND` in a child worldspace whose `PNAM` sets `0x01` (use land data)
takes the parent worldspace's `LAND` at the same grid cell first. The city worlds, such as
Whiterun and Riften, have no `LAND` of their own, so their ground is Tamriel's
([world records](/formats/world-records.md)).

An exterior cell with no `LAND` and no such parent `LAND` gets a flat 33 x 33 plane at the
worldspace's default land height, the first float of `WRLD` `DNAM`. Tamriel's is -27000. If `DNAM`
is missing, OpenSky draws no ground. It does not guess a height. What the game does in that case is
not confirmed.

## Cell edges weld exactly

UESP says a cell's grid overlaps its neighbors: row 32 of (x, y) equals row 0 of (x, y + 1), and
column 32 equals column 0 of (x + 1, y). The vanilla data agrees: in the Whiterun area, shared
edges match exactly. So neighbor cells join with no gaps, and streaming can drop one cell's
shared row instead of averaging.

`openskycli render --neighbors` draws a cell with its 8 neighbors, to check the joins
([CLI](/tools/cli.md)).
