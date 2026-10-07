---
type: Subsystem
title: Pipeline cache
description: How the renderer saves its compiled pipelines to disk and loads them on the next
  launch, when an archive is stale, and how to check it.
tags: [rendering, metal4, performance, cache]
---

# Pipeline cache

The renderer builds all its render pipelines when it starts. A pipeline is a compiled pair of
shaders plus its fixed state. Compiling one takes time, so the renderer saves the compiled
binaries in a Metal 4 archive, and later launches load them from it.

## How it works

1. The renderer compiles through one Metal 4 compiler. A pipeline data set serializer is
   attached to it with the `captureBinaries` configuration, so it keeps each compiled binary.
2. After setup, a launch that compiled every pipeline writes them to the archive with
   `serializeAsArchiveAndFlush(url:)`.
3. A later launch opens the archive with `makeArchive(url:)`. Each pipeline is looked up there
   first. A pipeline the archive lacks is compiled.

The serializer only keeps pipelines the compiler made, not ones loaded from the archive. So a
launch that loaded some pipelines and compiled others deletes the archive. The next launch
then compiles everything and saves a full archive again.

## When an archive is stale

A compiled binary fits one OS build, one GPU, one shader library, and one app binary. The
archive name is a hash of all four: the OS version string, the GPU name, and the size and
modification time of `default.metallib` and of the executable. A new build or an OS update
gives a new name, and saving deletes every other archive in the folder.

Metal crashes on a damaged archive instead of returning an error (observed on macOS 27 with
an M1). So each save writes the SHA-256 of the archive beside it, in `<name>.sha256`, and a
launch hands the archive to Metal only when the two match. A damaged or unchecked file is
deleted, every pipeline compiles, and the launch saves a new archive.

## Where it lives

The archive is in `pipelines/` inside the [asset cache](/engine/asset-cache.md) folder, so the
one folder setting places both caches. It holds only OpenSky's own shaders, no game content.
A process without a `default.metallib` in its bundle, such as a package test, gets no archive.

## Checking it

`Developer > Rendering Performance > Pipeline Cache` has the switch
(`PipelineCacheEnabledControl`), a clear button (`PipelineCacheClearControl`), and the counts
of this launch (`PipelineCacheStatsLabel`): pipelines loaded from the archive and pipelines
compiled. The switch is the `pipelineCache.enabled` player setting and applies on the next
launch.

`make benchmark ARGS=--cold-pipelines` deletes the archive first; the `pipelines` field of the
result holds the renderer setup time and the counts ([benchmark](/tools/benchmark.md)).
