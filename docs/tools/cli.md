---
type: Tool
title: CLI dev tool (openskycli)
description: The openskycli command-line tool - how it shares engine code with the app, how it finds
  the data root, what each subcommand checks, and the make probe smoke run.
tags: [tool, cli, dev, probe, rendering]
---

# CLI dev tool (openskycli)

`openskycli` runs repeatable developer checks from the terminal. It runs the same engine code as the
app, so a parse failure or skip in the CLI is exactly what the renderer would do.

## Sharing code with the app

Target membership follows the folders under `Sources/`. The app builds `OpenSky/` and
`Shaders/`. The CLI builds `OpenSkyCLI/` and `Shaders/`. Both link the engine modules of the
Swift package through the `OpenSkyModules` product ([Swift modules](/tools/modules.md)). So
app-only code is invisible to the CLI with no exception lists to maintain. Metal structs come
through the `OpenSkyShaderTypes` module ([build system](/tools/build-system.md)).
`Shaders.metal` compiles into `default.metallib` next to the binary, so
`device.makeDefaultLibrary()` works without an app bundle. Build it with `make cli`.

There is no swift-argument-parser. The options are positionals and `--name value`, and a small
standard library scanner covers them, which keeps the build free of dependencies. Revisit this if
the command set outgrows it.

## Data root and load order

`--data-root <path>` takes the install root or `Data/` itself. Without it, the
[game data locator](/engine/game-data-locator.md) tries `OPENSKY_DATA_ROOT`, then the
`OpenSkyDataRoot` user default, then the Steam default path. Missing or invalid is a typed error and
exit 1. The install is read-only: commands write only where `--out` points.

The load order comes from `OPENSKY_PLUGINS_TXT`, then the `OpenSkyPluginsText` user default, then the
searched locations ([plugins.txt](/formats/plugins-txt.md)). There is no `--plugins-txt` flag,
because the environment variable already covers a one-off run.

Exit codes: 0 success, 1 failure, 2 usage error. `cell`, `screenshot`, and `render` default to the
[first render cell](/decisions/first-render-cell.md).

## Subcommands

| Command | What it checks |
| --- | --- |
| `vfs ls [pattern]` | Archive entries as `path<TAB>archive`. `fnmatch` wildcards with `FNM_NOESCAPE`, so `\` stays a separator, or a substring. Loose files are not listed, but `cat` finds them |
| `vfs cat <key> --out <file>` | Extracts one resource. Loose files win, as in the engine |
| `record <formid-or-editorid>` | One record: header, decoded view, and fields, capped at 64. Reference rows include rotation and the `XTEL` destination. An editor ID lookup scans every record |
| `plugins` | The resolved load order, where each plugin came from, and plugins listed active that `Data/` lacks |
| `gmst combat`, `gmst archery`, `gmst detection`, `gmst movement` | The settings one subsystem uses, each with the winning plugin or the documented fallback |
| `gmst list --prefix <s>` | Every resolved GMST starting with `<s>`, with its value and winning plugin. How a documented fallback is checked against the shipped number |
| `archery [--census] [--ammo <substring>]` | Each `AMMO` with a flyable `PROJ`: damage, speed, `gravity`, `range`, and the drop each reading of `gravity` predicts. `--census` shows the distribution that settles the reading ([archery](/engine/archery.md)) |
| `footstep [--set] [--armature] [--material]` | The footstep chain from set to sound file, per gait, with broken links reported ([footstep records](/formats/footstep.md), [material types](/formats/material-type.md)) |
| `cell [--worldspace/--x/--y] [--refs]` | An exterior cell without Metal: reference count and base type histogram |
| `actor [--worldspace/--x/--y] [--radius n] [--npc id]` | Placed actors in a block of cells: template chain, appearance sources, skeleton, parts, FaceGen path, and reason-tagged skips. Persistent actors are placed by position. `--npc` resolves one base record |
| `actor-values [--npc id \| --race id] [--player-level n]` | How an actor's values are derived, with the record each part came from ([actor values](/engine/actor-values.md)) |
| `collision [--worldspace/--x/--y] [--radius n]` | Collision for the center cell's models and the placed grid, with each surface's `MATT` ([collision world](/engine/collision-world.md)) |
| `interior --out <file> [--radius n]` | Finds a door near the target, goes into the interior and back, and renders the arrival pose |
| `nif <key>`, `dds <key>` | Container stats and the flattened model, or the header and mip chain |
| `hkx <key>` | Havok packfile header, sections, classes, objects, the behavior census, and the decoded node tree ([HKX container](/formats/hkx-container.md)) |
| `skeleton <hkx-key> [--nif <nif-key>]` | Every `hkaSkeleton`, and with `--nif` how the rig's bone names map onto the NIF, both ways ([hkaSkeleton](/formats/hka-skeleton.md)) |
| `animation <hkx-key>` | Decodes and samples every frame. A bad binding or a non-finite value exits 1 ([animation](/formats/hka-animation.md)) |
| `lod [--worldspace edid]` | Every LOD file of a world space through the real decoders ([distant LOD](/engine/distant-lod.md)) |
| `swf sweep` | Every `interface\*.swf`: tags, shapes, bitmaps, fonts, text, frame 1 display lists, and fontconfig aliases. LZMA movies are counted as unsupported, not failed ([SWF container](/formats/swf.md)) |
| `swf render-sweep [--size] [--movie] [--out dir]` | Renders each movie's frame 1 over a movie-free baseline and counts changed pixels ([SWF layer](/rendering/swf-layer.md)) |
| `swf action-sweep [--movie] [--limit n]` | Every movie's ActionScript: opcode counts, unknown opcodes (expect none), host API names, clip events, and structure ([SWF actions](/formats/swf-actions.md)) |
| `swf action-run [--movie] [--ticks n] [--dump] [--dump-class] [--dump-proto] [--call]` | Brings one movie up and ticks it, then prints faults, missing names, classes, callbacks, invokes, and the display tree ([GameDelegate bridge](/engine/as2-game-delegate.md)) |
| `swf inventory-menu`, `swf quest-journal`, `swf container-menu`, `swf dialogue-menu` | Drives one vanilla menu through its bridge against real records and reads the rows back out of the movie. In the CLI because the real-data test host is unreliable here |
| `swf info <key>` | One movie's header and every tag |
| `audio info <key>` | One `.xwm` or `.fuz`: its format fields and packet table. Framing only ([xWMA](/formats/xwm.md)) |
| `audio sweep` | Frames and decodes every `.xwm`, one file at a time, keeping only counts ([audio](/engine/audio.md)) |
| `audio voice-sweep [--limit n] [--names-only]` | Checks the voice file naming rule against the archive listing, and frames every `.fuz` ([FUZ](/formats/fuz.md)) |
| `screenshot --out <file> [...]` | Builds a cell, renders it offscreen, and writes a PNG. `render` is the same command |
| `bench [...]` | A sustained offscreen render with a frame time budget |
| `bench --fly-path [...]` | A scripted flight across cells through the real streamer, with memory, build, and update budgets |
| `bench --walk-path [...]` | A fixed walk from Tamriel `(6,-2)` to Chillfurrow Farm `(7,-3)`, up stairs, through an interior, and back |

## Notes on the probes

- Sweeps read one file at a time and keep only counts. An unbounded audio sweep is the kind of run
  that has run this machine out of memory.
- `audio voice-sweep` exists because the naming rule was derived from the archive listing, so
  checking it against the listing is what keeps it honest.
- `screenshot` follows the app's launch chain on a headless view. It never touches a drawable. The
  app and CLI share one PNG readback. `--neighbors` builds a 5 by 5 block and frames the cell bounds
  only. Distant LOD is hidden only in cells actually built: hiding the whole block while building one
  cell left a ring with neither terrain nor LOD. `--ui-sample` draws the UI sample and
  `--navmesh-overlay` draws navmesh triangles ([navigation](/engine/navigation.md)).
- `bench` waits for the GPU each frame, so its times are an upper bound. The default budget is
  33.33 ms, which is 30 frames per second.
- `bench --fly-path` moves one cell east, then north. The two 5 by 5 blocks overlap, so exactly 35
  unique cells must build. It fails on a missing or extra cell, a failed build, no unload, memory
  growing past 1.6 times the start or past the cap, any budget miss, an actor failure without a
  reason, or a missing living system (rain, animated bones, particles, shadow casters, or grass).
  The first cell with actors also pays for building the resolver indexes, which shows in the
  maximum, not the 95th percentile.
- `bench --walk-path` uses only observed form IDs and positions. Short sidesteps avoid small
  obstacles without clipping. Its average budget is one 30 fps frame. The 95th percentile budget is
  one frame in Release and two in Debug, for synchronous offscreen scheduling. `--budget-ms` applies
  strictly to both. Options that belong to other bench modes are usage errors.

## make probe

`tools/probe.sh` is a smoke run against the local install. Without an install it prints `[INFO]`
and exits 0, so CI is safe. It runs most commands above and checks their output, for example:

- `record 0x3C` decodes Tamriel (UESP "Skyrim Mod:FormIDs").
- `actor` finds no unresolved actors in the default block, and `actor --npc Heimskr` reports a
  skeleton, parts, and a FaceGen path.
- `hkx` on `skeleton.hkx` shows `hk_2010.2.0-r1`, the `__classnames__` and `__data__` sections, and
  an `hkaSkeleton`, and the census of `mt_behavior.hkx` finds root generator `hkbStateMachine` named
  `MT_RootBehavior`, with no unresolved members and no class without a decoder.
- `animation` samples every frame of the male `mt_idle.hkx`, and `skeleton` maps the rig onto
  `skeleton.nif` with every mismatch tagged with a reason.
- The benches pass their budgets, and `bench --fly-path` reports culled shadow casters and grass
  draws with no budget drops.
- `--walk-path` rejects `--frames`, `--footprint-cap-mb`, and `--collision-build-budget-ms` with exit
  status 2, checked before touching game data.
- `audio voice-sweep` runs with `--limit 2000`, and the report states how many it skipped.

Captures and the full `probe.log` go to `logs/probe/<UTC timestamp>/`
([run output](/tools/run-output.md)).
