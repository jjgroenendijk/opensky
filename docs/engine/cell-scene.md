---
type: Subsystem
title: Cell scene build
description: How one exterior cell becomes a draw list - WRLD walk, base resolution,
  skip taxonomy, instancing-ready grouping, world bounds, load summary.
tags: [engine, world, rendering, esm]
timestamp: 2026-07-18T00:00:00Z
---

# Cell scene build

`opensky/World/CellSceneBuilder.swift` + `CellScene.swift` (todo 2.7 scene build).
`CellSceneBuilder.buildScene(worldspaceEditorID:gridX:gridY:)` turns one exterior cell of
one plugin into a `CellScene`: an opaque-first `RenderScene`, a `CellLoadSummary`, and a
world-space AABB for camera placement. Inputs: `ESMFile` + `MeshLibrary` +
`TextureLibrary`; no hardcoded cell — target comes in as parameters (first target:
[first render cell](/decisions/first-render-cell.md)).

M3.5 extends output with exterior sky + water: WRLD DATA controls sky presence; CELL
XCLW/XCWT resolve against WRLD/parent defaults into one flat water plane. Full rules:
[sky + water environment](/engine/sky-water.md).

M3.6 adds CELL top-group interior build + DOOR/XTEL transitions. Full flow:
[interior door transitions](/engine/interiors.md).

## Walk order

Group nesting per UESP "Skyrim Mod:Mod File Format" — Groups:

1. WRLD top group -> WRLD record with matching EDID (exact match; malformed WRLD ->
   log + skip) -> the world-children group (type 1) labeled with that record's FormID.
2. Depth-first through exterior block (type 4) / sub-block (type 5) groups. Block grid
   labels are never trusted for lookup (unreliable in CK-ignored groups — see
   `ESMGroup`); match is the decoded CELL XCLC grid only. Cost: every exterior CELL
   record in the worldspace decodes once per build — acceptable at startup, label-hint
   pruning is a future optimization.
3. Matching CELL -> the cell-children group (type 6) that follows it among the same
   siblings, labeled with the cell FormID. Missing children group = cell with zero refs,
   not an error.
4. Inside: persistent (type 8) + temporary (type 9) children groups both traversed ->
   REFR records.

WRLD persistent teleport doors are special: storage CELL `(0,0)` does not own their
physical placement. Cached XTEL refs merge into scene selected by REFR position ->
4096-unit grid coordinate. See [interior door transitions](/engine/interiors.md).

Traversal is lazy throughout: group headers only, record payloads decode on demand,
non-CELL/WRLD/REFR/STAT/MSTT/TREE/FURN/ACTI/CONT/DOOR records are never decoded.

## Base resolution

Milestone 3.2 "widen base coverage": a ref's base FormID is resolved against two lazy,
cached indices, STAT first, then `ModelBase` (MSTT/TREE/FURN/ACTI/CONT/DOOR —
[record decoders](/formats/records.md)):

* FormID -> `StaticObject` over the single STAT top group.
* FormID -> `ModelBase` over six top groups, one per record type (unlike STAT there is
  no single shared group for these).

Both cached across builds on first use. Raw FormIDs suffice while scene build reads a
single plugin (REFR base + base-record FormID share one FormID space); cross-plugin
resolution via `FormIDResolver` arrives with load-order support. MODL paths lack the
`meshes\` prefix; `MeshLibrary.model(path:)` prepends it (probe-verified — [first render
cell](/decisions/first-render-cell.md)). Animation/interaction fields on the four new
types (FURN markers, CONT inventory, ACTI activation, TREE billboard) are unread — model
path only, matching the STAT-only precedent.

## Skip taxonomy (robustness rule)

Structural failures throw typed `CellSceneError` (`worldspaceNotFound`, `cellNotFound`).
Everything per-ref/per-asset logs (subsystem `nl.jjgroenendijk.opensky`, category
`CellScene`) + skips + counts — never crashes, never aborts the build (AGENTS.md
mod-quirk rule):

| bucket | trigger |
| --- | --- |
| malformed | REFR record fails to decode (missing NAME/DATA) |
| unsupported-base | base FormID in neither STAT nor ModelBase index (NPC_, ACHR, IDLM, MISC, FLOR, SOUN, ... bases, or malformed base record) |
| marker | resolved base has no MODL (editor marker) |
| load-failed | `MeshLibraryError`: file not found, parse failed, empty model |

Ignored deliberately (not refs, not counted): non-REFR records inside cell children
(NAVM, PGRE, ... — not static placements, out of scope) and deleted REFRs (they
remove placements, nothing to draw). ACHR left this list in 5.5: placed actors run a
parallel collect/resolve/assemble pass with its own exact accounting
(`discovered = rendered + disabled + failed` — [actor records](/formats/actors.md)).
LAND is no longer ignored — `buildTerrain` decodes
it into ground geometry ([terrain mesh build](/engine/terrain.md)). Malformed groups under
the WRLD tree are pruned with a log, letting sibling blocks still resolve.

## Summary line

`CellLoadSummary.summaryLine`, logged once after build:

```text
[INFO] WhiterunExterior06 (6,-2): 16 refs, 16 drawn, 0 skipped,
9 models, 19 textures (0 missing), 4 terrain quads (14 splat layers)
```

Water cells append `, water`; `waterPlaneCount` is 0/1. Sky is intentionally absent from
summary count because it is worldspace environment state, not cell geometry.

Parenthetical lists only non-zero skip buckets (`unsupported-base`, `marker`,
`load-failed`, `malformed`) and disappears when nothing skipped. Model/texture counts
come from the `MeshLibrary`/`TextureLibrary` counters (distinct paths).

Actor-bearing cells append `, N actors (D drawn, S disabled, F failed)` (zero buckets
omitted) — the greppable per-cell form of the 5.5 exact-accounting rule
`N == D + S + F` (`CellLoadSummary.actorAccountingIsExact`).

## Grouping (instancing-ready)

Instances are sorted by (normalized mesh path, REFR FormID) before feeding
`RenderScene`, so all placements of one `RenderModel` are adjacent in the draw lists and
order is deterministic across runs. That is the precondition for switching the per-draw
loop to `drawIndexedPrimitives(instanceCount:)` later without reshuffling. `RenderScene`
itself splits opaque before alpha-tested draws (todo 2.7 opaque-first).

## App wiring (launch path)

Launch is async as of 3.2 -- no cell is built on the launch path. `AppDelegate` locates
game data before the window content exists, then hands `GameViewController` a *provider*
factory `(MTLDevice) -> (any CellSceneProvider)?`. The factory runs in `viewDidLoad` on the
view's Metal device (GPU resources must live on the rendering device) and chains VFS ->
`ESMFile` (`Data/Skyrim.esm`) -> `TextureLibrary` -> `MeshLibrary` -> `CellSceneBuilder`,
wrapped in `BuilderCellSceneProvider` -- cheap setup only (ESM is memory-mapped, top-group
headers only). The renderer starts on an empty scene; a `CellStreamer` centered on
`FirstRenderCell` builds cells off the main thread and streams them in, framing the camera
on the first arrival ([cell streaming](/engine/cell-streaming.md)). Target cell constants
live in one place: `opensky/FirstRenderCell.swift` (`Tamriel`, (6,-2) —
[decision](/decisions/first-render-cell.md)).

Robustness: missing data already fail-louds via the locator alert; past that gate, a
provider-setup failure (esm read/parse throw) logs `[ERROR]` and returns nil -> no
streamer, renderer falls back to `DemoScene`, never crashes. Per-cell build failures during
streaming are recorded (void / failed) and never retried, so a broken slot never storms.

The `openskycli` `render` / `bench` subcommands still call `CellSceneBuilder.buildScene`
directly (synchronous, single-threaded) -- they are one-shot offscreen tools, not the live
streaming loop, so they bypass the streamer entirely.

Integration test: `CellRenderRealDataTests` (env-gated, auto-skips unless
`OPENSKY_DATA_ROOT` is set and resolves + Metal 4 present — CI has no game data) builds
the real cell, asserts the summary loosely (drawn ref count is a floor, not exact —
widening base coverage in 3.2 raised WhiterunExterior06 from 15/16 to 16/16 drawn),
renders offscreen 1280x720 with the framing camera, asserts a non-background pixel
fraction, and writes `logs/cell-whiterunexterior06.png` (path printed in the test log).

## Transform + bounds

Per instance: `MatrixMath.placement(position:rotation:scale:)` over REFR DATA + XSCL
(sign/order rationale: [coordinates](/decisions/coordinates.md)). `MeshLibrary` captures
a model-space AABB (`ModelBounds`) at parse time — union of each mesh's vertex AABB
pushed through its mesh->model transform — because vertex data lives only on the GPU
after upload. Scene build transforms the 8 corners per instance and unions into
`CellScene.bounds` (nil when nothing drew); downstream camera placement frames that box.
The terrain model ([terrain mesh build](/engine/terrain.md)) is built in-engine, so its
AABB comes straight from the CPU-side `Model`; it unions into `CellScene.bounds` and its
opaque `DrawItem`s append after the object instances.
Water plane bounds union the exact cell square at resolved height. Sky is fullscreen and
does not alter bounds.
