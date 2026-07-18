---
type: Tool
title: CLI dev tool (openskycli)
description: Terminal dev entrypoints over the engine - VFS list/extract, record and cell
  probes, NIF/DDS inspection, offscreen cell render to PNG, env-gated probe harness.
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
typed error, exit 1. Install is read-only external input; `vfs cat`/`render` write only
where `--out` points (AGENTS.md Legal & IP).

## Subcommands

| command | does |
| --- | --- |
| `vfs ls [pattern]` | list archive entries as `path<TAB>archive`; fnmatch wildcards (`FNM_NOESCAPE` — `\` stays a separator) or substring match; count on stderr |
| `vfs cat <key> --out <file>` | extract one resource (loose files win, as in the engine) |
| `record <formid-or-editorid>` | dump one Skyrim.esm record: header, decoded view (WRLD/CELL/STAT/REFR), field list capped at 64 with a per-type tail summary |
| `cell [--worldspace <edid>] [--x n] [--y n] [--refs]` | exterior-cell summary without Metal: ref count, base-type histogram, other cell records; `--refs` lists placements |
| `nif <key>` | container stats + flattened model summary (meshes, verts/tris, bounds, materials with texture paths) |
| `dds <key>` | header + mip chain (size, BCn format, sRGB declaration) |
| `render --out <file> [--worldspace/--x/--y] [--size WxH] [--zoom f] [--neighbors]` | cell scene build -> framing camera -> `Renderer.renderOffscreen` -> PNG; prints load summary + non-background pixel fraction; `--zoom` (0.1-10) moves the eye toward the framed center — whole-cell framing is conservative, sparse cells render small without it; `--neighbors` builds the target cell plus its 8 grid neighbors (one shared `MeshLibrary`/`TextureLibrary`/`CellSceneBuilder`, so residency dedups across cells) and renders one frame framed to the union of all built bounds — a missing or malformed neighbor slot warns to stderr and is skipped, not fatal |
| `bench [--worldspace/--x/--y] [--size WxH] [--frames n] [--budget-ms f]` | sustained offscreen render (default 360 frames @ 1280x720) through `Renderer.renderOffscreenSustained` — FrameStats windows + per-frame wall times; prints avg/p95/max + fps, exit 1 when avg or p95 misses the budget (default 33.33 ms = 30 fps, todo 2.11 gate) |

`cell`/`render` default to the first-render cell
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
  [preview GUI](/tools/preview-gui.md) since 2.10).
* `cell` mirrors the [cell scene build](/engine/cell-scene.md) WRLD walk read-only
  (XCLC grid match, labels ignored) and resolves base types via a headers-only
  FormID -> record-type index.
* `render` follows the app launch chain (VFS -> ESM -> libraries ->
  `CellSceneBuilder` -> `SceneCamera.framing`) on a headless `MTKView`; the offscreen
  path never touches a drawable.
* `render --neighbors` composes 9 `CellScene` builds with `RenderScene(merging:)` (a
  flat concat of each scene's opaque/alpha-tested/terrain draw lists — draw items
  already carry absolute world matrices, so no re-transform) and unions the 9 bounds
  boxes before framing. Dumb composition on purpose: this is the 3.1 verify render, not
  the 3.2 streaming grid manager.

## Probe harness (make probe)

`tools/probe.sh` (POSIX sh): env-gated smoke run against the local install —
default `/Volumes/data/steam/steamapps/common/Skyrim Special Edition`, override via
`OPENSKY_DATA_ROOT`. Install absent -> `[INFO]` + exit 0 (CI safe). Checks: `vfs ls`
finds meshes; `record 0x3C` decodes Tamriel (UESP "Skyrim Mod:FormIDs"); `cell`
summary; `nif`/`dds` inspect the first listed assets; `render` writes
`logs/probe-render.png`; `bench` runs the sustained fps gate (360 frames @
720p, fails over 33.33 ms avg/p95) and echoes the measured line. Full
output -> `logs/probe.log`.
