---
type: File Format
title: Terrain records (LAND, LTEX, TXST)
description: Byte layouts of Skyrim SE landscape, land-texture, and texture-set records and OpenSky's terrain types.
tags: [format, plugin, records, terrain, land]
timestamp: 2026-07-18T00:00:00Z
---

# Terrain record decoders, Skyrim SE

Terrain source data over the [ESM container](/formats/esm.md): per-cell height
field, vertex normals/colors, and the per-quadrant texture splat stack (LAND),
plus the landscape-texture (LTEX) and texture-set (TXST) records the splat
references. First half of milestone 3.1 — feeds the terrain mesh + splat build.

Reference: UESP "Skyrim Mod:Mod File Format" subpages `/LAND`, `/LTEX`, `/TXST`
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>). Cross-checked against
xEdit dev-4.1.6 `wbDefinitionsCommon.pas` (wbLAND / wbLTEX / wbTXST). Impl:
`opensky/Formats/ESM/Records/{Land,LandTexture,TextureSet}.swift`.

Decode policy (same as [other records](/formats/records.md)): loop over fields,
pick known types, skip the rest — unknown modder fields are never an error.
Decoders guard the record type and throw `ESMError.malformed` only on
structurally unusable input (wrong subrecord size). Malformed sizes throw; they
never crash (callers log + skip, mod-quirk rule).

## LAND -> Land

LAND lives in a cell's temporary-children group (group type 9) that
`CellSceneBuilder` already walks. Real LAND records are almost always
zlib-compressed (record flag bit 18); `ESMRecord.fields()` decompresses
transparently, so the decoder just reads subrecords.

A cell edge is a 33x33 vertex grid: 32 quads at 128 game units each span the
4096-unit cell. Rows run south->north, columns west->east; grid subrecords are
row-major in that order. The cell splits into 4 quadrants (0 bottom-left,
1 bottom-right, 2 top-left, 3 top-right), each a 17x17 sub-grid.

| field | size (B) | decoded                                            |
| ----- | -------- | -------------------------------------------------- |
| DATA  | 4        | `flags` (uint32, kept raw)                         |
| VHGT  | 1096     | `heightField` — anchor float + accumulated heights |
| VNML  | 3267     | `normals` — 33x33 int8 (x, y, z)                   |
| VCLR  | 3267     | `colors` — 33x33 uint8 (r, g, b), optional         |
| BTXT  | 8        | `baseTextures[]` — base texture per quadrant       |
| ATXT  | 8        | `layers[].` header — an additional splat layer     |
| VTXT  | 8*N      | `layers[].alphas` — the preceding ATXT's alpha map |

### VHGT height field

VHGT = float32 anchor + 33x33 int8 deltas + 3 unused bytes (4 + 1089 + 3 =
1096). Heights are gradient-coded, decoded in this order:

- Column 0 of each row is a delta from the previous row's column-0 value. Row 0
  column 0 is a delta from the float anchor. This running value seeds each row.
- Columns 1-32 accumulate west->east from their row's column-0 value.
- Final game-unit height = accumulated value * 8.

```text
columnZero = anchor
for row in 0..<33:
    columnZero += delta[row][0]          # vertical carry (row 0 from anchor)
    running = columnZero
    height[row][0] = running * 8
    for col in 1..<33:
        running += delta[row][col]       # horizontal accumulate
        height[row][col] = running * 8
```

`heightField.anchor` keeps the raw float (before *8); `heightField.heights` is
the 1089-entry `[Float]` result, row-major south->north. Ref UESP LAND VHGT +
xEdit wbLAND decode (same gradient scheme as Oblivion/Morrowind, scale 8).

### Texture layers

BTXT and ATXT share an 8-byte header: uint32 LTEX FormID, uint8 quadrant (0-3),
uint8 unused, int16 layer number. BTXT is the quadrant base (layer 0/-1); each
ATXT is one additional splat layer and is immediately followed by a VTXT alpha
map. VTXT is an array of 8-byte entries: uint16 position (0-288 on the 17x17
quadrant grid), uint16 unused, float32 opacity (0.0-1.0). The decoder pairs each
ATXT with its following VTXT and preserves on-disk order — the layer number
drives splat blend order. Sparse: only painted vertices appear in VTXT.

## LTEX -> LandTexture

| field | type    | decoded                               |
| ----- | ------- | ------------------------------------- |
| EDID  | zstring | `editorID`                            |
| TNAM  | formID  | `textureSet` — the TXST it draws from |

Skipped for now: MNAM (material type), HNAM (havok friction/restitution), SNAM
(specular exponent), GNAM (grass FormIDs) — none needed to splat terrain.

## TXST -> TextureSet

| field | type    | decoded                     |
| ----- | ------- | --------------------------- |
| EDID  | zstring | `editorID`                  |
| TX00  | zstring | `diffusePath` (diffuse map) |
| TX01  | zstring | `normalPath` (normal/gloss) |

Paths are relative to `Data/` (`textures\...`), resolved through the
[VFS](/formats/vfs.md). Skipped for now: TX02-TX07 (specular / environment /
height / etc. maps), DODT (decal data), DNAM (texture-set flags) — the terrain
splat needs only diffuse + normal today.

## Skipped for now

- LAND MPCD (multi-pass color data, rare) — not read.
- LTEX/TXST material, decal, and secondary-map fields listed above.
- Quadrant/position values are kept verbatim (not clamped); the mesh/splat build
  is responsible for grid placement.

## Verification

Unit tests: `openskyTests/TerrainRecordDecoderTests.swift` (synthetic in-code
fixtures) — VHGT delta accumulation with hand-computed heights incl. the
column-0 row carry and *8 scaling, VNML/VCLR decode, BTXT/ATXT/VTXT pairing +
quadrant/position bounds, compressed-LAND round-trip, LTEX->TNAM, TXST
TX00/TX01, wrong-record-type + malformed-size rejection.

Real-data sweep: `openskyTests/LandRealDataTests.swift` (env-gated on
`OPENSKY_DATA_ROOT`, self-skips when absent). Every LAND in the Tamriel
worldspace of vanilla Skyrim.esm, 2026-07-18:

- 11186 LAND records decoded, no throws.
- Height range -37032.0 .. 39392.0 game units.
- Additional-layer-count histogram (total ATXT across all 4 quadrants per cell,
  layers:cells): `0:3044 1:176 2:292 3:310 4:719 5:279 6:304 7:296 8:415 9:257
  10:337 11:350 12:408 13:376 14:379 15:400 16:450 17:439 18:547 19:634 20:665
  21:94 22:12 23:3` — max 23 additional layers cell-wide (roughly 6/quadrant).
- Max VTXT position 288 (exactly the documented 17x17 upper bound).
- Quadrant values seen: {0, 1, 2, 3}.

Neighbor-edge overlap (`LandRealDataTests.adjacentCellEdgesMatch`, groundwork for
cross-cell stitching in streaming 3.2): spec says a cell's 33x33 grid overlaps its
neighbors — row 32 of (x,y) equals row 0 of (x,y+1), col 32 equals col 0 of (x+1,y).
Probed over Whiterun-area adjacent pairs on vanilla Skyrim.esm, 2026-07-18: 4 pairs
checked, 0 mismatched edge vertices — shared edges match exactly. Overlap confirmed.
