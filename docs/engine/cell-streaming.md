---
type: Subsystem
title: Cell streaming
description: How the camera position picks a grid of exterior cells, how cells build on one
  serial queue and stream in and out with a per-frame limit, and how assets and memory stay
  bounded.
tags: [engine, world, streaming, esm, concurrency]
---

# Cell streaming

Streaming has two halves:

- The grid manager decides which cells the camera wants. It is a pure value type with no Metal,
  no files, and no concurrency, so it is tested without a renderer.
- The streamer builds those cells off the main thread and hands the finished scenes to the
  renderer.

## Cell coordinates

One exterior cell is 4096 world units. Cell `(x, y)` covers world X from `x * 4096` up to (not
including) `(x + 1) * 4096`, and the same for Y ([coordinates](/decisions/coordinates.md)).

The coordinate is the floor of `position / 4096`, rounding down, not toward zero. A camera at
X = -1 must land in cell -1, not cell 0. Rounding toward zero would put every position just below
zero in cell 0, which is wrong for the whole negative quarter of the world.

## The desired grid

`uGridsToLoad` in the Skyrim INI is the full side length of the grid.
It is always odd, and 5 by default. The grid manager stores the number of rings around the
center instead: `(uGridsToLoad - 1) / 2`, which is 2. So the desired grid is the
`(2 * radius + 1)` squared cells around the center: 25 cells by default. Sources: UESP
"Skyrim:INI Settings", and community Creation Kit notes that describe the same odd side length.
A negative radius becomes 0, which is only the center cell.

## Who owns the loaded set

The grid manager tracks only its center. It does not track which cells are loaded. Loads run in
the background, can finish in any order, and can fail. A manager that tracked "loaded" itself
would need confirm, cancel, and retry calls, and would drift from the truth the first time a load
failed quietly.

Instead, every frame the caller passes in its own loaded set with the camera position. The
manager moves the center if needed, computes the desired grid, and compares:

```text
loads   = desired - loaded
unloads = loaded - desired
```

A cell that failed, or is still building, is still missing from the loaded set, so it shows up
in `loads` again next frame. No separate retry path is needed.

## Hysteresis at cell borders

A camera moving back and forth over a border would change the center, and the whole grid, every
time it crossed. So a new center is accepted only once the camera is at least 128 units (about
1.8 m) past the border it crossed. This is checked per axis. A diagonal crossing needs the margin
on both axes. 128 units is small next to a 4096-unit cell, but larger than jitter. So a clear
crossing moves the center on the next frame, and noise does nothing.

## The streamer

The streamer owns the grid manager, the set of loaded cell scenes, a bookkeeping core, and a
build runner. Once per frame, the renderer calls it with the camera position. It:

1. collects finished builds;
2. updates the grid around the camera, requesting new cells and dropping cells that left;
3. adds at most one finished cell to the scene;
4. gives the new combined scene to the renderer, if anything changed.

Every build request carries a world state snapshot, taken on the main thread when the request
is made. That snapshot is the only way changeable runtime state reaches the build queue. A change
to a cell already on screen queues a rebuild. The cell stays loaded and keeps drawing its old
scene until the rebuild arrives ([runtime state](/engine/runtime-state.md)).

## One serial queue, no locks

The cell builder and the mesh and texture libraries are classes with changeable caches and no
locks inside. They are confined to one serial dispatch queue. Every build runs there, one cell
at a time. The main thread never touches them. It only receives finished cell scenes, which are
values. Creating Metal buffers and textures on that queue is safe.

A queue was chosen over an actor:

- A serial queue runs one block to the end before the next. An actor pauses at every `await`, so
  two builds could interleave there, and the "one thread, no locks" rule of the caches would have
  to be checked again at each `await`. A build is synchronous CPU work and GPU uploads, with no
  `await` inside. So a queue fits exactly.
- The build call was already synchronous and throwing. Wrapping it in `queue.async` needs no
  change to the caches.

Only the result buffers, the set of pending coordinates, and the build counts cross between
threads. The runner guards them with two locks. The counts and pending sets are `Sendable`
values in a `Mutex`, so the compiler checks them. The result buffers hold cell scenes, which
are not `Sendable`, so an `OSAllocatedUnfairLock` guards them without a compiler check. No lock
goes into the caches. The main thread collects results once per frame.

## Scheduling

The streamer keeps its own list of wanted cells, ordered from the center out, with a fixed
tie-break. It gives the runner at most one cell at a time. A new center removes stale requests
from the list before any file is read. A finished result is collected and added before the next
request goes out. So the queue stays short, unloads run before the next build, and stale work
cannot pile up behind a slow read from an external disk.

The runner also removes duplicates: a coordinate stays pending until the main thread collects
its result, not only until the build returns.

## Empty and failed cells

The bookkeeping core has four sets: resident (built), in flight (building), void (no `CELL`
record), and failed (the build threw). The grid manager's loaded set is all four together.

Because void and failed cells count as loaded, the grid never asks for them again. Empty slots
are common at the edge of a worldspace, and would otherwise be built and fail every frame.

An unload removes the coordinate from every set, so a later visit builds it fresh. A result for
a coordinate that is no longer in flight (unloaded during the build, or a late duplicate) is
dropped as stale.

## One new cell per frame

Adding a cell rebuilds the combined render scene, so at most one cell that draws is added per
frame. Void, failed, and stale results are cheap and are all collected at once. So 25 finished
cells take at most 25 frames to appear. Because requests go center-out, the start cell builds
first.

## The first camera

Until the first cell that draws arrives, the streamer keeps the start cell as its center and
ignores the renderer's placeholder camera. That first cell places the camera to frame it. Later
scene changes never move the camera.

## Assets and unload

Each cell scene lists the mesh and texture cache keys it used. A cached mesh remembers its
texture keys, so a cache hit still marks every texture the new cell uses. Collision uses the same
mesh keys ([static collision](/engine/collision-world.md)).

On unload, the cell is removed first. Then the keys it used, minus the keys any loaded cell
still uses, are evicted on the build queue. Assets shared with a neighbor survive. A build that
became stale is never shown, and its keys take the same eviction path.

A renderer scene swap prepares every allocation that can fail before it changes live state. Old
allocations stay until the GPU frames that use them finish, so a quick A, B, C change cannot free
memory B still needs.

## Script lifetime

The streamer announces when a cell joins and leaves the world, so the
[Papyrus world runtime](/engine/papyrus-world.md) can follow cells without the streamer knowing
about it. The join event has a flag that is true only when the cell really joined, and false when a
cell that never left was only rebuilt. So a rebuild does not fire load events again. A scene with no
known `CELL` identity is never announced, because subscribers file script instances by it.

## Distant LOD and coverage

Once the whole 5x5 grid is settled, the same queue builds one [distant LOD](/engine/distant-lod.md)
scene. It comes last, so its many first-load assets cannot delay near cells.

After that, moving the center starts a coverage change. The old scene stays on screen. New cells
build and wait off screen. Void and failed slots stay covered by LOD. When the matching LOD
arrives, the waiting cells and the new LOD ring go live in one swap. Another move drops waiting
cells outside the newest grid. Waiting cells keep their assets from eviction until the swap.

## Interiors

A door transition uses the same serial runner ([interiors](/engine/interiors.md)). The exterior
stays on screen while the interior builds. Once the interior is ready, the grid stops: no new
requests, no LOD, no unloads. The exterior scene is kept to return to. Leaving through a door
builds or replaces the destination cell, moves the camera to the door's `XTEL` pose, and restarts
the grid.

## Actors

Actors are part of a cell, not a separate stream. The cell build resolves and builds its `ACHR`
records on the same queue ([actor resolution](/engine/actor-resolution.md)). So actors follow the
same rules as statics: their body and head keys are cell assets, and a body shared by two loaded
cells survives when one leaves. Skeletons are kept by the mesh library outside cell assets,
because they are small and shared by everyone.

`ACHR` records in the worldspace's persistent cell are placed in streamed cells by position.

Each cell counts its actors exactly: found = drawn + disabled + failed. Every failure has a
reason. The fly benchmark fails on any count that does not add up, or any failure with no reason.

## Memory

`Data(contentsOf:options: .mappedIfSafe)` may copy a file instead of mapping it, especially on an
external disk. The Skyrim archives are about 14.6 GiB, so copying them would fill memory before
any cell loads. Archives and plugins are opened with `.alwaysMapped`. They stay read-only, and
pages load only when touched.

Streaming reports the Darwin physical footprint (`task_vm_info.phys_footprint`), not the resident
set size. Real-data tests have two guards: sampling inside the process, and `tools/memguard.sh`
outside it, which reads the same number with `/usr/bin/footprint` and kills the process if
sampling stops ([testing](/testing.md)).

Limits: 1 GiB for the fly benchmark, 3.5 GiB inside a real-data test, 4 GiB for the outside
watchdog, and a final settled footprint below 1.6 times the start.
