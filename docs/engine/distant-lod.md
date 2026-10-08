---
type: Subsystem
title: Distant LOD streaming
description: How the distant LOD rings are chosen from the INI settings, how block edges are
  clipped so each cell has one terrain owner, and how LOD swaps in without holes.
tags: [engine, streaming, lod, terrain, tree, rendering]
---

# Distant LOD streaming

Distant LOD (level of detail) draws the land and objects beyond the loaded cells. The files are
on the [LOD](/formats/lod.md) page. The distance settings come from the [INI](/formats/ini.md)
files.

## Rings

Distances in game units become cell radii with `ceil(distance / 4096)`. The levels fit together
with no gaps:

| Level | Inner radius | Outer radius | Content |
| --- | --- | --- | --- |
| 4 | Loaded radius (2) | `fBlockLevel0Distance` | Terrain and objects |
| 8 | Previous outer | `fBlockLevel1Distance` | Terrain and objects |
| 16 | Previous outer | `min(maximum, 2 * level1)` | Terrain and objects |
| 32 | Previous outer | `fBlockMaximumDistance` | Terrain |

Skyrim has two near distances and one maximum, but the files have four levels. The level 16
limit (`2 * level1`, capped at the maximum) is OpenSky's own choice. It keeps each level coarser
than the last, with no gaps between them.

The block grid starts at the origin in the LOD settings file, not at cell 0. A block that is not
on the settings stride is dropped.

## One owner per cell

Every cell inside the far radius has exactly one terrain source: loaded full terrain, or level 4,
8, 16, or 32. A LOD block can cover cells that belong to another source. So OpenSky clips the
block: it cuts every triangle against each owned cell's rectangle, splits the pieces into
triangles, and interpolates position, normal, tangent, bitangent, UV, and color at the cuts.
Neighbor masks split the area exactly, so no ground is missing or drawn twice at any border.
Clipped models are cached by file path and cell set.

Object LOD blocks (`.bto`) that are only partly owned are dropped, because their geometry does
not say which cell each part belongs to. This affects distant objects, not terrain.

LOD hides only cells that loaded. A cell that failed or has no land has no full terrain, so the
level 4 LOD stays visible there.

## Building without holes

LOD scenes are built on the same serial queue as cells, except the first ring:

1. At the session start, the first ring is built beside the near grid, in a `@concurrent`
   function with its own mesh and texture libraries, so it never touches the build queue's
   caches. It hides the whole desired 5 x 5 grid. The loading screen stays up until the near
   grid has finished and this ring is in ([loading screens](/engine/loading-screens.md)).
2. Every later ring waits for the near grid to finish (every cell loaded, empty, or failed),
   so a LOD build cannot hold up near cells.
3. After the first ring, a move keeps the old grid and old LOD visible.
4. New full cells are collected off-screen.
5. When the matching new LOD is ready, the new cells and new LOD swap in together. There is no
   moment with a hole, and no moment with old LOD over new cells.
6. A LOD build that is out of date when it finishes is dropped, and its assets are freed.
7. Old LOD assets stay loaded while cells or the new LOD still use them.

Camera framing uses only full cell bounds. Otherwise distant LOD would pull the start camera out
to see the whole world.

LOD models and textures use the same caches as normal NIF and DDS files. The first ring keeps
its own copies until a later ring replaces it. Terrain blocks (`.btr`)
are moved to their south-west corner. Object blocks (`.bto`) are already in world space.

### Start time

Measured with `openskycli bench --fly-path --evict` on a Release build, game data and cache on
the same external USB SSD (2026-10-08, `.logs/lod-prebuild/20261008T060617Z`). The first ring
takes about 0.9 s cold and now finishes within about 1.1 s of the start, long before the near
grid. But both builds read from the same disk, so the near grid gets slower by almost the same
time. "Start area ready" went from 6.2 s to 6.1 s with the asset cache, and stayed at about
6.7 s from the archives. Background priority made it worse: its throttled reads finished the
ring last.

## Tree LOD

Each tree type gets one cached model of two crossed planes. The tree positions (`.btt`) are
drawn with normal instancing, one draw per type. `fTreeLoadDistance` is an exact circle, not a
square of cells.

Tree LOD is hidden inside loaded cells, as terrain and object LOD are, because a loaded cell
draws its full `TREE` references. A missing tree block is counted on its own and does not hide
terrain or object LOD.

Distant LOD does not cast or receive near shadows and ignores point lights. Sun, ambient, and fog
still apply.

## Controls

World > Environment > Distant LOD has four fields: level 4, level 8, far distance, and trees.
Apply saves an OpenSky override and rebuilds the current ring at once. "Use Skyrim INI" clears
the override, reloads the files, and rebuilds. A label shows which source is active.

`openskycli render --worldspace Tamriel --x 6 --y -2 --neighbors` draws a 5 x 5 grid with its
LOD ([CLI](/tools/cli.md)).
