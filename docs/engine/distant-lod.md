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

LOD scenes are built on the same serial queue as cells:

1. The 5 x 5 near grid finishes first: every cell loaded, empty, or failed.
2. Then the LOD build is queued, so first-load LOD cannot hold up near cells.
3. After the first ring, a move keeps the old grid and old LOD visible.
4. New full cells are collected off-screen.
5. When the matching new LOD is ready, the new cells and new LOD swap in together. There is no
   moment with a hole, and no moment with old LOD over new cells.
6. A LOD build that is out of date when it finishes is dropped, and its assets are freed.
7. Old LOD assets stay loaded while cells or the new LOD still use them.

Camera framing uses only full cell bounds. Otherwise distant LOD would pull the start camera out
to see the whole world.

LOD models and textures use the same caches as normal NIF and DDS files. Terrain blocks (`.btr`)
are moved to their south-west corner. Object blocks (`.bto`) are already in world space.

## Tree LOD

Each tree type gets one cached model of two crossed planes. The tree positions (`.btt`) are
drawn with normal instancing, one draw per type. `fTreeLoadDistance` is an exact circle, not a
square of cells.

Tree LOD also stays visible inside loaded cells, because full `TREE` records have no renderer
yet. Hiding them would leave a hole in the near grid. Remove this when full trees are drawn. A
missing tree block is counted on its own and does not hide terrain or object LOD.

Distant LOD does not cast or receive near shadows and ignores point lights. Sun, ambient, and fog
still apply.

## Controls

World > Environment > Distant LOD has four fields: level 4, level 8, far distance, and trees.
Apply saves an OpenSky override and rebuilds the current ring at once. "Use Skyrim INI" clears
the override, reloads the files, and rebuilds. A label shows which source is active.

`openskycli render --worldspace Tamriel --x 6 --y -2 --neighbors` draws a 5 x 5 grid with its
LOD ([CLI](/tools/cli.md)).
