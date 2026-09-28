---
type: Subsystem
title: Procedural grass
description: How OpenSky places grass from land textures, keeps it the same on every rebuild,
  batches it on the GPU, and where it differs from the original game.
tags: [engine, world, grass, terrain, streaming]
---

# Procedural grass

Grass is not placed by hand in Skyrim. It grows from the land textures:

```text
LAND BTXT/ATXT coverage -> LTEX GNAM (repeats) -> GRAS MODL + DATA
```

The records are on the [grass](/formats/grass.md) page. The original game's placement grid and
random number method are not in any open source. OpenSky uses its own method, described below.
None of its constants are claimed to match the game.

## Placement

For one `LAND` record:

1. Collect the land textures in use, follow their `GNAM` links, and group each grass type with
   the textures that pick it. Sort all FormIDs first.
2. Build a square grid of candidate points. Spacing is the grass's position range, at least 32
   units. Points per side is `ceil(4096 / spacing)`, at most 128. Move each point by a random
   amount up to half the smaller of the position range and the spacing, inside the cell.
3. Seed each point from the cell X and Y, the `LAND` FormID, the `GRAS` FormID, the row, and the
   column. Random numbers come from SplitMix64, which gives the same values on every machine.
   Swift's `Hasher` is never used, because it changes per run.
4. Sample the [terrain](/engine/terrain.md) triangle under the point for height and normal. A
   hidden cell quarter rejects the point.
5. Rebuild each texture's final coverage the way the terrain shader does. Keep the point with
   chance `clamp(density / 100) * coverage`.
6. Reject points outside the slope range. If the cell has a known water height, apply the
   grass's water rule. With no water information, nothing is rejected.
7. Add a random turn, a height change around scale 1, optional even scaling, the land's vertex
   color, and random darkening. Keep the normal and the "fit to slope" flag for drawing.

Bad values, zero density, a reversed slope range, or a missing `DATA` or model give no grass. The
32-unit floor and the 128 cap limit bad input to 16,384 points per grass type per cell.

## Same result every time

Each point's seed depends only on the point. So a cell rebuilt later gives exactly the same grass
in the same order, whatever order cells load in. Neighbor cells get different seeds, so the
pattern does not repeat. A worldspace with "no grass" gets none. Interiors and cells with no land
get none.

## Drawing

Grass is grouped by type. Each model loads once. Groups with the same mesh and texture are merged
across all loaded cells, so one grass type is one instanced draw. Grass belongs to its cell and
leaves with it.

With "fit to slope", the model's up axis follows the land normal, then the random turn is applied
around it. The vertex shader bends the top of each blade along the weather's wind. The wind scale
is 0 to 2. Grass fades from 70% of the draw distance, through alpha test, so it does not pop.

Each frame, grass is filtered in this order:

1. The density key against the user's density (0 to 100%).
2. Camera distance, 512 to 16,384 units.
3. The view frustum, with bounds grown for sway.
4. A hard cap of 16,384 instances.

The cap drops only for that frame, and each reason is counted. Grass receives sun shadows and
fog. It does not cast shadows and ignores point lights, because small alpha-tested blades would
cost too much there.

World > Environment > Grass has on and off, density, distance, and wind, and shows draws and
each drop count.

## Differences from the game

- The candidate grid, SplitMix64 seeds, the 32-unit floor, and the 128 cap are OpenSky's.
- Position range is used as spacing and random offset. The Creation Kit describes what it looks
  like, not the math.
- Density is a chance per point times the texture coverage. How the game samples coverage is not
  known.
- Height and color changes are symmetric around scale 1 and darken only. The game's exact spread
  is not known.
- The water rule names come from xEdit. How edges compare is OpenSky's reading. Unknown values
  pass.
- Normals are not updated after the wind bends a blade.
- The instance cap drops in scene order, not nearest first.
