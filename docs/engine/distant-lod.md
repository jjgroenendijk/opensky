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
| 4 | Loaded radius (2) | `split * fBlockLevel0Distance`, at least one ring | Terrain and objects |
| 8 | Previous outer | `split * fBlockLevel1Distance` | Terrain and objects |
| 16 | Previous outer | `split * 2 * level1` | Terrain and objects |
| 32 | Previous outer | `fBlockMaximumDistance` | Terrain |

Skyrim has two near distances and one maximum, but the files have four levels. The level 16
limit (`2 * level1`, capped at the maximum) is OpenSky's own choice. It keeps each level coarser
than the last, with no gaps between them.

`split` is `fSplitDistanceMult`, and each scaled distance stops at the maximum. A small split,
such as 0.5 in the Low preset, could leave no level 4 ring. A level 8 block would then touch the
full-detail cells, and the cracks between them would show. So level 4 always keeps one ring.

The block grid starts at the origin in the LOD settings file, not at cell 0. A block that is not
on the settings stride is dropped.

## One owner per cell

Every cell inside the far radius has exactly one terrain source: loaded full terrain, or level 4,
8, 16, or 32. A LOD block can cover cells that belong to another source. So OpenSky clips the
block: it cuts every triangle against each owned cell's rectangle, splits the pieces into
triangles, and interpolates position, normal, tangent, bitangent, UV, and color at the cuts.
Neighbor masks split the area exactly, so no ground is missing or drawn twice at any border.
Clipped models are cached by file path and cell set.

### Skirts

The vanilla terrain blocks have vertices exactly 1000, 2000, 3000, and 4000 units below the land
at levels 4, 8, 16, and 32 (measured in #1530). They read as skirts: vertical strips that hang
from a block's outer edge and hide the step to a neighbour of another level, whose edge heights
differ. The clip keeps a vertical triangle that lies on an owned cell's side. A cut side, where
the cell beyond is inside the block but owned by another source, gets a new skirt of the same
depth for that level, facing both ways. The skirt reading is not confirmed against the game,
and the cut depth is OpenSky's choice.

Object LOD blocks (`.bto`) that are only partly owned are dropped, because their geometry does
not say which cell each part belongs to. This affects distant objects, not terrain.

LOD hides only cells that loaded. A cell that failed or has no land has no full terrain, so the
level 4 LOD stays visible there.

## Building without holes

LOD scenes are built on the same serial queue as cells, except the first ring:

1. At the session start, the first ring is built beside the near grid, in a `@concurrent`
   function with its own mesh and texture libraries, so it never touches the build queue's
   caches. It hides the whole desired near grid. The loading screen stays up until the near
   grid has finished and this ring is in ([loading screens](/engine/loading-screens.md)).
2. The second ring waits for the near grid to finish (every cell loaded, empty, or failed),
   so a LOD build cannot hold up near cells.
3. Each ring leaves out exactly the full cells that draw with it. A new cell that the ring on
   screen covers waits off screen.
4. When the next ring is ready, it swaps in with the cells it leaves out. There is no moment
   with a hole, and no moment with old LOD over new cells. The rules for when a ring is
   requested are on the [cell streaming](/engine/cell-streaming.md#distant-lod-and-coverage)
   page.
5. Old LOD assets stay loaded while cells or the new LOD still use them.

Camera framing uses only full cell bounds. Otherwise distant LOD would pull the start camera out
to see the whole world.

LOD models and textures use the same caches as normal NIF and DDS files. The first ring keeps
its own copies until a later ring replaces it. Terrain blocks (`.btr`)
are moved to their south-west corner. Object blocks (`.bto`) are already in world space.

### Start time

Measured with the fly-path gate after a page cache eviction, on a Release build, game data and cache
on the same external USB SSD (2026-10-08, `.logs/lod-prebuild/20261008T060617Z`). The first ring
takes about 0.9 s cold and now finishes within about 1.1 s of the start, long before the near grid.
But both builds read from the same disk, so the near grid gets slower by almost the same time.
"Start area ready" went from 6.2 s to 6.1 s with the asset cache, and stayed at about 6.7 s from the
archives. Background priority made it worse: its throttled reads finished the ring last.

## Large references

A large reference is a placed object that is big, such as a mountain or a bridge. The `WRLD` `RNAM`
field lists them by cell. Each plugin's copy of the `WRLD` lists only its own: on the install,
`Skyrim.esm`'s `Tamriel` holds about 160,000 and the winning override 18. So OpenSky joins the lists
of every plugin. In the game they keep their full model out to `uLargeRefLODGridSize` cells, 11 by
default, instead of the 5 of `uGridsToLoad` (UESP "Skyrim Mod:Mod File Format/WRLD", `RNAM`).
OpenSky reads the setting from the INI files and the Graphics page as "Large object grid", and turns
the grid side into rings like `uGridsToLoad`: 11 gives 5. A value at or below the loaded grid turns
the ring off.

Each ring build, on the build queue:

1. Object LOD blocks merge their large references into separate shapes. On the real install,
   `tamriel.4.4.-8.bto` holds `obj-LargeRef`, `objsnow-LargeRef`, `objHD-LargeRef`, and
   `objsnowHD-LargeRef`, each with a `BSDistantObjectLargeRefExtraData` block. Each shape
   holds one segment per cell ([LOD format](/formats/lod.md#large-references)). A block that
   reaches into the ring drops the segments of the cells inside the large radius, and keeps
   the rest.
2. The ring's cells are every cell inside the large radius, minus the cells the ring leaves
   out. A near cell that is still building keeps the ring's large references, because its
   object LOD segment is gone. A
   `-LargeRef` shape without segments, as a tool other than the game's might write, drops
   whole, and then every cell of its block joins the ring, so no large reference goes
   missing.
3. In those cells, the references that `RNAM` lists are read from their cell and drawn with
   their full model, as the cell build places them. A listed static stays only while it is
   still large: half the diagonal of its base's `OBND` bounds, times the reference's scale,
   must be above `fLargeRefMinSize` (1,024 by default), as observed in the game. So a plugin
   that raises the setting drops the smaller ones. A listed reference whose base is not a
   static, or has no bounds, stays as `RNAM` lists it. Each takes the enable state its own cell
   would give it: the world state, then its enable parent.

The quick first ring of a session keeps the `-LargeRef` shapes, because its builder cannot
read the plugins. Once the near grid is in, the same center is built once more with the large
references. The start area stays behind the loading screen until that second build is in or
has failed, so the first view already shows the full models and no swap is seen.
`openskycli game state frame` reports `largeReferences` and `hiddenLargeReferenceLOD`, the
count of cell segments the ring hid. `openskycli render` prints the large-reference count with
the LOD line.

The ring remembers the object IDs of the references it draws and of their enable parents. When
a script or a quest enables or disables one of them, the ring of the current center is built
again, so the reference appears or goes. The match is by object ID, so a ring may rebuild once
too often, never too seldom.

## Is Full LOD references

A reference with the record flag `0x10000` (xEdit "Is Full LOD", "Never Fades" on a light)
draws its full model at every distance in the worldspace. On the install 1,022 references carry
it, 951 of them persistent. Each ring build adds the worldspace's persistent ones whose cell is
not loaded, in their enable state, and watches them as it watches the large references. The
temporary ones are added the same way.
`state frame` reports them as `fullLODReferences`.

The 71 temporary Is Full LOD references are found by one walk of the worldspace's exterior
cells, the first time a ring is built. The walk reads only the record headers of each cell's
temporary children, and keeps the cells that hold a live `REFR` with the flag. Each ring build
then reads those cells, except the loaded ones, and draws their flagged temporary references in
their enable state.

[WARNING] The walk reads the temporary children of the first plugin that has each cell. A
temporary Is Full LOD reference that only a later plugin adds is drawn only when its cell is
loaded. The objects merged into the object LOD blocks do not follow enable changes: the
vanilla blocks were built with them, and only generated LOD could leave them out.

## Generated terrain

The vanilla terrain LOD files were built from `Skyrim.esm` alone, so land that `Update.esm`,
the DLCs, or a mod changes is wrong far away. With "Distant land from the load order" on the
Graphics page (on by default), each terrain block is built from the winning `LAND` record of
every cell in it instead. The vanilla file draws when no cell of the block has land, and when
the switch is off.

- The mesh is a 33 x 33 grid over the block at every level, as the vanilla level 4 blocks have
  about. Its heights are the `VHGT` heights, read bilinearly between the land's own vertices. A
  cell without land takes the worldspace's default land height (`WRLD` `DNAM`).
- Each side hangs a skirt down by the vanilla depth: 1000 units at level 4, 2000 at 8, 3000 at
  16, and 4000 at 32 ([skirts](#skirts)). The skirt draws from both sides.
- The diffuse map is 256 x 256, as vanilla's. Each texel takes 4 samples. A sample blends the
  quadrant's base texture and its layers by their `VTXT` opacity in linear light, with the
  near terrain's tiling (one repeat per 2 quads), then multiplies `VCLR` as the near terrain
  shader does. A land texture is read at a small mip whose texels match the LOD texel: an edge
  of 8, 4, 2, and 1 at levels 4, 8, 16, and 32.
- The normal map is 256 x 256 and holds the `VNML` normals in model space, x in red, z in
  green, and y in blue, as vanilla's `_n` maps do.
- The generated block keeps the land textures' own brightness, so a ring with generated
  blocks draws with no [brightness curve](/rendering/surface-shading.md).

The blocks are built on the cell build queue when a ring first needs them, and the mesh cache
keeps them like a file's model. The quick first ring of a session still draws the vanilla files,
because its builder cannot read the plugins; the second build of the same center swaps the
generated blocks in behind the loading screen. `openskycli game state frame` reports
`generatedTerrainBlocks`, and `openskycli render` prints the count with the LOD line.

Objects and trees still come from the vanilla files. The game draws its own LOD files only;
building them from the load order is OpenSky's own step.

## Tree LOD

Each tree type gets one cached model of two crossed planes. The tree positions (`.btt`) are
drawn with normal instancing, one draw per type. `fTreeLoadDistance` is an exact circle, not a
square of cells.

Tree LOD is hidden inside loaded cells, as terrain and object LOD are, because a loaded cell
draws its full `TREE` references. A missing tree block is counted on its own and does not hide
terrain or object LOD.

Distant LOD does not cast or receive near shadows and ignores point lights. Sun, ambient, and fog
still apply.
