---
type: File Format
title: Skyrim SE distant LOD
description: lodsettings, terrain BTR, object BTO, tree LST/BTT layouts, and probe evidence.
tags: [format, lod, terrain, tree, nif, rendering]
timestamp: 2026-07-21T00:00:00Z
---

# Skyrim SE distant LOD

Milestone 3.4 loads terrain + object geometry beyond streamed 5x5 cells. Source data stays
in user's read-only install. OpenSky never copies LOD containers into repo.

References:

* xEdit `dev-4.1.6` [`wbLOD.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbLOD.pas)
  (`TwbLodSettings.LoadFromData`, block anchoring, tree paths).
* xEdit generator [`LODGen.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Build/Edit%20Scripts/LODGen.pas)
  for generated terrain/object asset conventions.
* NifTools [`nif.xml`](https://github.com/niftools/nifxml/blob/develop/nif.xml):
  `BSMultiBoundNode`, `BSMultiBound`, `BSMultiBoundAABB`, `BSSubIndexTriShape`,
  `BSGeometrySegmentData`.
* UESP [LOD Settings File Format](https://en.uesp.net/wiki/Tes5Mod:LOD_Settings_File_Format).

`.btr`/`.bto` are generator-defined NIF profiles, not a published Bethesda spec. Parsers
therefore validate all counts/ranges and real-data verification sweeps every vanilla file.

## lodsettings

Path: `lodsettings/<worldspace-editor-id>.lod`. Skyrim layout is exactly 16 bytes,
little-endian:

| offset | type | field |
| --- | --- | --- |
| 0 | int16 | south-west origin cell X |
| 2 | int16 | south-west origin cell Y |
| 4 | int32 | worldspace stride in cells |
| 8 | int32 | minimum LOD level |
| 12 | int32 | maximum LOD level |

`LODSettings` rejects wrong size, non-positive stride, inverted/non-positive level range.
Levels double from min through max. Block containing cell `C` at level `N`:

`origin + floor((C - origin) / N) * N`

Floor division matters west/south of origin; Swift truncation would anchor negative cells to
wrong block. Vanilla `tamriel.lod` probe: origin `(-96,-96)`, stride `256`, levels
`4/8/16/32`.

## Terrain BTR

Path + textures:

```text
meshes/terrain/<ws>/<ws>.<level>.<x>.<y>.btr
textures/terrain/<ws>/<ws>.<level>.<x>.<y>.dds
textures/terrain/<ws>/<ws>.<level>.<x>.<y>_n.dds
```

`(x,y)` is block south-west cell. Level N spans N x N cells. Terrain vertices are block-local
and receive translation `(x*4096, y*4096, 0)`. Sample `tamriel.4.4.-4.btr`: `land` shape,
1,042 vertices / 2,040 triangles, local bounds `(0,0)..(16384,16384)`.

Terrain files commonly contain two sibling `BSMultiBoundNode`s: `chunk` -> land; `WATER` ->
water shape. Flattener prunes `WATER` subtree until 3.5 supplies water rendering.

Vanilla L4/L8/L16/L32 diffuse atlases are legacy 32-bit xRGB8888 DDS: B,G,R,X payload,
opaque alpha, full mip chains. [DDS parser](/formats/dds.md) validates masks + pitch;
`TextureLoader` uploads them as sRGB BGRA8. Normal atlases remain linear DXT5. Invalid
assets keep placeholder fallback; valid LOD no longer becomes flat gray.

Multi-bound additions after shared [NIF](/formats/nif.md) layouts:

| block | payload after inherited prefix |
| --- | --- |
| `BSMultiBoundNode` | NiNode children/effects, int32 multi-bound ref, uint32 culling mode |
| `BSMultiBound` | int32 data ref |
| `BSMultiBoundAABB` | float3 center, float3 non-negative extent |

## Object BTO

Path:

```text
meshes/terrain/<ws>/objects/<ws>.<level>.<x>.<y>.bto
```

Vanilla object levels: 4/8/16. Lighting properties reference shared atlas:

```text
textures/terrain/<ws>/objects/<ws>.objects.dds
textures/terrain/<ws>/objects/<ws>.objects_n.dds
```

Unlike BTR, vanilla BTO vertices are already world-space. Probe
`tamriel.4.4.-4.bto`: bounds near cell `(4,-4)` world origin, 24,843 vertices / 14,024
triangles across `Obj` + `obj-LargeRef`. Applying filename translation again would move
objects twice; OpenSky uses identity placement.

Shared object diffuse atlas is RGBA8888 (`DDPF_ALPHAPIXELS`; stored alpha preserved);
object normal atlas remains DXT5.

SSE `BSSubIndexTriShape` = complete `BSTriShape` payload, then:

| type | field | validation |
| --- | --- | --- |
| uint32 | segment count | each SSE segment needs 9 remaining bytes |
| repeated uint8 | flags | opaque metadata retained |
| repeated uint32 | start index | into flat triangle-index array |
| repeated uint32 | primitive count | `start + count*3 <= index count` |

Segment metadata is decoded + validated; current renderer draws complete shape. Particle-copy
bytes in inherited `BSTriShape` are skipped by declared size before segment decode.

## Tree LST + BTT

Traditional tree LOD uses one type list, one atlas, and L4 placement blocks:

```text
meshes/terrain/<ws>/trees/<ws>.lst
meshes/terrain/<ws>/trees/<ws>.4.<x>.<y>.btt
textures/terrain/<ws>/trees/<ws>treelod.dds
```

xEdit `TwbLodTES5TreeType.LoadFromData` defines LST as int32 count followed by 32-byte
records:

| bytes | type | field |
| ---: | --- | --- |
| 4 | int32 | stable type index referenced by BTT |
| 4 + 4 | float32 | billboard width, height |
| 4 x 4 | float32 | atlas UV min X/Y, max X/Y |
| 4 | uint32 | retained opaque metadata |

`TwbLodTES5TreeBlock.LoadFromData` defines BTT as int32 group count. Each group starts with
int32 type index + int32 reference count, then 32-byte references:

| bytes | type | field |
| ---: | --- | --- |
| 12 | float32 x3 | world position |
| 4 | float32 | rotation about +Z, radians |
| 4 | float32 | uniform scale |
| 4 | uint32 | source FormID |
| 8 | uint32 x2 | retained opaque metadata |

Parser rejects impossible counts, non-finite/invalid dimensions and transforms, duplicate
LST indices, unknown BTT type indices, and trailing bytes. Atlas UVs may bleed slightly
outside 0...1; vanilla padding does, so validation requires finite ordered bounds only.

DynDOLOD's [Tree LOD](https://dyndolod.info/Help/Tree-LOD) description confirms traditional
billboards are two double-sided planes intersecting at 90 degrees. OpenSky generates those
planes at runtime from LST dimensions/UVs, alpha-tests atlas pixels, then places them using
BTT transform data. Generated models remain normal mesh/texture cache entries.

## Probe evidence

Repeatable command:

```sh
make run-cli ARGS="lod --worldspace Tamriel"
```

2026-07-21 vanilla AE install: 3,060 `.btr` + 717 `.bto`, plus 34 LST types + 329 `.btt`
blocks + 40,839 tree refs. Every container parsed, every BTT type resolved, every
LOD-specific NIF block decoded, every scene flattened; 0 failures. No files were extracted.
