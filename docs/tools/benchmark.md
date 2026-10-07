---
type: Tool
title: Shared performance benchmark
description: The one repeatable benchmark for load time, frame time, GPU time, and GPU memory -
  what it measures, its launch and route modes, how load time splits into asset phases, the
  result shape, and how to run it.
tags: [tool, performance, benchmark]
---

# Shared performance benchmark

One benchmark measures load time and frame time on the real install. Every later
performance item measures its win with it, and the app shows the same result. A second
benchmark definition would give numbers that do not compare, so callers reuse this one.

## Run it

`make benchmark` builds a Release `openskycli` and runs
`openskycli benchmark --launch --route`. It writes
`.logs/benchmark/<UTC timestamp>/` ([run output](/tools/run-output.md)):

- `benchmark.log`: the printed summary.
- `result.json`: the full result.
- `view.png`: the measured view, to check that it drew. It embeds game assets, so it stays in
  `.logs/` and is never committed.

`openskycli benchmark --out <file>` runs the same steps from any build. A Debug build is
much slower, and the result says which build ran it.

`--asset-cache` loads textures and meshes through the [asset cache](/engine/asset-cache.md),
with the preset and folder from the app settings unless `--preset` or `--folder` overrides
them. The summary then prints the cache hits and misses. `--evict` first drops the game data
and the cache folder from the page cache, so the cold load reads from disk. It uses `msync`
with `MS_INVALIDATE`, the method of `vmtouch -e`, and needs no `sudo`.

`--loose <dir>` reads the files that `asset-cache extract` copied there before the archives.
Comparing a run with it against a run without it separates the cost of the archive from the
cost of the parse. `--record-paths <file>` writes the asset paths the cache was asked for,
so `asset-cache build --paths` and `extract --paths` can work on just the benchmark's assets.
The summary also prints the GPU memory allocated after the load.

`--fast-load` loads the cached textures of each cell with Metal fast resource loading
([asset cache](/engine/asset-cache.md)) and prints the batches, textures, and bytes it
read. `bench --fly-path` and `bench --walk-path` take the same cache options, so the cell
loads while streaming can be compared with and without it.

`--size WxH` sets the frame size. The default is 2560 by 1600, the size of a Retina
display, because upscaling and other per-pixel work only show their cost at display sizes.
`--launch` and `--route` add the two modes below; `--launch-seconds <s>` changes the 60
seconds of the launch mode.

The command exits 1 when a cell fails to build. Such a result does not compare with a
clean run.

## What it measures

The plan is fixed, so every run loads the same cells and renders the same view:

1. A cold load: a new cell builder with empty caches builds the first-render cell, Tamriel
   `(6,-2)`, and its eight neighbors. Then it builds distant LOD around that block, and the
   farmhouse interior the walk benchmark enters.
2. A warm load: the same builder builds the same cells again, with its caches full.
3. Frame time: the nine exterior cells and the distant LOD from the warm load render
   offscreen at the frame size. 60 frames warm up; 600 frames are measured.

The camera stands at the walk benchmark's start point, at player eye height over the
terrain, and looks level toward the farm. A camera that frames the cell bounds does not
work: a few placed objects sit far outside their cells, so the framed view shows the block
from far away.

Each frame waits for the GPU, so frame times are an upper bound on the pipelined game loop.
The result reports the average, the 95th percentile, and the worst frame. It also reports the
last frame's draw calls and drawn instances: two runs with different counts drew different
views.

GPU time is the time the GPU spent on each frame's command buffer. Metal's commit feedback
gives the GPU start and end time of each commit, the same numbers the frame HUD shows. It
leaves out the CPU encode and the wait, so it shows GPU work apart from wall-clock time.
Feedback can arrive after the last frame ends, so the GPU frame count can be one lower.

CPU encode is the CPU time that the shadow and scene passes take to encode each frame. It
holds culling, the per-draw uniform writes, and the draw calls, and leaves out the wait for the
GPU. The static scene culls on the GPU, as in the app ([GPU culling](/rendering/gpu-culling.md)).
`--cpu-culling` culls it on the CPU instead, and the `gpuCulling` field says which path ran.
The drawn instance count adds the GPU's camera count, so the two paths compare.

GPU memory is sampled after each load pass and after each measured frame:

- total: `MTLDevice.currentAllocatedSize`, every GPU allocation of the process;
- render targets: resident textures that a pass renders into, such as the color and depth
  targets and the shadow maps;
- textures: resident textures that shaders only read.

The result keeps the peak of each value and the last sample. The two parts come from the
renderer's residency set, so buffers and short-lived staging memory count only in the total.

The grass line gives the grass draws and instances in the last measured frame. Zero draws
means the view shows no grass, so a grass change cannot show a win there.

## Launch mode

`--launch` times the start of a fresh process. After the cold load, the cold-loaded view
renders frames for 60 seconds before the warm load starts. The result holds:

- `processToFirstFrameMS`: from the process start, as the kernel records it, to the end of
  the first frame. It holds Metal setup, the cold load, and the first frame.
- `firstFrameMS`: the first frame alone. Pipeline creation and first uploads land here.
- `frameTime`: every frame of the 60 seconds, so its worst frame is the worst frame of the
  first minute.

The [pipeline cache](/rendering/pipeline-cache.md) saves compiled pipelines in the asset
cache folder. `--cold-pipelines` (`make benchmark ARGS=--cold-pipelines`) deletes the archive
first, so the run compiles every pipeline and saves a new archive. A second run without it
then loads them. The `pipelines` field holds the renderer setup time, the archive state, and
how many pipelines were loaded and compiled. macOS also caches compiled shaders between runs,
so the first run after a build or a reboot can be slower for that reason too.

## Route mode

`--route` walks the shared route of `bench --walk-path` at the frame size: across a cell
border, up stairs, through a door into the farmhouse, and back. Cells stream in while it
walks. One route serves both tools, so their numbers compare.

The route uses a new cell builder with empty caches; the file cache of the operating system
may still be warm. The result holds:

- `frameTime`: every frame of the route, the frames that wait for a cell included. Its worst
  frame is the worst frame while streaming.
- `gpuTime`: GPU time over the same frames.
- `cellLoads`: each cell, distant LOD, and door build, with its time and any error. Builds
  run off the main thread, so a slow build shows as a wait, not as a long frame.

The walk gates still apply: a route that does not climb the stairs or cross the interior
fails the command. The route runs without the audio engine of `bench --walk-path`, so its frame times
are a little lower than that command's.

The cold load runs in the same process as the first file access, but the operating system
may still hold the archive bytes in its file cache from an earlier run. A cold load here
means cold OpenSky caches, not a cold disk.

## Load phases

Each load pass splits its time into phases. A phase counts only its own time. A mesh load
that reads an archive gives the read to `archive`, and the rest to `mesh`.

| Phase | What it holds |
| --- | --- |
| `archive` | Reading loose files and archive entries, decompression included |
| `texture` | DDS parsing and the GPU texture upload |
| `mesh` | NIF parsing, flattening, and GPU buffer building, terrain included |
| `collision` | Static collision, trigger volumes, and dynamic bodies |
| `other` | Everything else: record lookups, actors, lighting, setup |

Distant LOD has its own line in the cell list, and its asset work counts in the phases.

A cell builder reports phases when a `LoadPhaseRecorder` is attached to it and its file
source is wrapped in `PhaseTimedFileSource`. Normal play attaches none and pays one nil check
per asset load. The recorder handles one thread of loading. Two threads loading at once
would mix their phase times.

## The result

`PerformanceBenchmarkResult` is the one result shape. The JSON has sorted keys and ISO 8601
dates, so two results diff line by line. It holds:

- the machine: model, CPU, GPU, memory, and macOS version;
- the build configuration: `debug`, `optimizedDebug`, or `release`;
- the plan;
- the cold and the warm load pass, each with its total, its phases, and each cell's time;
- the frame time, with `gpuTime`, `encodeTime`, `gpuCulling`, and `grass`;
- `gpuMemory`, with `peak` and `last`, each holding `totalMB`, `renderTargetMB`, and
  `textureMB`;
- `launch` and `route`, when their mode ran;
- `pipelines`: the renderer setup time and the pipeline cache counts.

A field added after the first version is optional, so an older result still decodes with that
field empty.

`schemaVersion` changes when a field changes meaning or goes away. A new field does not
need a new version. The frame size is part of the plan, so a result at another size says so
in its own plan.

## Calling it from the app

`PerformanceBenchmark.run` lives in `OpenSkyWorld`, so the app can call it without the
CLI. The caller passes a renderer and a closure that builds a fresh `CellSceneBuilder`
reporting into the given recorder. The CLI's builder is the example.
