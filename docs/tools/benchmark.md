---
type: Tool
title: Shared performance benchmark
description: The one repeatable benchmark for load time and frame time - what it measures, how
  load time splits into asset phases, the result shape, and how to run it.
tags: [tool, performance, benchmark]
---

# Shared performance benchmark

One benchmark measures load time and frame time on the real install. Every later
performance item measures its win with it, and the app shows the same result. A second
benchmark definition would give numbers that do not compare, so callers reuse this one.

## Run it

`make benchmark` builds a Release `openskycli` and runs `openskycli benchmark`. It writes
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

The command exits 1 when a cell fails to build. Such a result does not compare with a
clean run.

## What it measures

The plan is fixed, so every run loads the same cells and renders the same view:

1. A cold load: a new cell builder with empty caches builds the first-render cell, Tamriel
   `(6,-2)`, and its eight neighbors. Then it builds distant LOD around that block, and the
   farmhouse interior the walk benchmark enters.
2. A warm load: the same builder builds the same cells again, with its caches full.
3. Frame time: the nine exterior cells and the distant LOD from the warm load render
   offscreen at 1280 by 720. 60 frames warm up; 600 frames are measured.

The camera stands at the walk benchmark's start point, at player eye height over the
terrain, and looks level toward the farm. A camera that frames the cell bounds does not
work: a few placed objects sit far outside their cells, so the framed view shows the block
from far away.

Each frame waits for the GPU, so frame times are an upper bound on the pipelined game loop.
The result reports the average, the 95th percentile, and the worst frame. It also reports the
last frame's draw calls and drawn instances: two runs with different counts drew different
views.

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
- the frame time.

`schemaVersion` changes when a field changes meaning or goes away. A new field does not
need a new version.

## Calling it from the app

`PerformanceBenchmark.run` lives in `OpenSkyWorld`, so the app can call it without the
CLI. The caller passes a renderer and a closure that builds a fresh `CellSceneBuilder`
reporting into the given recorder. The CLI's builder is the example.
