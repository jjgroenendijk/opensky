---
type: Tool
title: CLI dev tool (openskycli)
description: Terminal dev entrypoints over engine data, collision, rendering, and probes.
tags: [tool, cli, dev, probe, rendering]
timestamp: 2026-07-21T00:00:00Z
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
| `actor [--worldspace <edid>] [--x n] [--y n] [--radius n] [--npc <formid-or-edid>]` | list ACHR placed actors in the (2r+1)^2 cell block (persistent-cell ACHRs mapped in by position); per actor: base NPC_+ editor ID, placement, TPLT chain with chosen LVLN entries, source NPC_ of every appearance field, then visuals — skeleton path, `part` lines (origin ARMO, ARMA, biped slots, gendered model path), FaceGen mesh path, reason-tagged skips; summary counts discovered/resolved/failed/deleted/malformed (visual failures count as failed); `--npc` resolves one base NPC_ directly (named residents live in interior cells), exit 1 on failure; default radius 1 |
| `collision [--worldspace <edid>] [--x n] [--y n] [--radius n]` | center-cell unique-model bhk sweep + production placed collision grid; per cell shapes/tris/build ms/KiB, void cells, aggregate filters/failures; fail acceptance gaps |
| `interior --out <file> [--worldspace/--x/--y] [--radius n]` | scan exterior doors near target for exterior -> interior -> paired exterior round trip, render exact XTEL arrival pose to PNG; default radius 16 |
| `nif <key>` | container stats + named node/shape rows + flattened model summary (meshes, verts/tris, bounds, materials with texture paths) |
| `dds <key>` | header + mip chain (size, BCn format, sRGB declaration) |
| `hkx <key>` | Havok packfile container: header (version string, fileVersion, pointer size, section count, resolved root class), section table (name, data start/size, local/global/virtual fixup counts), class-name table (signature hex + name), object inventory (total, per-class histogram, first 8 offset/class rows + truncation count); unresolved root class warns on stderr |
| `skeleton <hkx-key> [--nif <nif-key>]` | decode every hkaSkeleton in a Havok packfile: per object name, bone count, root count, first 12 bones with parent index; `--nif` name-maps the rig (most bones) onto the NIF skeleton NiNode names — `M of N matched` plus one reason-tagged `unmatched hkx bone`/`unmatched nif node` line per mismatch, both directions |
| `animation <hkx-key>` | decode every hkaSplineCompressedAnimation + matching hkaAnimationBinding, sample every stored frame as bone-indexed local transforms, report frame/track/block/mapping counts + max translation/scale + normalized-quaternion range; malformed/unbound/non-finite/unbounded sample exits 1 |
| `lod [--worldspace edid]` | parse lodsettings + sweep every worldspace BTR/BTO and tree LST/BTT through production decoders; any failed container/type reference exits 1 |
| `screenshot --out <file> [--worldspace/--x/--y] [--size WxH] [--zoom f] [--time-of-day 0-24] [--neighbors] [--ui-sample]` | cell scene build + distant LOD -> framing camera -> `Renderer.renderOffscreen` -> PNG; prints load/LOD/draw stats + non-background fraction; `--zoom` (0.1-10) moves eye toward framed center; `--time-of-day` controls procedural sky (default 13); `--neighbors` builds production-size 5x5 (shared libraries) and frames full-cell bounds only; missing cell warns + skips; `--ui-sample` sets `uiScene = .labSample` ([screen-space UI](/rendering/ui.md)) and prints its quad/glyph/dropped/atlas stats; `render` is identical alias |
| `bench [--worldspace/--x/--y] [--size WxH] [--frames n] [--budget-ms f]` | sustained offscreen render (default 360 frames @ 1280x720) through `Renderer.renderOffscreenSustained` — FrameStats windows + per-frame wall and animation-update times; prints avg/p95/max + fps, exit 1 when avg or p95 misses the budget (default 33.33 ms = 30 fps, todo 2.11 gate) |
| `bench --fly-path [--worldspace/--x/--y] [--size WxH] [--budget-ms f] [--max-frames n] [--footprint-cap-mb f] [--collision-build-budget-ms f] [--actor-build-budget-ms f] [--animation-budget-ms f] [--shadow-budget-ms f]` | scripted launch-center -> east -> north cell flight through live `CellStreamer`; requires physical-footprint plateau/cap, exact 35-cell build union, zero failed builds, collision-build p95 (default 750 ms), actor-build p95 (default 4500 ms; includes cold rig/clip decode), exact/reason-tagged actor + animation accounting, animation-update avg/p95 (default 4 ms), shadow-update avg/p95 (default 14 ms), selected rainy weather, updated actor bones, live world particles + rain, shadow casters, drawn grass with zero hard-budget drops, and frame avg/p95 budget; prints living-system peaks, build/update budgets, per-cell accounting, shadow culling + grass instancing |
| `bench --walk-path [--size WxH] [--budget-ms f] [--max-frames n] [--out file]` | fixed M4 production walk from Tamriel `(6,-2)` to Chillfurrow Farm `(7,-3)`, stair ascent, interior floor crossing + paired exterior return; gates timeout, grounding/penetration, destination/build errors, active-physics avg/p95; optional final PNG |

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
  [main-app asset browser](/tools/preview-gui.md) since 2.10). Decoded REFR rows include
  placement rotation + XTEL destination pose, used to establish fixed clean-engine routes.
* `cell` mirrors the [cell scene build](/engine/cell-scene.md) WRLD walk read-only
  (XCLC grid match, labels ignored) and resolves base types via a headers-only
  FormID -> record-type index.
* `actor` is M5.1/5.2's repeatable probe. Decode + resolution live in the engine tree
  (`ActorTemplateResolver.build` indexes NPC_/LVLN top groups;
  `ActorVisualResolver.build` indexes RACE/ARMO/ARMA/OTFT/LVLI; see
  [actor records](/formats/actors.md)); the CLI mirrors `cell`'s WRLD walk over the
  radius block plus the worldspace (0,0) persistent cell, assigning persistent ACHRs
  to cells by physical position (door pattern). `--npc` skips the walk and resolves
  the named base NPC_ alone.
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
  The LOD pass hides only cells actually built: hiding the whole 5x5 while building one
  cell (no `--neighbors`) left a 24-cell ring with neither terrain nor LOD — sky showed
  through the gap around the target cell.
* `lod` is repeatable clean-room probe. It validates all LOD-specific NIF blocks, flattens
  each file without GPU upload, parses tree LST/BTT, and resolves every type reference.
  Vanilla Tamriel: 3,060 BTR + 717 BTO + 329 BTT/40,839 refs, 0 failed. Screenshot/render
  load the same [INI precedence](/formats/ini.md) as main app.
* `hkx` is M6.1's container probe. It parses the Havok packfile via shared `HKXFile`
  (header + section table + class-name table + fixup-derived object inventory) and only
  prints; object internals stay later milestones (needs class reflection). CLI parses/
  prints only; a bad magic/layout/section index exits 1. See
  [HKX container](/formats/hkx-container.md).
* `skeleton` is M6.2's hkaSkeleton probe. It decodes bones/parents/reference pose via
  shared `HKASkeleton.skeletons(in:)` and, with `--nif`, name-maps the rig onto
  `NIFSkeleton.boneTransforms` via `SkeletonBoneMap`. CLI parses/prints only; a decode
  failure (typed `HKASkeletonError`) or unreadable key exits 1. Only the largest
  skeleton (the rig) is mapped — the ragdoll is physics, not the mesh bind skeleton.
  See [hkaSkeleton](/formats/hka-skeleton.md).
* `animation` is M6.3's idle-track probe. Shared
  `HKASplineCompressedAnimation.animations(in:)` decodes Havok 2010 spline blocks;
  `HKAAnimationBinding.bindings(in:)` resolves each track to a skeleton bone (empty map =
  identity); `boneLocalTransforms(at:binding:)` samples all transforms. CLI evaluates every
  stored frame, so missing binding, typed metadata/block/quantization/spline errors, or
  non-finite/unbounded transforms exit 1. See
  [hkaSplineCompressedAnimation](/formats/hka-animation.md).
* `bench --fly-path` uses shared `CellStreamingFlyBenchmark` engine logic, not a CLI-only
  model. It drives production serial build runner, streamer, renderer scene swaps, asset
  eviction, and `task_vm_info.phys_footprint` sampler. Waypoints move one cell east, then
  north; overlapping 5x5 grids require exactly 35 unique builds. Repeated count,
  missing/unexpected coordinate, failed cell, no unload, >1.6x final/start footprint, cap,
  timeout, collision-build p95 budget miss, actor-build p95 budget miss, per-cell actor
  accounting mismatch, a counted actor failure without a reason (5.6
  zero-unexplained rule), animation- or shadow-update avg/p95 budget miss, missing rainy
  weather/animated bones/world particles/rain/shadow casters/rendered grass, grass
  hard-budget drops, or
  avg/p95 frame budget miss exits 1. Per-cell
  metrics come from `SerialCellBuildRunner`; collision time covers base resolution, decoded
  model cache, transform placement + BVH build; actor time covers ACHR collection,
  template/visual resolution + GPU assembly (first actor-bearing cell also pays the
  one-time resolver index build — shows up in max, not p95).
* `bench --walk-path` uses shared `CellStreamingWalkBenchmark` engine logic. Route constants
  are observed FormIDs/positions only; no asset bytes. It drives production renderer,
  fixed-step `WalkController`, streamed terrain/static collision, serial scene builds + door
  transitions. Bounded sidesteps avoid small placed obstacles without clipping/teleporting.
  Any timeout, fall-through, unresolved penetration, wrong door/CELL/return pose, failed
  cell/door build, <16-unit stair gain, short interior crossing, or active-physics avg/p95
  over budget exits 1.

## Probe harness (make probe)

`tools/probe.sh` (POSIX sh): env-gated smoke run against the local install —
default `/Volumes/data/steam/steamapps/common/Skyrim Special Edition`, override via
`OPENSKY_DATA_ROOT`. Install absent -> `[INFO]` + exit 0 (CI safe). Checks: `vfs ls`
finds meshes; `record 0x3C` decodes Tamriel (UESP "Skyrim Mod:FormIDs"); `cell`
summary; `actor` requires zero unresolved ACHR template+visual chains in the default
3x3 block, then `actor --npc Heimskr` must report skeleton, parts + FaceGen path;
`collision --radius 2` gates placed 5x5 collision; `nif`/`dds` inspect first listed
assets; `hkx` dumps the container inventory for `skeleton.hkx` (must show
`hk_2010.2.0-r1`, `__classnames__`/`__data__` sections, an `hkaSkeleton` class) and a
human idle `.hkx` (must show `hkaSplineCompressedAnimation`); `animation` decodes
male `mt_idle.hkx` + samples all 275 frames x 99 tracks over full duration (M6.3 gate:
99-sample identity bone mapping, finite + bounded); `skeleton` decodes the
human rig `skeleton.hkx` name-mapped onto `skeleton.nif` (M6.2 gate: rig reports 99
bones, name-map 93 of 99 matched, every mismatch line reason-tagged); `screenshot` writes
a local ignored render capture; `interior` verifies one door round trip + local render,
and its summary line must report at least one drawn + animated actor; `bench` runs the
sustained fps gate (360 frames @
720p, fails over 33.33 ms avg/p95); `bench --fly-path` runs the M3.2 cross-cell gate at
640x360, including the 750 ms collision-build p95 gate + M5.5/5.6 actor gates (actor-build
p95, exact actor/animation accounting, reason-tagged failures, 4 ms animation-update
  avg/p95, 14 ms shadow-update avg/p95), M7.6 living-system peaks (selected weather,
  animated bones, world particles, rain, shadow casters, grass); probe additionally requires the aggregate
  accounting lines plus one per-cell line for each of the 35 touched cells, echoing
  explained failures, asserts the `shadow culling` line reports culled casters, and
  requires nonzero `grass instancing` draws with zero budget drops);
`bench --walk-path` runs M4's 640x360
physics/route gate + writes `logs/probe-walk-path.png`. Full output -> `logs/probe.log`.
