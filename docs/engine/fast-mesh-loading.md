---
type: Subsystem
title: Fast mesh loading
description: How a cached mesh entry lays out its vertex and index bytes so Metal fast
  resource loading can read them straight into GPU buffers, when it runs, and what it measured.
tags: [engine, assets, cache, loading, metal4]
---

# Fast mesh loading

Fast mesh loading reads the vertex and index bytes of a cached mesh straight from its entry
file into GPU buffers, with Metal fast resource loading (MTLIO). It works like fast texture
loading ([asset cache](/engine/asset-cache.md), "Fast resource loading"): the CPU does not
copy the bytes.

Reference: Apple, `MTLIOCommandQueue` and `MTLIOCommandBuffer.load(_:offset:size:sourceHandle:sourceHandleOffset:)`.

## Mesh entry payload

A mesh entry (converter version 2) puts the GPU bytes first, so the loader can find them
without decoding the whole model. All integers are little-endian.

| Field | Size | Meaning |
| --- | --- | --- |
| layout length | 8 | Bytes of the layout block |
| layout | n | Shape counts, materials, the model's byte range, then per mesh: name, transform, material slot, counts, bounds, byte ranges |
| padding | 0 to 15 | Zeros, to a 16-byte boundary |
| GPU blocks | n | Per mesh: interleaved vertices (48 bytes each), then `uint16` indices; each block starts on a 16-byte boundary |
| model | n | The whole decoded model, as in version 1 |

The vertex block uses the same 48-byte interleaved layout as a mesh built on the CPU, so a
buffer filled either way draws the same. The layout stores each byte range from the start
of the GPU blocks, and the reader adds the payload offset of that start.

A lookup reads only the head of the entry: 64 KiB, or more when the layout is longer. It does
not read the GPU blocks or the model.

## When it runs

- Only during a cell build, in the same batch as the textures. Fast texture loading must be
  on too, because it opens the batch.
- Only for a plain load: no terrain LOD clip, surface override, rigid attachment, or
  explicit skeleton. Those change the mesh after decoding, so they take the CPU path.
- Only when every mesh of the model is ready: not skinned, not empty, and every index
  inside the vertex count. Otherwise the model takes the CPU path.
- If the IO command buffer fails, every buffer of the batch is filled on the CPU from the
  same entry.

The setting "Fast mesh loading" (`assetCache.fastMeshLoad`) is off by default. It is on the
launcher's Asset Cache page under Loading, and in World > Asset Cache.
`openskycli benchmark --asset-cache --fast-load --fast-mesh-load` measures it.

## Measured

On 2026-10-07, on an Apple M1 with the Release `openskycli`, the benchmark block was loaded
cold (`--evict`) from a cache built for its paths. There were three runs of each mode, in
turn. Run directory: `.logs/fast-mesh-load/20261007T183338Z`.

| Mode | Cold load | Mesh phase |
| --- | --- | --- |
| `--fast-load` | 3979, 3991, 4112 ms | 569, 573, 595 ms |
| `--fast-load --fast-mesh-load` | 4003, 4022, 4190 ms | 568, 569, 618 ms |

The two modes render the same frame (PSNR 100 dB). The 464 cached meshes hold 6 MiB, so
reading their bytes was never the slow part of the mesh phase. That is why the setting is
off by default.
