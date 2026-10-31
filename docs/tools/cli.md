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
The `Sources/Shaders` files compile into `default.metallib` next to the binary, so
`device.makeDefaultLibrary()` works without an app bundle. Build it with `make build-cli`.

The command line is declared with swift-argument-parser in the `OpenSkyCLIArguments` module
([decision](/decisions/swift-argument-parser.md)). `openskycli --help` and
`openskycli help <command>` print help generated from those declarations, so the help cannot
drift from the real options. Options are order-free, and an option value may start with `-`, so
`--y -2` works. `--data-root` goes before or after the command name. `game` passes every word it
does not know to the app.

## Data root and load order

`--data-root <path>` takes the install root or `Data/` itself. Without it, the
[game data locator](/engine/game-data-locator.md) tries `OPENSKY_DATA_ROOT`, then the
`OpenSkyDataRoot` user default, then the Steam default path, then every Steam library. Missing or
invalid is a typed error and exit 1. The install is read-only: commands write only where `--out` points.

The load order comes from `OPENSKY_PLUGINS_TXT`, then the `OpenSkyPluginsText` user default, then the
searched locations ([plugins.txt](/formats/plugins-txt.md)). There is no `--plugins-txt` flag,
because the environment variable already covers a one-off run.

Exit codes: 0 success, 1 failure, 2 usage error. A group without its subcommand, such as `swf`,
prints its help and exits 2. `cell` and `render` default to the
[first render cell](/decisions/first-render-cell.md).

## Conventions

`CLIConventionTests` checks the parsed command tree, and `make cli-conventions`
(`tools/lint/cli-conventions.sh`) checks the source. Both run in `make check` and CI.

- Names are lowercase kebab case: `asset-optimisation`, `--player-level`. Options are spelled
  out; there are no short options.
- Each command has one name. There are no aliases and no old names kept for scripts.
- A group, such as `record`, only holds subcommands. A mode is a subcommand, never a
  positional word: `record show 0x3C`, `record find --type WEAP`. `show` reads one item.
- A choice is an enum, so the help lists the values and a bad value exits 2:
  `--preset quick|standard|full`. A number is `Int`, `Int32`, `Float`, or `Double`, and its
  range is checked in `validate()`, before any game data loads.
- A list is one comma-separated value: `--scenes a,b`. A switch is a flag, `--x` or `--no-x`,
  never `--x on`.
- Every command and argument has help that is a sentence. Every option takes
  `parsing: .unconditional`, so a value may start with `-`.
- Every leaf command has a runner in `CommandRunners.swift`, a row below, and a run in
  `tools/probe.sh` or `tools/probe-swf.sh`. A command the probe cannot run, because it
  writes settings or opens the app, has a reason in `tools/lint/cli-probe-exceptions.txt`.

`make new-cli-command NAME=<name> GROUP=<help group>` writes the stubs for a new top-level
command: the arguments struct, the runner, the command file, a row in this page, and a probe
run. Each stub says TODO, and `make cli-conventions` fails until none is left.

## Searching records

`record find --type <TYPE>` walks every winning record of one type through its decoder. Each
`--where` filter must match:

| Filter | Matches |
| --- | --- |
| `field=value`, `field!=value` | Some value equals, or no value equals, ignoring case |
| `field~text`, `field!~text` | Some value contains, or no value contains, the text |
| `field<n`, `field<=n`, `field>n`, `field>=n` | Some value compares as a number |
| `field` | The field has a value |

A field is a path through the decoded record, such as `data.damage`. The last parts are enough:
`damage` matches `data.damage`. Every element of a list shares the list's path, so
`keywords=WeapTypeDagger` matches a weapon with that keyword anywhere in its list. A FormID reads
as the target's editor ID. Every type also has `formID`, `plugin`, and `subrecords` (one per
subrecord signature), so an undecoded type can still be searched by its fields.

```sh
openskycli record find --type WEAP --where keywords=WeapTypeDagger --where 'damage>=10' \
  --fields editorID,damage
openskycli record find --type LAND --where subrecords=VTEX --count
```

Output is one tab-separated line per record, `formID` then each `--fields` path (default
`editorID`). `--json` prints one object per record with every field, and `--count` prints only
the number. A summary line goes to stderr.

## Subcommands

`openskycli --help` groups the commands the same way.

### Game data

| Command | What it checks |
| --- | --- |
| `install` | The game folder check the launcher shows: game version, official DLC, Creation Club plugin count, archive, plugin, and record counts, and each install problem with its fix. Exits 1 on a problem |
| `plugins` | The resolved load order, where each plugin came from, and plugins listed active that `Data/` lacks |
| `record show <id>` | One record by FormID or editor ID: header, decoded view, and fields, capped at 64. Reference rows include rotation and the `XTEL` destination. An editor ID lookup scans every record |
| `record find --type <TYPE> [--where <filter>]... [--fields a,b] [--limit n] [--count] [--json]` | Every winning record of one type that matches the filters ([searching records](#searching-records)) |
| `gmst combat`, `gmst archery`, `gmst detection`, `gmst movement` | The settings one subsystem uses, each with the winning plugin or the documented fallback |
| `gmst list [<prefix>]` | Every resolved GMST starting with `<prefix>`, with its value and winning plugin, and the text of a string setting from that plugin's string table. How a documented fallback is checked against the shipped number |
| `ess show <save.ess> [--offline]` | A Skyrim save, read-only: header, plugins, sections, global data, change form histograms, the Papyrus table, and the import report against the current load order. `--offline` skips the load order ([ESS import](/engine/ess-import.md)) |
| `ess list <folder>` | Each save's header in a folder |
| `gaps [--only a,b] [--limit n] [--summary-out path]` | What the install's data uses that the engine does not do yet, per area: how much is done, and what is left ranked by use; `--summary-out` also writes the summary as a Markdown table ([gap report](/tools/gaps.md)) |

### World

| Command | What it checks |
| --- | --- |
| `cell [--worldspace/--x/--y] [--cell <editorID>] [--refs]` | An exterior cell of any worldspace, or an interior cell by editor ID, without Metal, merged over every active plugin: the winning plugin, reference count, and base type histogram. `--refs` lists each reference with its base editor ID and position |
| `actor appearance [--worldspace/--x/--y] [--radius n] [--npc id]` | Placed actors in a block of cells: template chain, appearance sources, skeleton, parts, FaceGen path, and reason-tagged skips. Persistent actors are placed by position. `--npc` resolves one base record |
| `actor values --npc <id>` or `--race <id>` `[--player-level n]` | How an actor's values are derived, with the record each part came from ([actor values](/engine/actor-values.md)) |
| `collision [--worldspace/--x/--y] [--radius n]` | Collision for the center cell's models and the placed grid, with each surface's `MATT` ([collision world](/engine/collision-world.md)) |
| `interior --out <file> [--radius n]` | Finds a door near the target, goes into the interior and back, and renders the arrival pose |
| `lod [--worldspace edid]` | Every LOD file of a world space through the real decoders ([distant LOD](/engine/distant-lod.md)) |

### Game rules

| Command | What it checks |
| --- | --- |
| `archery [--census] [--ammo <text>]` | Each `AMMO` with a flyable `PROJ`: damage, speed, `gravity`, `range`, and the drop each reading of `gravity` predicts. `--census` shows the distribution that settles the reading ([archery](/engine/archery.md)) |
| `footstep [--set] [--armature] [--material]` | The footstep chain from set to sound file, per gait, with broken links reported ([footstep records](/formats/footstep.md), [material types](/formats/material-type.md)) |
| `effects census` | The effect records the runtimes read: `IMAD` timing, `IMGS` grading ranges, `SPGD` precipitation, `SOPM` output models, `REVB` reverbs, and explosions ([image space](/rendering/image-space.md)) |
| `effects imad <edid> [--at seconds]` | Samples one image-space modifier at one time |

### Assets

| Command | What it checks |
| --- | --- |
| `vfs ls [pattern] [--containing <text>]` | Archive entries as `path<TAB>archive`. `fnmatch` wildcards with `FNM_NOESCAPE`, so `\` stays a separator, or a substring. `--containing` keeps the entries whose bytes hold the text, such as a NIF block type name. Loose files are not listed, but `cat` finds them |
| `vfs cat <path> --out <file>` | Extracts one resource. Loose files win, as in the engine |
| `nif <path> [--sequences] [--controllers]` | Container stats, each node with its local translation, the flattened model, and any furniture markers. `--sequences` adds every node's full transform, each effect shape's material, and each controller sequence with its tracks ([sequences](/formats/nif-sequences.md)). `--controllers` adds each node controller that plays on its own clock, and the bone LOD bones and levels ([controllers](/formats/nif-controllers.md#node-controller-rules)) |
| `dds <path>` | The header and mip chain |
| `hkx <path>` | Havok packfile header, sections, classes, objects, the behavior census, and the decoded node tree ([HKX container](/formats/hkx-container.md)). `--blenders` lists each blender instead: flags, bound blend parameter, and each child's place and generator. On an actor graph, `--raise <event>`, repeated, steps it and prints the active states after each event, with `--set name=value` holding a variable ([dragon flight](/engine/dragon-flight.md#the-behavior-graph)) |
| `hkt show <path>`, `hkt sweep` | One Havok binary tagfile, or every archived `.hkt`: class versions, objects, cloth classes, and skeleton bones ([HKT tagfile](/formats/hkt-tagfile.md)) |
| `skeleton <path> [--nif <nif-path>] [--all]` | Every `hkaSkeleton` with its first 12 bones, or every bone with `--all`, and with `--nif` how the rig's bone names map onto the NIF, both ways ([hkaSkeleton](/formats/hka-skeleton.md)) |
| `animation <path>` | Decodes and samples every frame. A bad binding or a non-finite value exits 1 ([animation](/formats/hka-animation.md)) |
| `audio show <path>` | One `.xwm` or `.fuz`: its format fields and packet table. Framing only ([xWMA](/formats/xwm.md)) |
| `audio sweep` | Frames and decodes every `.xwm`, one file at a time, keeping only counts ([audio](/engine/audio.md)) |
| `audio voice-sweep [--limit n] [--names-only]` | Checks the voice file naming rule against the archive listing, and frames every `.fuz` ([FUZ](/formats/fuz.md)) |
| `audio aac-check [--per-category n] [--out file]` | Encodes a fixed sample of each cached sound category as AAC and prints the AAC or ALAC verdict ([asset cache](/engine/asset-cache.md)) |
| `swf show <path>` | One movie's header and every tag |
| `swf sweep` | Every `interface\*.swf`: tags, shapes, bitmaps, fonts, text, frame 1 display lists, and fontconfig aliases. LZMA movies are counted as unsupported, not failed ([SWF container](/formats/swf.md)) |
| `swf render-sweep [--size WxH] [--movie text] [--out dir]` | Renders each movie's frame 1 over a movie-free baseline and counts changed pixels ([SWF layer](/rendering/swf-layer.md)) |
| `swf action-sweep [--movie text] [--limit n]` | Every movie's ActionScript: opcode counts, unknown opcodes (expect none), host API names, clip events, and structure ([SWF actions](/formats/swf-actions.md)) |
| `swf action-list --movie <text>` | One movie's action records with names resolved |
| `swf action-run [--movie text] [--ticks n] [--dump] [--dump-class] [--dump-proto] [--call]` | Brings one movie up and ticks it, then prints faults, missing names, classes, callbacks, invokes, and the display tree ([GameDelegate bridge](/engine/as2-game-delegate.md)) |
| `swf movie-probe --movie <path> [--ticks] [--capture] [--then] [--dump]` | Starts any movie and runs steps split by `;`: `call:<path>:<method>[:<JSON args>]` calls a node method, an empty path calls a GameDelegate callback, `key:<code>` sends a key, and `gamepads:<n>` reports gamepads. Prints the host calls, the dumped nodes, and the focus at the end. Used to measure the race menu movie ([race menu](/engine/race-menu.md)) |
| `menu inventory`, `menu quest-journal`, `menu container`, `menu dialogue` | Drives one vanilla menu through its bridge against real records and reads the rows back out of the movie. In the CLI because the real-data test host is unreliable here |
| `menu system [--state] [--focus] [--row] [--ticks] [--dump]` | Opens `quest_journal.swf` on its System page, starts one page state, optionally accepts a row, and prints every GameDelegate call, the faults, and the missing names. Help and Installed Content answer with two sample topics. `--dump` also prints a node's sprite frames and display children ([system menu](/engine/system-menu.md)) |

### Rendering

| Command | What it checks |
| --- | --- |
| `render --out <file> [...]` | Builds a cell, renders it offscreen, and writes a PNG. Use it for a cell or effect check; `preview` frames one record, and `game screenshot` captures the running app |
| `preview --record\|--ref\|--mesh\|--cell <id> [--stage studio\|cell] [--angles all] [...]` | One record, placed reference, mesh, or cell rendered offscreen from fixed angles, with a PNG and a JSON report per view. A blank view exits 1 ([preview render](/tools/preview-render.md)) |

### The app

| Command | What it checks |
| --- | --- |
| `game <command> [...]` | Not a probe: drives the running app over its agent control socket. `game help` lists the app's commands and `game <command> --help` shows one. `game launch`, `game attach`, and `game run` start or join a session ([agent control](/tools/agent-control.md)) |
| `benchmark [--preset quick\|standard\|full] [--scenes a,b] [--set id=value,...] [--no-overlay] [--screenshots] [--windowed] [--capture <id>] [--out <dir>] [--list] [...]` | Opens the app and flies the benchmark tour full screen, then prints the summary. Exits 1 when a scene fails ([benchmark](/tools/benchmark.md)) |
| `graphics status`, `graphics preset low\|medium\|high\|ultra` | The Graphics page without the app. `status` prints the preset that matches the settings, or Custom, and each base game option with its value or why it is unavailable. `preset` writes the values of the game's `Low.ini` to `Ultra.ini` into the player settings file ([graphics options](/engine/graphics-options.md)) |
| `asset-optimisation build`, `asset-optimisation check`, `asset-optimisation clear`, `asset-optimisation status` `[--texture-quality original\|high\|medium\|low] [--max-texture-side n] [--folder] [--kinds a,b] [--width n] [--paths <file>]` | Asset optimisation without the app. `build` converts every source the folder does not hold yet and prints the space check first, `check` counts current, stale, and missing entries per kind, `clear` empties the folder, and `status` prints the folder, size, texture quality, and location warnings. The texture quality and folder come from the app settings unless an option overrides them. `--paths` limits a build or check to the files listed one per line ([asset cache](/engine/asset-cache.md)) |
| `asset-optimisation extract --paths <file> --out <dir>` | Writes loose copies of the listed files, outside the repo and the install, to time loose files apart from the archives |
| `asset-optimisation io-bench --paths <file>` | Loads the listed textures that have a cache entry as one batch, four ways: the archive path, the cache read on the CPU, and Metal fast resource loading from the raw entries and from LZ4 copies. Each runs cold, after a page cache eviction, then warm. Prints wall and process CPU time ([asset cache](/engine/asset-cache.md)) |
| `asset-optimisation measure [--per-kind n]` | Per asset kind, builds the entries of up to `n` archive files (default 300) and loads them from the archives and from the cache, cold and warm. Prints wall and CPU time per kind and an `advice` line, `cache` or `archives`; the [asset cache](/engine/asset-cache.md) page explains how the result decides which kinds the cache stores |
| `asset-optimisation compare <reference.png> <candidate.png>` | The PSNR and the largest channel error between two captures of the same view, such as two renders with the cache off and on. 100 dB means identical |
| `reference status` | The reference game prefix and what it still lacks, and the Wine that runs it ([reference game](/tools/reference-game.md)) |
| `reference check` | Compares the Steam build and the SHA-256 of every `.esm` of the reference copy and the OpenSky install. Exits 1 on a difference |
| `reference launch [--width n] [--height n] [--steam-wait s] [--preset low\|medium\|high\|ultra]` | Sets the window size and the game's own graphics preset, Low by default, in the prefix's `SkyrimPrefs.ini`, then starts Windows Steam and the game |
| `reference export-view [--no-hide-menus] [--freeze]` | Writes the running OpenSky view as the batch file `bat opensky` runs in the reference game |
| `reference capture [--width n] [--height n]` | Captures both games at one size and writes the pair, their difference, the batch file, and a report to `.logs/reference/<UTC time>/` |
| `reference state` | The Windows game's state as the bridge plugin reports it: place, angles, hour, weather, and field of view |
| `reference send <command>...` | Runs console commands in the Windows game through the bridge plugin, without typed keys |
| `reference sync [--no-hide-menus] [--freeze]` | Puts the Windows game at the running OpenSky's view through the bridge plugin |
| `reference follow` | Puts the running OpenSky at the Windows game's view, through `debug.view` |
| `reference answer <button>` | Presses a button of the message box open in the Windows game, by index or text |
| `reference load [<save>]` | Waits for the Windows game's main menu, then loads the save, by default the newest |

## Notes on the probes

- A record that fails to decode prints a `[WARNING]` line to stderr, with its type and error.
  Stdout keeps only the lines `make probe` greps.
- Sweeps read one file at a time and keep only counts. An unbounded audio sweep is the kind of run
  that has run this machine out of memory.
- `audio voice-sweep` exists because the naming rule was derived from the archive listing, so
  checking it against the listing is what keeps it honest.
- `render` follows the app's launch chain on a headless view. It never touches a drawable. The
  app and CLI share one PNG readback. `--neighbors` builds a 5 by 5 block and frames the cell bounds
  only. Distant LOD is hidden only in cells actually built: hiding the whole block while building one
  cell left a ring with neither terrain nor LOD. `--ui-sample` draws the UI sample and
  `--navmesh-overlay` draws navmesh triangles ([navigation](/engine/navigation.md)).
- `render` effect flags make the image-space and effect A/B captures.
  `--image-space-off` skips the composite pass, and `--tone-mapping-off` skips only its
  [HDR tone mapping](/rendering/image-space.md). `--imgs` forces a baseline, and `--imad` starts
  a modifier sampled at `--imad-at` seconds. `--membrane` puts an `EFSH` membrane on the first
  actor and frames it. `--frame-actor` frames that actor with no effect, for a skin or face
  check. `--shading-off` turns [surface shading](/rendering/surface-shading.md) terms off, by
  name (`normalMaps,specular`) or `all`, for a with and without pair. `--weather` forces a
  weather, so its `SPGD` rain falls. Rain needs a few frames to fill the volume, so add
  `--frames 60`.
- The streaming, walk, and sustained frame time gates are real-data tests:
  `FlyPathGateRealDataTests`, `WalkPathGateRealDataTests`, and `SustainedRenderGateRealDataTests`.
  `make test-real PERF=1` runs them ([benchmark](/tools/benchmark.md)).

## make probe

`tools/probe.sh` is a smoke run against the local install. Without an install it prints `[INFO]`
and exits 0, so CI is safe. It runs most commands above and checks their output, for example:

- `record show 0x3C` decodes Tamriel (UESP "Skyrim Mod:FormIDs"), and `record find` finds it
  by editor ID and counts the daggers by keyword.
- `actor appearance` finds no unresolved actors in the default block, and
  `actor appearance --npc Heimskr` reports a
  skeleton, parts, and a FaceGen path.
- `hkx` on `skeleton.hkx` shows `hk_2010.2.0-r1`, the `__classnames__` and `__data__` sections, and
  an `hkaSkeleton`, and the census of `mt_behavior.hkx` finds root generator `hkbStateMachine` named
  `MT_RootBehavior`, with no unresolved members and no class without a decoder.
- `animation` samples every frame of the male `mt_idle.hkx`, and `skeleton` maps the rig onto
  `skeleton.nif` with every mismatch tagged with a reason.
- `benchmark --list` prints the tour's scenes, and `benchmark` rejects an unknown preset or
  setting with exit status 2, before it opens the app.
- `asset-optimisation build --kinds collision` of 20 clutter meshes into a temporary folder
  reports no failures, and `check` then counts every entry as current.
- `audio voice-sweep` runs with `--limit 2000`, and the report states how many it skipped.
- `audio aac-check --per-category 5` prints a verdict for the effects category.
- `game status` against an unused socket path exits 1 with `notRunning`. `game dance` and a
  misspelled option exit 2, and `game help` prints the command list. All run without the app.

Captures and the full `probe.log` go to `.logs/probe/<UTC timestamp>/`
([run output](/tools/run-output.md)).
