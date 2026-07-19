---
type: Tool
title: CLI dev tool (openskycli)
description: Terminal dev entrypoints over engine data, collision, rendering, and probes.
tags: [tool, cli, dev, probe, rendering]
timestamp: 2026-07-18T00:00:00Z
---

# CLI dev tool (openskycli)

Second product target (todo 2.9): repeatable dev checks from the terminal, replacing
throwaway probe scripts. Runs the same engine code the app runs — a parse failure or
skip in the CLI reproduces the renderer's behavior exactly.

## Target sharing

`openskycli` is a macOS command-line tool target in `opensky.xcodeproj`. It lists the
`opensky/` `PBXFileSystemSynchronizedRootGroup` in its `fileSystemSynchronizedGroups`
with a `PBXFileSystemSynchronizedBuildFileExceptionSet` excluding app-only files
(`OpenSkyApp.swift`, `AppDelegate.swift`, `GameViewController.swift`,
`Assets.xcassets`) -> one source tree, no framework split, no duplication. CLI entry
code lives in `openskycli/` (own synchronized root group). Bridging header pinned to
`opensky/ShaderTypes.h`; `Shaders.metal` compiles into `default.metallib` next to the
tool binary, so `device.makeDefaultLibrary()` works without an app bundle. Shared
scheme `openskycli`; build via `make cli`.

Dependency decision: no swift-argument-parser. Option surface is small (positionals +
`--name value`), a ~60-line stdlib scanner (`ArgumentScanner`) covers it, build stays
hermetic (AGENTS.md: prefer stdlib when it suffices). Revisit when the command set
outgrows it.

## Data root

`--data-root <path>` (install root or `Data/` itself) or the
[game data locator](/engine/game-data-locator.md) chain: `OPENSKY_DATA_ROOT` env var ->
`OpenSkyDataRoot` user default -> Steam default path. Missing/invalid -> locator's
typed error, exit 1. Install is read-only external input; `vfs cat`/`screenshot` write
only where `--out` points (AGENTS.md Legal & IP).

## Subcommands

| command | does |
| --- | --- |
| `vfs ls [pattern]` | list archive entries as `path<TAB>archive`; fnmatch wildcards (`FNM_NOESCAPE` — `\` stays a separator) or substring match; count on stderr |
| `vfs cat <key> --out <file>` | extract one resource (loose files win, as in the engine) |
| `record <formid-or-editorid>` | dump one Skyrim.esm record: header, decoded view (WRLD/CELL/STAT/REFR), field list capped at 64 with a per-type tail summary |
| `cell [--worldspace <edid>] [--x n] [--y n] [--refs]` | exterior-cell summary without Metal: ref count, base-type histogram, other cell records; `--refs` lists placements |
| `collision [--worldspace <edid>] [--x n] [--y n] [--radius n]` | center-cell unique-model bhk sweep + production placed collision grid; per cell shapes/tris/build ms/KiB, void cells, aggregate filters/failures; fail acceptance gaps |
| `interior --out <file> [--worldspace/--x/--y] [--radius n]` | scan exterior doors near target for exterior -> interior -> paired exterior round trip, render exact XTEL arrival pose to PNG; default radius 16 |
| `nif <key>` | container stats + named node/shape rows + flattened model summary (meshes, verts/tris, bounds, materials with texture paths) |
| `dds <key>` | header + mip chain (size, BCn format, sRGB declaration) |
| `lod [--worldspace edid]` | parse lodsettings + sweep every worldspace BTR/BTO through LOD block decoders + scene flattener; any failed container exits 1 |
| `screenshot --out <file> [--worldspace/--x/--y] [--size WxH] [--zoom f] [--time-of-day 0-24] [--neighbors]` | cell scene build + distant LOD -> framing camera -> `Renderer.renderOffscreen` -> PNG; prints load/LOD/draw stats + non-background fraction; `--zoom` (0.1-10) moves eye toward framed center; `--time-of-day` controls procedural sky (default 13); `--neighbors` builds production-size 5x5 (shared libraries) and frames full-cell bounds only; missing cell warns + skips; `render` is identical alias |
| `bench [--worldspace/--x/--y] [--size WxH] [--frames n] [--budget-ms f]` | sustained offscreen render (default 360 frames @ 1280x720) through `Renderer.renderOffscreenSustained` — FrameStats windows + per-frame wall times; prints avg/p95/max + fps, exit 1 when avg or p95 misses the budget (default 33.33 ms = 30 fps, todo 2.11 gate) |
| `bench --fly-path [--worldspace/--x/--y] [--size WxH] [--budget-ms f] [--max-frames n] [--footprint-cap-mb f] [--collision-build-budget-ms f]` | scripted launch-center -> east -> north cell flight through live `CellStreamer`; requires physical-footprint plateau/cap, exact 35-cell build union, zero failed builds, collision-build p95 (default 500 ms), avg/p95 frame budget |

`cell`/`screenshot`/`render` default to the first-render cell
([decision](/decisions/first-render-cell.md), constants in
`opensky/FirstRenderCell.swift`). Exit codes: 0 ok, 1 failure, 2 usage.

Implementation notes:

* `vfs ls` uses `VirtualFileSystem.archiveEntries()` (engine addition): every archive
  entry path attributed to the winning archive, sorted. Loose files not enumerated —
  walking all of `Data/` is not worth it for a lookup layer; `cat` still resolves them.
* Editor-ID lookup scans EDID fields of every record (whole-file decompression):
  ~6 s worst case on Skyrim.esm, fine for a dev tool.
* `record` prints the shared `RecordTextDump` string; walk helpers live in
  `opensky/Formats/ESM/ESMWalk.swift` (shared with the
  [main-app asset browser](/tools/preview-gui.md) since 2.10).
* `cell` mirrors the [cell scene build](/engine/cell-scene.md) WRLD walk read-only
  (XCLC grid match, labels ignored) and resolves base types via a headers-only
  FormID -> record-type index.
* `collision` uses shared `ExteriorCellModelCatalog` + `NIFCollisionSweep` for center-asset
  diagnostics, then `CellCollisionGridProbe` + production `CellSceneBuilder` placement for
  radius grid. CLI only parses/prints. Any empty root, unknown reachable block, decode/load
  failure exits 1. See [NIF collision](/formats/nif-collision.md) +
  [collision world](/engine/collision-world.md).
* `interior` is M3.6 repeatable acceptance probe. It uses production builder transition
  resolution for both directions; destination must be interior, reverse destination must
  equal source exterior door. One WRLD walk gathers doors without loading assets;
  `--radius` bounds selection to 0-64 cells.
* `screenshot` follows the app launch chain (VFS -> ESM -> libraries ->
  `CellSceneBuilder` -> `SceneCamera.framing`) on a headless `MTKView`; the offscreen
  path never touches a drawable. `render` dispatches the same implementation as a
  compatibility alias. App + CLI both use shared `FrameScreenshot` BGRA readback/PNG
  encoder; no separate screenshot pipeline. `--time-of-day` feeds the same renderer field
  as live frames; 24 normalizes to midnight.
* `screenshot --neighbors` composes 25 `CellScene` builds + one distant LOD scene with
  `RenderScene(merging:)` (a
  flat concat of each scene's opaque/alpha-tested/terrain draw lists — draw items
  already carry absolute world matrices, so no re-transform) and unions the 9 bounds
  boxes before framing. LOD bounds stay excluded so distant mountains do not shrink target.
* `lod` is M3.4 repeatable clean-room probe. It validates all LOD-specific NIF blocks +
  flattens each file without GPU upload. Vanilla Tamriel: 3,060 BTR + 717 BTO, 0 failed.
* `bench --fly-path` uses shared `CellStreamingFlyBenchmark` engine logic, not a CLI-only
  model. It drives production serial build runner, streamer, renderer scene swaps, asset
  eviction, and `task_vm_info.phys_footprint` sampler. Waypoints move one cell east, then
  north; overlapping 5x5 grids require exactly 35 unique builds. Repeated count,
  missing/unexpected coordinate, failed cell, no unload, >1.6x final/start footprint, cap,
  timeout, collision-build p95 budget miss, or avg/p95 frame budget miss exits 1. Per-cell
  metrics come from `SerialCellBuildRunner`; collision time covers base resolution, decoded
  model cache, transform placement + BVH build.

## Probe harness (make probe)

`tools/probe.sh` (POSIX sh): env-gated smoke run against the local install —
default `/Volumes/data/steam/steamapps/common/Skyrim Special Edition`, override via
`OPENSKY_DATA_ROOT`. Install absent -> `[INFO]` + exit 0 (CI safe). Checks: `vfs ls`
finds meshes; `record 0x3C` decodes Tamriel (UESP "Skyrim Mod:FormIDs"); `cell`
summary; `collision --radius 2` gates placed 5x5 collision; `nif`/`dds` inspect first listed
assets; `screenshot` writes
`logs/probe-screenshot.png`; `interior` verifies one door round trip + writes
`logs/probe-interior.png`; `bench` runs the sustained fps gate (360 frames @
720p, fails over 33.33 ms avg/p95); `bench --fly-path` runs the M3.2 cross-cell gate at
640x360, including 500 ms collision-build p95 gate. Full output -> `logs/probe.log`.
