---
type: Engine Design
title: Distant LOD streaming
description: INI-driven rings, tree billboards, async composition, and verification.
tags: [engine, streaming, lod, terrain, tree, rendering]
timestamp: 2026-07-21T00:00:00Z
---

# Distant LOD streaming

`DistantLODSelection` maps live streaming center + [LOD settings](/formats/lod.md) + typed
[INI settings](/formats/ini.md) to terrain/object blocks. World-unit thresholds become
cell radii with `ceil(distance / 4096)`. Available levels map without holes:

| level | inner radius | outer radius | content |
| --- | ---: | ---: | --- |
| 4 | loaded radius (2) | `fBlockLevel0Distance` | terrain + objects |
| 8 | prior outer | `fBlockLevel1Distance` | terrain + objects |
| 16 | prior outer | `min(maximum, 2 * level1)` | terrain + objects |
| 32 | prior outer | `fBlockMaximumDistance` | terrain |

Grid anchoring uses lodsettings origin, not cell zero. Blocks outside settings stride drop.
Each world cell inside configured far radius owns exactly one source: resident full terrain, L4,
L8, L16, or L32. Selection keeps partially owned BTR blocks. `TerrainLODClipper` intersects
every source triangle against each owned cell rectangle, triangulates resulting polygons,
and interpolates position, normal, tangent, bitangent, UV, and color at cut edges. Adjacent
masks partition source area exactly -> no missing or double-drawn XY coverage at full/L4 or
L4/L8/L16/L32 boundaries. Clipped GPU models cache by BTR path + stable cell bitset. Fully
owned blocks retain normal shared-path cache. Partial BTO object atlases still drop because
their geometry lacks safe cell ownership metadata; this affects distant objects, not terrain
coverage. L16 split is OpenSky policy: Skyrim exposes two near thresholds + one maximum,
while asset set contains four power-of-two levels. Clamped `2 * level1` preserves
coarsening and leaves contiguous ownership.

LOD hides resident successful cells only, not desired grid slots. Void/failed cells have no
full terrain and therefore remain visible in clipped L4 coverage.

## Async flow

`CellStreamer` requests one LOD scene per grid center through same `SerialCellBuildRunner`
used by cell builds. Ordering keeps cache access confined to one utility queue:

1. complete desired 5x5 reaches resident/void/failed;
2. LOD build queues after near-grid work (first-load assets cannot starve cells);
3. after first settled ring, recenter retains old full grid + LOD as complete coverage;
4. replacement full cells integrate into an offscreen staging dictionary;
5. matching replacement LOD completion atomically swaps staged full grid + ring in one
   recompose; no transient hole or old-LOD/new-cell overlap;
6. stale completion drops + evicts its assets;
7. old LOD asset keys stay alive when still used by cells/new LOD, otherwise evict on queue.

`CellSceneComposition` merges resident full cells + optional LOD scene. Camera framing unions
full-cell bounds only; far LOD must not pull launch camera back to whole-world scale.

`DistantLODBuilder` reuses `MeshLibrary` + `TextureLibrary`: paths cache exactly like regular
NIF/DDS assets. BTR gets south-west translation; BTO stays world-space. `WATER` subtree is
absent until [sky + water milestone](/todo.md). [LST/BTT tree LOD](/formats/lod.md) generates
one cached crossed-plane model per tree type, then batches BTT transforms through normal
instancing. `fTreeLoadDistance` applies as an exact world-space XY radius, not a square cell
approximation. Tree LOD remains visible inside resident cells because full `TREE` records
have no renderer yet; suppressing those refs would create a near-grid hole. Remove this
fallback when full trees become a live consumer. Missing/malformed optional tree blocks
increment separate unavailable accounting and do not suppress terrain/object LOD. Distant
LOD does not cast or receive near cascaded shadows or local point lights; sun, ambient, and
fog still apply. Per-instance main-pass culling + one instanced draw per LST type remain.

Configuration loads once at app/CLI startup. Main app surface:
`World > Environment > Distant LOD`. Four fields expose only live consumers: L4, L8, far,
and trees. `Apply + rebuild` writes an OpenSky override, updates thread-safe config snapshot,
and invalidates current LOD ring. `Use Skyrim INI` clears override, reloads files, and
rebuilds. Source label shows active filename or OpenSky override.

## Verification

Vanilla Tamriel target `(6,-2)`, production-size 5x5 full grid:

```sh
openskycli render --worldspace Tamriel --x 6 --y -2 --neighbors \
  --size 1280x720 --zoom 1.4 --out logs/distant-lod-3.4-5x5.png
```

2026-07-21 configured INI 5x5 result: 121 terrain/object blocks, 0 unavailable, 9 available
tree blocks, 0 unavailable tree blocks, 2 placements inside the exact camera radius, 100%
non-background pixels. Focused `(7,-3)` render: 131 terrain/object blocks, 9 tree blocks,
35 placements, 100% non-background; tree atlas billboards are visible across distant hills
and inside the loaded cell as the temporary full-tree fallback.
Selection tests prove exact configured band boundaries and every cell through L32 outer
radius has one terrain owner; synthetic crossing-triangle tests prove adjacent masks
preserve source area with neither gap nor overlap. East/north real fly path settled three grids with
35 unique builds, 9 unloads, 25 final residents, 0 void; 5,192 frames averaged 3.32 ms,
p95 5.94 ms, max 17.75 ms under 33.33 ms budget.

Generated render captures stay local; numeric ownership + frame metrics above are the
repository acceptance evidence.
