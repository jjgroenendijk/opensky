---
type: Subsystem
title: Cell streaming grid manager
description: Camera position -> desired NxN exterior-cell grid, diffed against the
  caller's loaded set; hysteresis against border thrash. Pure math, no async yet.
tags: [engine, world, streaming, esm]
timestamp: 2026-07-18T00:00:00Z
---

# Cell streaming grid manager

Todo 3.2 (grid manager sub-item only). `opensky/World/CellGridManager.swift` maps a
camera's world position to the set of exterior cells that should be loaded around it, and
diffs that desired set against whatever the caller currently has resident. Pure
`simd`-only value type -- no AppKit, no Metal, no I/O, no async -- so the mapping, grid
contents, diffing and hysteresis are all unit-tested without a renderer
(`openskyTests/CellGridManagerTests.swift`).

The async build/streaming controller that actually drives cells through load/unload off
the main queue is a separate sub-item of 3.2 and lands in a later commit on this branch
(`docs/todo.md`). This document covers the grid manager only; it will grow a "streaming
controller" section once that piece exists.

## Types

- `CellCoordinate` -- `{x: Int32, y: Int32}`, `Hashable`. The pure streaming-side grid
  coordinate. Distinct from `Cell.Grid` (the decoded XCLC record field, which also carries
  the force-hide-land-quad flags and belongs to one parsed plugin) -- `CellCoordinate` has
  no tie to any plugin. `CellSceneBuilder.buildScene(worldspaceEditorID:gridX:gridY:)`
  still takes raw `Int32` grid axes; convert at the call site
  (`coordinate.x`/`coordinate.y`).
- `CellGridDiff` -- `{loads: Set<CellCoordinate>, unloads: Set<CellCoordinate>}`. Both
  sets empty never surfaces as a value -- `CellGridManager.update` returns nil instead.
- `CellGridManager` -- the manager itself: a `radius` (rings around center) and a
  `center` (`CellCoordinate`, hysteresis-gated, see below).

## Cell coordinate mapping

One exterior cell = 4096 world units, cell `(x, y)` covers world X in
`[x*4096, (x+1)*4096)`, same for Y (`docs/decisions/coordinates.md`). `CellCoordinate` is
computed by floor division on `position.x / 4096` and `position.y / 4096`
(`Float.rounded(.down)`, not truncation) -- a camera at X=-1 must land in cell -1, not
cell 0. Truncation-toward-zero would put every negative-but-near-zero position in cell 0,
silently wrong for the whole negative-X/Y quadrant of the worldspace. `cellCoordinate(for:)`
reuses `TerrainMeshBuilder.cellSize` for the 4096 constant instead of redefining it.

## Desired grid + radius

`uGridsToLoad` (Skyrim ini, Grid section) is documented as the full grid side length,
always odd -- default 5. `CellGridManager.defaultRadius = 2` is the ring count
(`(uGridsToLoad - 1) / 2`) so `desiredCells` returns the `(2*radius+1)^2` square of cells
centered on `center` -- 25 cells at the default radius. Refs: UESP "Skyrim:INI Settings"
Grid section; community SKSE/Creation Kit docs describe the same odd-side,
center-plus-N-rings convention. `radius` is a manager-construction parameter, not
hardcoded -- negative values clamp to 0 (just the center cell) rather than crashing on a
malformed range.

`desiredCells` returns a `Set`, unordered -- load priority/ordering (e.g. nearest cells
first) is the streaming controller's concern, not this type's.

## Ownership split: who holds the loaded set

`CellGridManager` tracks only its own desired *center* cell. It does **not** track which
cells are actually loaded -- that set stays entirely with the caller.

Why: the caller's loads are async (3.2's other sub-item, off the main queue) and can
finish out of order or fail outright. If the manager tried to track "loaded" state
itself, it would need a confirm/cancel/retry API and would drift from reality the moment
a load failed silently or raced with an unload. Instead:

```swift
mutating func update(
    cameraPosition: SIMD3<Float>,
    loaded: Set<CellCoordinate>
) -> CellGridDiff?
```

Every frame, the caller passes its own source of truth (whatever it currently has
resident) alongside the camera position. The manager recenters (subject to hysteresis,
below), computes the desired grid, and diffs it fresh against `loaded`:
`loads = desired.subtracting(loaded)`, `unloads = loaded.subtracting(desired)`. Returns
nil when there is nothing to do -- center held, or center moved but `loaded` already
matches the new desired grid exactly.

Consequence: a cell that failed to load, or is still mid-flight when the frame's `loaded`
snapshot is taken, simply reappears in `loads` on the very next `update` call, because it
is still absent from `loaded`. No separate retry path needed -- the diff is always
correct for whatever state the caller reports, by construction. The streaming controller
(later commit) owns the actual load/unload dictionary and async work; this type never
touches it.

## Hysteresis against border thrash

A camera oscillating across a cell border (patrol path, mouse jitter, float noise at the
boundary) would otherwise flip `center` -- and therefore the whole desired grid -- every
time floor division crosses the line, thrashing load/unload every frame near any border.

`CellGridManager.hysteresisMargin = 128` world units (~1.8 m,
`docs/decisions/coordinates.md` scale). `recenterIfNeeded` only accepts a new candidate
center once the camera has penetrated at least `hysteresisMargin` past whichever border
it crossed -- checked per axis, so a diagonal corner crossing needs clearance on both X
and Y before the diagonal neighbor becomes the new center. An axis that did not change
cell needs no clearance on that axis. 128 units is small next to the 4096-unit cell
(irrelevant to which cell is genuinely "current" for streaming purposes) but comfortably
larger than positional jitter, so a border crossed once decisively still recenters on the
very next `update` call -- no lag for genuine movement, no thrash for noise.

`openskyTests/CellGridManagerTests.swift` covers this directly: walking back and forth
within the margin on either side of a border never changes `center` or emits a diff;
crossing decisively past the margin recenters immediately; a diagonal crossing needs both
axes past margin.
