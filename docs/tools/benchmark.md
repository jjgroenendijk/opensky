---
type: Tool
title: Benchmark tour
description: The one benchmark for load time, frame time, and GPU time - a camera tour through
  cities, wilderness, interiors, and DLC worlds in the live game window, how to run it from the
  launcher and the CLI, what each scene measures, and the result shape.
tags: [tool, performance, benchmark]
---

# Benchmark tour

The benchmark flies a camera through a fixed list of places in the live game window and
measures every frame. One tour serves the launcher, the CLI, and the agent socket, so their
numbers compare. A second benchmark definition would give numbers that do not compare, so
every performance change measures its win with this one.

## Run it

| From | How |
| --- | --- |
| Launcher | The Benchmark page: pick a length, then Run Benchmark. The page shows the newest result |
| CLI | `openskycli benchmark [--preset quick\|standard\|full]` opens the app and waits for it to quit |
| Make | `make benchmark PRESET=quick` builds Release and keeps the output in `.logs/benchmark/` |
| Running app | `openskycli game benchmark quick` starts the tour in the open game window |
| App flag | `OpenSky.app --benchmark-request '<json>'`; this is what `openskycli benchmark` passes |

A run writes `result.json` and `summary.txt` into its folder. The default folder is
`~/Library/Application Support/OpenSky/Benchmarks/<UTC time>Z/`; `--out <folder>` picks
another. The launcher and the Diagnostics page read the newest folder there.

CLI options:

| Option | What it does |
| --- | --- |
| `--preset` | `quick` (3 scenes), `standard` (every base-game scene), or `full` (DLC worlds too) |
| `--scenes a,b` | These scene ids only, in tour order; `--list` prints every id |
| `--set id=value,...` | Overrides player settings for this run only, comma-separated: `--set a=on,b=off` |
| `--no-overlay` | Starts with the readout hidden |
| `--capture <id>` | Writes a GPU trace (`.gputrace`) of that scene's first measured frame |
| `--screenshots` | Saves the window at the start, middle, and end of each shot as PNGs in the run folder |
| `--windowed` | Runs in the window. By default the window fills the screen for the tour and comes back after it; a window that was already full screen stays so |
| `--no-load-passes` | Skips the cold and warm load passes |
| `--evict` | Drops the game data from the page cache first, so the loads read from disk |
| `--keep-open` | Leaves the app open after the tour |
| `--app <path>` | Which `OpenSky.app` to open; the default is the installed one |

The CLI exits 1 when a scene fails, and such a result does not compare with a clean run.

`--set` takes the ids of the player settings catalog. A toggle takes `on` or `off`, a choice
takes its option text, and a number takes a number. For example:
`--set rendering.gpuCulling=off`, `--set rendering.renderScale=67%`,
`--set rendering.meshShaderGrass=on`, `--set assetOptimisation.directLoad=off`. The override
lives only in the app's memory and is never saved.

`--evict` uses `msync` with `MS_INVALIDATE`, the method of `vmtouch -e`, and needs no `sudo`.

## While it runs

Every way to start a run fills the screen with the game window for the tour, so the
measured frame is the display's size. The window comes back when the run ends. "Full
screen" on the launcher page and `--windowed` on `openskycli benchmark` or `game benchmark`
keep the window instead.

The Play window gets a toolbar with two buttons for the length of the run. The overlay
button shows or hides the readout: the scene, its number, its progress, and the frame rate.
The stop button ends the tour and keeps the scenes measured so far; the result then says
`stopped`. The Developer window keeps both buttons in its own toolbar.

The tour takes over the game for its length. It switches to fly mode, freezes the game
clock, hides the in-game HUD, and steps the world by a fixed 1/60 s each frame. At the end it
gives back the movement mode, the clock, the HUD, the camera, and the weather.

## The scenes

Each scene has a place, a time of day, a weather, and a camera shot. Each shot runs 16 s, so
every scene weighs the same in the tour total. Four shot kinds give different loads:

- `dolly`: the eye follows a spline and looks along a second spline, as through a street.
- `orbit`: a circle around a point, so the view sweeps the whole area.
- `flyover`: a straight, fast flight that streams cells in on the way.
- `pan`: the eye stands still and turns. Interiors use it.

| Group | Scenes |
| --- | --- |
| Cities | Whiterun, Solitude, Riften, Markarth, Windhelm |
| Wilderness | Whiterun plains, Rift forest, Falkreath pines, Throat of the World, Hjaalmarch marsh, Winterhold coast, Blackreach |
| Interiors | Dragonsreach, Bleak Falls Barrow, Mzinchaleft, Blue Palace, Ragged Flagon |
| DLC worlds | Forgotten Vale, Soul Cairn (Dawnguard); Raven Rock, Tel Mithryn (Dragonborn) |

The quick preset takes one scene each of a city, the wilderness, and an interior.

A DLC scene names the plugin it needs. When the load order lacks it, the scene is `skipped`
with a note, and the result still compares. The positions come from the install's map
markers and cell lists, read with `openskycli record show` and `openskycli cell --refs`
(`--cell <editorID>` lists an interior). An exterior shot's points are offsets from the
ground under the scene's position. Solitude and Windhelm stand on meshes, and their cells
hide the terrain under them, so no ground sample exists there. Those scenes give a street
height instead, read from the `cell --refs` positions of doors and floors. An interior
shot's points are cell coordinates in the cell's main room, because the door often opens
into a side passage.

The origin is taken again once streaming settles, because at arrival the ground under it
may not be resident yet.

An exterior eye stays at least 300 units above the ground. It also keeps an 80-unit sphere clear
of static collision, such as rocks, walls, and roofs, by rising in 100-unit steps. A sphere deep
inside a large rock touches no triangle, so the eye also rises while the line from its last
position to the next one hits collision. It keeps 600 units of open view along its level look
direction, so a shot does not end against a cliff. These checks also run on the path 2 s
ahead, so a flight climbs before a hill or a rock instead of cutting into it. The camera rises
smoothly and sinks back slowly. Interior shots get none of this, because a rising eye would
go through the ceiling; they are placed by hand. Tree crowns have no collision, so a
shot over a forest is written high enough to clear them. The tour hides the HUD on every frame,
because a loading screen shows it again when it ends.

## What a scene measures

Every scene runs the same steps:

1. Arrival: the camera teleports to the place, and the time until streaming is done counts
   as `arrivalMS`. Streaming is done when no cell is in flight, queued, or waiting to finish.
   Its cell builds split into load phases (below). An arrival that takes over 150 s fails.
2. Warm-up: 120 frames at the first pose of the shot, so first uploads and pipeline creation
   do not land in the measured frames. Settling has its own 45 s limit.
3. Measuring: the shot plays, one 1/60 s step a frame. Every frame is recorded.

Per scene the result holds:

- `frameTime` and `gpuTime`: average, 95th and 99th percentile, the worst frame, and the 1%
  low frame rate. GPU time is the time between Metal's start and end of each frame's command
  buffer, so it leaves out the CPU encode and the wait.
- `passes`: GPU time per pass, read from Metal counter heaps: `setup` (texture streaming and
  the ray-traced shadow build), `shadows`, and `scene`, the main render pass. Apple GPUs run
  the draws of one render encoder together, tile by tile, so a timestamp inside an encoder
  does not split its time. On an M1, marks inside the scene encoder put almost the whole pass on
  the first mark. The timer therefore marks only the boundaries between encoders. For the cost of one
  layer inside the scene pass, compare two runs with that layer off, or read a `--capture`
  trace in Xcode.
- `cpu`: CPU time per subsystem: `simulation`, `animation`, `shadows`, `encode`, `scripts`,
  and `audio`. Each is read from the frame before.
- the average draw calls and drawn instances. Two runs with different counts drew different
  views.
- `gpuMemory`: the GPU memory allocated, sampled every 30 frames.

The whole tour also gets a `frameTime` and `gpuTime` over every measured frame.

Each scene is an `OSSignposter` interval in the `Benchmark` category, so an Instruments trace
shows where each scene starts and ends. `make profile` records one
([testing](/testing.md), Profiling).

## Load time

A run from the CLI or the app flag times the app's own start: from the kernel's process
start until the world is ready (`processToWorldReadyMS`), each world load stage, and the
session start phases. A launcher run starts in a process that is already running, so it has
no app start.

Before the first scene, unless `--no-load-passes` is given, a new cell builder with empty
caches builds the first scene's cells twice off screen: once cold, then again warm with its
caches full. An exterior builds the 3 by 3 block around its origin and its distant LOD. The
live streamer is not touched. A cold load here means cold OpenSky caches. The operating
system may still hold the archive bytes from an earlier run; `--evict` drops them.

### Load phases

Each load pass, and each arrival, splits its time into phases. A phase counts only its own
time. A mesh load that reads an archive gives the read to `archive`, and the rest to `mesh`.

| Phase | What it holds |
| --- | --- |
| `archive` | Reading loose files and archive entries, decompression included |
| `texture` | DDS parsing and the GPU texture upload |
| `mesh` | NIF parsing, flattening, and GPU buffer building, terrain included |
| `collision` | Static collision, trigger volumes, and dynamic bodies |
| `other` | Everything else: record lookups, actors, lighting, setup |

A cell builder reports phases when a `LoadPhaseRecorder` is attached to it and its file
source is wrapped in `PhaseTimedFileSource`. Normal play attaches none and pays one nil check
per asset load. The app attaches one only when a tour will run.

## The result

`BenchmarkTourResult` is the one result shape. The JSON has sorted keys and ISO 8601 dates,
so two results diff line by line. It holds the machine, the build configuration, the preset,
the frame size, every setting that differs from its default, the overrides, the app start,
the cold and warm load, each scene, and the tour totals.

`isComparable` is true when no scene failed, the tour was not stopped, and every load built.
Compare only two comparable runs on the same machine, preset, and build configuration. A
Debug build is much slower, and the result says which build ran it.

`schemaVersion` changes when a field changes meaning or goes away. A new field is optional,
so an older result still decodes. Version 2 is the tour; version 1 results do not decode.

## Screenshots

`--screenshots` (or "Save screenshots" on the launcher page) writes
`<number>-<scene id>-start.png`, `-middle.png`, and `-end.png` into the run folder, from the
frame the window presents. They show whether a shot frames its place. Writing a PNG takes
main-actor time inside the measured frames, so such a run is not comparable. The PNGs embed
game assets, so keep them in `.logs/` or the default folder and never commit them.

## GPU capture

`--capture <id>` sets `MTL_CAPTURE_ENABLED=1` for the app, because Metal allows a
programmatic capture only with it. The trace lands in the run folder as `<id>.gputrace`.
It embeds game assets, so keep it in `.logs/` or the default folder and never commit it.

## Where the code lives

`BenchmarkTourCoordinator` in `OpenSkyWorld` holds the tour rules: the phases, the timeouts,
the skipped scenes, and the result. It talks to the game through the `BenchmarkTourWorld`
port, so `BenchmarkTourCoordinatorTests` runs a whole tour against a fake world. The app's
`BenchmarkWorldAdapter` is the live game window behind that port.

The old fixed-path gates for streaming, walking, and sustained frame time are now real-data
tests: `FlyPathGateRealDataTests`, `WalkPathGateRealDataTests`, and
`SustainedRenderGateRealDataTests`. `make test-real PERF=1` runs them.
