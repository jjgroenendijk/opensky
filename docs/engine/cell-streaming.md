---
type: Subsystem
title: Cell streaming
description: Camera position -> desired NxN exterior-cell grid, built off the main thread
  on one serial queue, streamed in/out around the free-fly camera with a per-frame budget.
tags: [engine, world, streaming, esm, concurrency]
timestamp: 2026-07-18T00:00:00Z
---

# Cell streaming

Todo 3.2. Two halves: a pure grid manager (`CellGridManager`) that decides which cells a
camera wants, and an async controller (`CellStreamer`) that builds them off the main
thread and streams them into the renderer. The grid manager is covered first; the
controller (concurrency model, void-cell handling, launch path) follows.

`opensky/World/CellGridManager.swift` maps a camera's world position to the set of
exterior cells that should be loaded around it, and diffs that desired set against
whatever the caller currently has resident. Pure `simd`-only value type -- no AppKit, no
Metal, no I/O, no async -- so the mapping, grid contents, diffing and hysteresis are all
unit-tested without a renderer (`openskyTests/CellGridManagerTests.swift`).

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

`CellGridManager.cellCenter(of:)` is the inverse of `cellCoordinate(for:)` up to the
half-cell offset -- the world position at a cell's center. The streamer seeds the grid on
a known launch cell (FirstRenderCell) with it so `cellCoordinate(for:)` maps straight back
to that cell.

## Streaming controller

`opensky/World/CellStreamer.swift` is the live controller. It owns the grid manager, a
`CellSceneComposition` (resident cells by coordinate), a bookkeeping core
(`CellStreamCore`), and a build runner. One main-thread entry point:

```swift
func update(cameraPosition: SIMD3<Float>)
```

driven once per frame (`Renderer.onFrame`, below). Per call it: (1) collects finished
builds, (2) re-grids around the camera -- dispatching newly-needed cells, dropping cells
that left the grid, (3) integrates at most one finished cell, (4) hands the recomposed
scene to a sink (`Renderer.setScene` in the app) when anything changed.

### Concurrency model: one serial queue, confinement not locks

`CellSceneBuilder` + `MeshLibrary` + `TextureLibrary` are non-`Sendable` classes with
mutable caches and no internal locking. They are confined to ONE serial `DispatchQueue`
(`SerialCellBuildRunner`, qos `.utility`): every `buildScene` runs there, one cell at a
time, and the main thread never touches them. Main only ever receives finished `CellScene`
*values*. GPU resource creation (MTLBuffer/MTLTexture) off that queue is safe.

Queue chosen over an actor deliberately:

- A serial queue runs one block to completion before the next -- no reentrancy. An actor
  suspends at every `await`, so two builds could interleave at suspension points; the
  "single-threaded, no locks" invariant the caches rely on would need re-checking at each
  `await`. Builds are synchronous CPU + GPU-upload work with no internal awaits, so a queue
  is the exact fit.
- The build API (`CellSceneBuilder.buildScene`) is already a synchronous throwing call;
  wrapping it in `queue.async` needs no actor refactor of the caches.

The only shared state across the boundary is a tiny completion buffer, guarded by its own
`NSLock` inside the runner. That lock is in the runner, never in the caches -- confinement
keeps the caches lock-free, as their header comments state. The main thread polls
`drainCompleted()` once per frame.

`CellSceneProvider` is the build seam (`buildCell(at:) -> CellScene`, throwing
`cellNotFound` for void slots). `BuilderCellSceneProvider` adapts `CellSceneBuilder` in the
app; unit tests inject a fake so streamer logic runs without Metal or game data.
`CellBuildRunning` abstracts the executor: `SerialCellBuildRunner` in the app, a manual
runner in tests that stages completions in any order.

### Bookkeeping core + void/failed handling (no retry storms)

`CellStreamCore` (pure value type, `openskyTests/CellStreamCoreTests.swift`) holds four
coordinate sets: `resident` (built), `inFlight` (building), `void` (no CELL record), and
`failed` (build threw). Its key output is `accountedCells = resident ∪ inFlight ∪ void ∪
failed`, fed to `CellGridManager.update` as the `loaded` set. Because void and failed
count as accounted, the grid never re-emits them in `loads` -- a void exterior slot
(`CellSceneError.cellNotFound`) or a cell whose build threw is remembered and never
re-requested every frame. This is the retry-storm guard the task demands: without it,
empty grid slots (common at worldspace edges) would rebuild-and-fail forever.

`apply(diff:)` folds one grid diff in: `loads` become `inFlight` (each requested exactly
once, since loads already exclude accounted cells); `unloads` forget the slot from *every*
set (a resident cell is dropped from the composition, everything else simply forgotten) so
a return visit rebuilds it fresh. `integrate(coordinate:kind:)` moves a finished cell out
of `inFlight` into the matching set; a coordinate no longer in `inFlight` (unloaded
mid-flight, or a duplicate late completion) returns `.discardedStale` and is dropped --
that is the out-of-order / stale-completion tolerance.

### Per-frame integration budget

A scene swap is a full recompose (`RenderScene(merging:)` + `Renderer.setScene` ring
regrow), so the controller integrates at most one *drawable* cell per frame. Void / failed
/ stale completions are cheap (no recompose) and drained freely; the first successful
integration stops the drain and the rest wait for later frames. At launch the 5x5 fills in
~25 frames (<0.5 s at 60 fps). Requests dispatch center-out (nearest to grid center first,
deterministic coordinate tie-break) so the launch cell builds first.

### Camera reseed

The renderer starts on an empty scene (clear frame). The first integrated cell that has
drawable bounds reseeds the camera via `setScene(camera: SceneCamera.framing(bounds:))`,
snapping the free-fly view onto the launch cell once it arrives. Every later recompose
passes a nil camera, so streaming never yanks the view out from under the user. A first
cell that drew nothing (no bounds) does not reseed -- the next drawable cell does.

### Unload

`unloads` drop the cell's `CellScene` from the composition (recompose reflects it);
libraries keep their caches (eviction deferred per todo -- measure memory first). A cell
still building when it leaves the grid finishes, then integrates as `.discardedStale`.

### Launch path (async)

`AppDelegate` locates game data, then builds a `CellSceneProvider` factory (VFS ->
`ESMFile` -> Texture/MeshLibrary -> `CellSceneBuilder`) -- cheap setup only, no cell built.
`GameViewController.viewDidLoad` runs the factory, starts `Renderer` on an empty scene, and
wires a `CellStreamer` centered on FirstRenderCell: the renderer's per-frame `onFrame` hook
drives `streamer.update` with the live free-fly position, and the streamer's sink calls
`Renderer.setScene`. Both captures are weak -> no retain cycle (the controller owns both).
Missing game data keeps fail-loud behavior (locator alert); a provider-setup failure past
that gate logs `[ERROR]` and leaves the renderer on the synthetic `DemoScene` so the window
is never blank forever.

`Renderer.onFrame` is an optional main-thread closure invoked in `draw(in:)` after
`advanceCamera`, passing `freeFlyCamera.position`. The streamer may call `setScene` back
synchronously inside it -- safe, since it is the same thread and still between frames (this
frame has not encoded yet), so the frame draws the freshly streamed scene. The offscreen /
test render paths never set `onFrame`, so they are unchanged.
