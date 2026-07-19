---
type: Engine Design
title: Distant LOD streaming
description: Ring selection, async build, scene composition, placement, and verification.
tags: [engine, streaming, lod, terrain, rendering]
timestamp: 2026-07-18T00:00:00Z
---

# Distant LOD streaming

`DistantLODSelection` maps live streaming center + [LOD settings](/formats/lod.md) to
terrain/object blocks. Initial cell-distance bands:

| level | inner radius | outer radius | content |
| --- | ---: | ---: | --- |
| 4 | 2 | 8 | terrain + objects |
| 8 | 8 | 16 | terrain + objects |
| 16 | 16 | 32 | terrain + objects |
| 32 | 32 | 64 | terrain |

Grid anchoring uses lodsettings origin, not cell zero. Blocks outside settings stride drop.
Each world cell inside 64-cell radius owns exactly one source: resident full terrain, L4,
L8, L16, or L32. Selection keeps partially owned BTR blocks. `TerrainLODClipper` intersects
every source triangle against each owned cell rectangle, triangulates resulting polygons,
and interpolates position, normal, tangent, bitangent, UV, and color at cut edges. Adjacent
masks partition source area exactly -> no missing or double-drawn XY coverage at full/L4 or
L4/L8/L16/L32 boundaries. Clipped GPU models cache by BTR path + stable cell bitset. Fully
owned blocks retain normal shared-path cache. Partial BTO object atlases still drop because
their geometry lacks safe cell ownership metadata; this affects distant objects, not terrain
coverage. INI `fBlockLevel*Distance` fidelity remains deferred.

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
absent until [sky + water milestone](/todo.md). Tree `.btt`/`.lst` is non-NIF and deferred.

## Verification

Vanilla Tamriel target `(6,-2)`, production-size 5x5 full grid:

```sh
openskycli render --worldspace Tamriel --x 6 --y -2 --neighbors \
  --size 1280x720 --zoom 1.4 --out logs/distant-lod-3.4-5x5.png
```

Result after cell clipping: 101 LOD blocks, 0 unavailable, 975 visible draw calls, 3,313
instances, 100% non-background pixels. Prior sky-visible holes around loaded square are
filled by gray L4 terrain. Selection test proves every cell through L32 outer radius has
exactly one terrain owner; synthetic crossing-triangle tests prove adjacent masks preserve
source area with neither gap nor overlap. East/north real fly path settled three grids with
35 unique builds, 9 unloads, 25 final residents, 0 void; 5,192 frames averaged 3.32 ms,
p95 5.94 ms, max 17.75 ms under 33.33 ms budget.

![Original Tamriel distant LOD acceptance view](/img/distant-lod-whiterun.png)
