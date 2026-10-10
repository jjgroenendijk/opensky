---
type: Subsystem
title: Texture streaming
description: How large textures keep only the mip levels the camera needs, in Metal 4
  placement-sparse textures mapped to a pool of heap tiles, under a memory budget.
tags: [rendering, metal4, performance, textures, memory]
---

# Texture streaming

A texture with mip levels needs its large levels only when a surface is close. A far
surface samples a small level, so the large ones waste memory. Texture streaming keeps a
large texture's small levels always, and maps its large levels only while a close surface
needs them.

Reference: Apple's Metal documentation for `MTLTextureDescriptor.placementSparsePageSize`,
`MTLHeapType.placement`, and `MTL4CommandQueue.updateMappings(texture:heap:operations:)`.

## Sparse textures and the tile pool

A placement-sparse texture has no memory of its own. Its memory is a set of tiles, and each
tile maps to a slot in a placement heap. A read from an unmapped tile returns zero on a GPU
with sparse tier 2, so a missing tile draws black and never faults.

- The levels above the tail map tile by tile. The small levels share one packed tail, and
  the tail is always mapped. The texture's `firstMipmapInTail` and `tailSizeInBytes` give
  the split.
- One tile is 16 KB (`MTLSparsePageSize.size16`). Observed on an M1 through
  `MTLDevice.sparseTileSize`: a BC1 tile is 256 x 128 texels, a BC3, BC5, or BC7 tile is
  128 x 128, and an RGBA8 tile is 64 x 64. An ASTC tile holds 32 x 32 blocks, so ASTC 4x4
  is 128 x 128 texels, 5x5 is 160 x 160, 6x6 is 192 x 192, and 8x8 is 256 x 256. All four
  ASTC formats made placement-sparse textures on the M1 (2026-10-09).
- The tiles come from a pool of 16 MB placement heaps. The pool adds a heap when it runs
  out and drops a heap when all its tiles are free, so its size follows what is mapped.
- The draw binds a texture view whose base level is the first resident level, so the
  sampler never picks an unmapped level.

Only a texture with mip levels and at least 512 texels on its long side streams, in a BC or
an ASTC format. A level is copied whole, row by row of blocks, so the block size does not
change the copy.
A smaller texture fits in its tail and gains nothing. A GPU without sparse tier 2 loads
every texture whole.

## How a texture streams

1. The cell build worker loads a texture. If it streams, the worker creates the sparse
   texture and keeps only the levels of 512 texels and smaller. It posts the texture and
   those bytes to a mailbox.
2. At the start of each frame, the renderer drains the mailbox. It maps tiles for the new
   levels, copies the bytes into them, and puts a barrier before the passes that read them.
3. Every 8 frames, the renderer picks each texture's level. It compares texels per world
   unit with pixels per world unit at the closest surface that uses the texture. That gives
   the level with about one texel per pixel; one finer level is kept for slanted surfaces.
   Texels per world unit come from the mesh's UV density: the square root of its UV area
   over its world area, measured once at load. A tree maps its whole branch texture onto
   each of many small cards, so its density is high, and the mesh size alone would pick a
   level far too coarse. A landscape texture repeats every two terrain quads
   ([terrain](/engine/terrain.md)).
   A scene texture the rule does not measure, such as grass or particles, keeps all its
   levels. A grass texture keeps them even when a static far away shares it. A texture
   outside the scene lists, such as the player's first-person body, keeps the levels it
   has.
4. A texture that needs finer levels asks the worker to read them again from the asset
   cache or the archive. They arrive in the mailbox a few frames later, and the frame maps
   and fills them.
5. A texture that needs fewer levels unmaps them after the frames in flight finish. It keeps
   one extra level as slack, so a texture near the line does not flip each update.

## Budget

If the wanted levels pass the budget, the farthest textures drop one level at a time until
the levels fit. A texture never drops below its tail, so the floors alone can pass the
budget. The Graphics page calls the budget "Memory for close-up detail". Automatic, the
default, takes a quarter of what the GPU can still use: Metal's
`recommendedMaxWorkingSetSize` minus `currentAllocatedSize` when the renderer starts,
rounded down to 64 MiB and held between 256 MiB and 4 GiB. A quarter leaves room for meshes,
render targets, and the next cells. Five fixed choices from 128 MiB to 2 GiB stay for
measurements.

## Settings and checking it

The app streams textures by default. The player setting `rendering.textureStreaming` turns
it off; off raises every streamed texture to its full size, and on applies to textures
loaded from then on. The `Renderer` type itself starts with streaming off, so a render test
that builds one loads textures whole unless it turns streaming on. `rendering.textureBudget`
picks the budget, with 0 for Automatic. The launcher's Graphics page ("Full detail only near
the camera") and
`Developer > Rendering Performance > Texture Streaming` write both
(`TextureStreamingEnabledControl`, `TextureBudgetControl`). The readout
(`TextureStreamingStatsLabel`) shows the streamed textures, the mapped memory against the
budget, the heap memory, and the levels loaded and dropped.

`make benchmark ARGS=--texture-streaming` measures it, and `--texture-budget <MiB>` sets the
budget ([benchmark](/tools/benchmark.md)). The heaps count as texture memory in the GPU
memory samples.
