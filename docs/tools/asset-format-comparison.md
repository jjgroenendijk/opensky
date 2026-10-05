---
type: Tool
title: Asset format comparison
description: The repeatable comparison of cache formats per asset kind - the fixed sample, the
  candidates, the two load paths, what each number means, the preset rule, and how to run it.
tags: [tool, performance, benchmark, cache, texture, astc, mtlio]
---

# Asset format comparison

The asset cache converts game files into formats that load faster on Apple Silicon. This
comparison measures which format to use for each asset kind before a converter exists. It
loads a fixed sample of base-game files the current way and from every candidate cache
format, on the same machine and build record as the [shared benchmark](/tools/benchmark.md).

## Run it

`make asset-formats` builds a Release `openskycli` and runs `openskycli asset-formats`.
`make asset-formats KIND=texture` measures one asset kind. The run writes
`logs/asset-formats/<UTC timestamp>/` ([run output](/tools/run-output.md)):

- `asset-formats.log`: one line per asset, one line per candidate total, and the picks.
- `result.json`: the full result, with sorted keys, so two runs diff line by line.

The cache files are game content. They live in `scratch/` inside the run directory while a
candidate is measured, and are deleted afterwards. The command exits 1 when a sampled asset
cannot be loaded.

The whole run takes minutes, mostly ASTC encoding of the 4096 textures. Other work on the
machine adds noise, so each row repeats the load 5 times and keeps the run with the median
total. The result records the 1-minute load average at the start and the end.

## The sample

`AssetFormatComparisonPlan.standard` lists archive paths, so every run reads the same files:

| Kind | Sample |
| --- | --- |
| Texture | 16 files: color, normal, and data maps; BC1, BC3, and 32-bit; 64 to 4096 texels |
| Mesh, collision | 6 static models, from a pitchfork to a Whiterun house, and one tree |
| Animation | 4 Havok clips: three character clips and one creature clip |
| Audio | 2 WAV effects, 1 xWMA music track, and 1 FUZ voice line |

## Candidates

Every candidate is a format that macOS and Apple Silicon support natively.

| Kind | Candidates |
| --- | --- |
| Texture | `shipped` BC blocks; `rgba8`; `astc4x4` to `astc12x12` at medium effort; `astc6x6` at fastest, fast, and thorough effort; `shippedHalf` and `shippedQuarter`, the shipped blocks without the largest one or two mip levels |
| Mesh | `shipped` NIF; `ready` GPU vertex, index, and skin buffers |
| Collision | `shipped` NIF; `ready` shape transforms, vertices, and indices |
| Animation | `shipped` HKX; `ready` bone poses of every frame, ten floats per track |
| Audio | `pcmFloat32`, `alac`, and `aac` in a CAF file |

The `original` row is the current engine path: the archive entry read through the file
system, then parsed. The `shipped` rows store the same file loose in the cache, which shows
what leaving the archive alone gains.

Each cache candidate is stored five ways: `raw`, or compressed with `lz4`, `lzfse`,
`lzBitmap`, or `zlib` in the chunked format of Metal fast resource loading. Audio is stored
raw only, because AAC and ALAC are already compressed.

ASTC comes from the vendored [astcenc](/decisions/astcenc.md), which encodes each mip level
of the GPU-decoded shipped texture. ETC2 and PVRTC are native too, but they are no better than
BC or ASTC at the same size, so they are left out.

## Load paths

| Path | What it does |
| --- | --- |
| `archive` | The file system reads and decompresses the entry; the engine parses it |
| `cpu` | The cache file is mapped when raw, or decompressed by MTLIO into memory, then copied into GPU resources or engine arrays |
| `mtlio` | Metal fast resource loading reads and decompresses the file straight into the texture or buffers |

All loads are warm: each cache file was just written, and the archive was read by the
earlier repeats, so the bytes come from the page cache. The numbers compare decode and copy
cost, not cold disk reads.

Textures and meshes load on both cache paths. Collision, animation, and audio have no GPU
resource, so they load on `cpu` only. Each loaded texture or buffer is compared with the
cache payload byte for byte; a difference is an error on that row.

## What each number means

- `readMS`: reading and decompressing. On `mtlio` it also holds the copy into the GPU.
- `decodeMS`: parsing or decoding into engine values. For audio from CAF it is the whole
  AudioToolbox read, because AudioToolbox reads the file itself.
- `uploadMS`: building GPU resources or engine arrays.
- `memoryBytes`: the GPU allocation of a texture or the mesh buffers, the raw arrays of
  collision and animation, and the decoded samples of audio. The `original` animation row
  counts the HKX file, because the engine keeps the spline data, not poses.
- `diskBytes`: the bytes the archive stores for `original`, or the cache file size.
- `convertMS`: time to build the cache payload from the archive bytes, parse included. For
  ASTC it holds the DDS parse, the GPU decode of the shipped levels, and the encode. For
  audio it holds the decode of the shipped file and the CAF write.
- `writeMS`: time to compress and write the cache file.
- `fidelity`: `exact` when bytes or pixels match. Lossy textures report the PSNR over RGB and
  alpha, the largest channel error, and for normal maps the mean angle between normals.
  Audio reports the signal-to-noise ratio against the shipped file decoded by the engine.

Texture pixels compare as the GPU decodes them. A render pass samples both textures into
RGBA8, in the stored values, not linearized. A half or quarter size candidate is resampled
bilinearly to full size first. Only mip level 0 is compared.

Ready forms leave out small fields: mesh materials, collision body settings such as filters
and dynamics, and animation annotations. Their parse cost is not in the `ready` rows.

## The preset rule

`AssetFormatRecommendation` sums each candidate over the assets of one kind and texture role,
then picks one per quality preset. A candidate with an error, or one missing on some asset,
is not picked.

| Preset | Loss allowed | Picks |
| --- | --- | --- |
| `highestQuality` | None | The fastest total load |
| `balanced` | 40 dB RGB, 2 degrees on normals, 20 dB audio SNR | The least memory, then the fastest |
| `bestPerformance` | 30 dB RGB, 5 degrees on normals, 10 dB audio SNR | The least memory, then the fastest |

Memory comes before speed in the lossy presets, because the CPU and the GPU share one
memory on Apple Silicon. A texture the GPU holds is memory the engine cannot use.

These limits are starting values. The asset quality presets set the final ones.

## Whole-game estimate

Before the sample is measured, `AssetCensus` walks every archive entry of the measured kinds
and counts work units: texels over all mips for a texture, read from its DDS header, and
stored bytes for the other kinds. A NIF counts as both a mesh and a collision source. A
texture's role comes from its name suffix: `_n` and `_msn` are normal maps; `_s`, `_sk`,
`_em`, `_e`, `_g`, `_m`, `_p`, `_b`, and `_h` are data maps; the rest are color maps.

For each candidate and storage, the processing time of one sampled asset is its archive
read, `convertMS`, and `writeMS`. `AssetProcessingEstimate` scales the sum over the sample
by the install's work units divided by the sample's. The log prints it for every candidate,
and per preset the total for the picks, on one core and divided by the core count. The
divided number is a lower bound: the efficiency cores are slower, and astcenc runs one
thread per texture. The archive reads are warm, so a cold first run reads slower.
