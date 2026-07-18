---
type: Subsystem
title: Cell scene build
description: How one exterior cell becomes a draw list - WRLD walk, STAT resolution,
  skip taxonomy, instancing-ready grouping, world bounds, load summary.
tags: [engine, world, rendering, esm]
timestamp: 2026-07-17T00:00:00Z
---

# Cell scene build

`opensky/World/CellSceneBuilder.swift` + `CellScene.swift` (todo 2.7 scene build).
`CellSceneBuilder.buildScene(worldspaceEditorID:gridX:gridY:)` turns one exterior cell of
one plugin into a `CellScene`: an opaque-first `RenderScene`, a `CellLoadSummary`, and a
world-space AABB for camera placement. Inputs: `ESMFile` + `MeshLibrary` +
`TextureLibrary`; no hardcoded cell — target comes in as parameters (first target:
[first render cell](/decisions/first-render-cell.md)).

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

Traversal is lazy throughout: group headers only, record payloads decode on demand,
non-CELL/WRLD/REFR/STAT records are never decoded.

## STAT resolution

FormID -> `StaticObject` index built over the STAT top group on first use, cached across
builds. Raw FormIDs suffice while scene build reads a single plugin (REFR base + STAT
record share one FormID space); cross-plugin resolution via `FormIDResolver` arrives with
load-order support. MODL paths lack the `meshes\` prefix; `MeshLibrary.model(path:)`
prepends it (probe-verified — [first render cell](/decisions/first-render-cell.md)).

## Skip taxonomy (robustness rule)

Structural failures throw typed `CellSceneError` (`worldspaceNotFound`, `cellNotFound`).
Everything per-ref/per-asset logs (subsystem `nl.jjgroenendijk.opensky`, category
`CellScene`) + skips + counts — never crashes, never aborts the build (AGENTS.md
mod-quirk rule):

| bucket | trigger |
| --- | --- |
| malformed | REFR record fails to decode (missing NAME/DATA) |
| non-STAT | base FormID not in the STAT index (ACTI/TREE/... bases, or malformed STAT) |
| marker | base STAT has no MODL (editor marker) |
| load-failed | `MeshLibraryError`: file not found, parse failed, empty model |

Ignored deliberately (not refs, not counted): non-REFR records inside cell children
(NAVM, ACHR, PGRE, ... — not static placements, out of scope) and deleted REFRs (they
remove placements, nothing to draw). LAND is no longer ignored — `buildTerrain` decodes
it into ground geometry ([terrain mesh build](/engine/terrain.md)). Malformed groups under
the WRLD tree are pruned with a log, letting sibling blocks still resolve.

## Summary line

`CellLoadSummary.summaryLine`, logged once after build:

```text
[INFO] WhiterunExterior06 (6,-2): 16 refs, 15 drawn, 1 skipped (1 non-STAT),
8 models, 24 textures (0 missing)
```

Parenthetical lists only non-zero skip buckets (`non-STAT`, `marker`, `load-failed`,
`malformed`) and disappears when nothing skipped. Model/texture counts come from the
`MeshLibrary`/`TextureLibrary` counters (distinct paths).

## Grouping (instancing-ready)

Instances are sorted by (normalized mesh path, REFR FormID) before feeding
`RenderScene`, so all placements of one `RenderModel` are adjacent in the draw lists and
order is deterministic across runs. That is the precondition for switching the per-draw
loop to `drawIndexedPrimitives(instanceCount:)` later without reshuffling. `RenderScene`
itself splits opaque before alpha-tested draws (todo 2.7 opaque-first).

## App wiring (launch path)

`AppDelegate` locates game data before the window content exists, then hands
`GameViewController` a scene factory closure `(MTLDevice) -> (RenderScene, SceneCamera)?`.
The factory runs in `viewDidLoad` on the view's Metal device (GPU resources must live on
the rendering device) and chains VFS -> `ESMFile` (`Data/Skyrim.esm`) -> `TextureLibrary`
-> `MeshLibrary` -> `CellSceneBuilder.buildScene` -> `SceneCamera.framing(bounds:)` ->
`Renderer(view:scene:camera:)`. Target cell constants live in one place:
`opensky/FirstRenderCell.swift` (`Tamriel`, (6,-2) — [decision](/decisions/first-render-cell.md)).

Robustness: missing data already fail-louds via the locator alert; past that gate, any
factory failure (esm read/parse throw, build throw, nil bounds) logs `[ERROR]` and returns
nil -> renderer falls back to `DemoScene`, never crashes. The build is synchronous at
startup — acceptable for 2.7's single small cell; streaming moves it off the launch path
later.

Integration test: `CellRenderRealDataTests` (env-gated, auto-skips unless
`OPENSKY_DATA_ROOT` is set and resolves + Metal 4 present — CI has no game data) builds
the real cell, asserts the summary loosely against the decision-doc counts, renders
offscreen 1280x720 with the framing camera, asserts a non-background pixel fraction, and
writes `logs/cell-whiterunexterior06.png` (path printed in the test log).

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
