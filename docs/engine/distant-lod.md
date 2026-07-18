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
Any block rectangle intersecting desired loaded 5x5 drops -> no full-cell/LOD double draw.
Vanilla L4 geometry is one complete 4x4 block, so conservative exclusion can leave up to
three alignment cells between full grid + first LOD block. Follow-up: clip terrain triangles
or use segment masks, then close band without overlap. INI `fBlockLevel*Distance` fidelity
also deferred; constants above are measurable first pass.

## Async flow

`CellStreamer` requests one LOD scene per grid center through same `SerialCellBuildRunner`
used by cell builds. Ordering keeps cache access confined to one utility queue:

1. complete desired 5x5 reaches resident/void/failed;
2. LOD build queues after near-grid work (first-load assets cannot starve cells);
3. recenter removes old ring before new full cells integrate -> no stale-ring overlap;
4. completion matching current center replaces composed LOD scene;
5. stale completion drops + evicts its assets;
6. old LOD asset keys stay alive when still used by cells/new LOD, otherwise evict on queue.

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

Result: 122 LOD blocks, 0 unavailable, 981 visible draw calls, 3,360 instances, 70.8%
non-background pixels. Distant terrain + object atlas silhouettes fill horizon; selection
unit test proves no selected block intersects loaded grid.

![Tamriel distant LOD beyond 5x5 Whiterun grid](/img/distant-lod-whiterun.png)
