---
type: Tool
title: CLI dev tool (openskycli)
description: Terminal dev entrypoints over engine data, collision, rendering, and probes.
tags: [tool, cli, dev, probe, rendering]
timestamp: 2026-07-28T00:00:00Z
---

# CLI dev tool (openskycli)

Second product target (todo 2.9): repeatable dev checks from the terminal, replacing
throwaway probe scripts. Runs the same engine code the app runs — a parse failure or
skip in the CLI reproduces the renderer's behavior exactly.

## Target sharing

`openskycli` is a macOS command-line tool target in `opensky.xcodeproj`. Target
membership follows the folder split under `opensky/` (issue #336): the app target
synchronizes `App/`, `Engine/`, and `SharedHeaders/`, while `openskycli` synchronizes
`Engine/`, `SharedHeaders/`, and `openskycli/`. App-only code (`OpenSkyApp.swift`,
`AppDelegate.swift`, `GameViewController.swift`, `Assets.xcassets`, the whole shell and
panel framework) lives under `opensky/App/` and is therefore invisible to the CLI, with
no `PBXFileSystemSynchronizedBuildFileExceptionSet` to hand-maintain -> one source tree,
no framework split, no duplication. CLI entry
code lives in `openskycli/` (own synchronized root group). The structs shared with Metal
arrive through the `OpenSkyShaderTypes` clang module rather than a bridging header, so the
CLI no longer borrows the app target's, and any file that needs them says so with an
`import` — see [Build system](/tools/build-system.md).
`Shaders.metal` compiles into `default.metallib` next to the
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

The plugin load order is resolved the same way, from `OPENSKY_PLUGINS_TXT` ->
`OpenSkyPluginsText` user default -> the searched layouts
([plugins.txt](/formats/plugins-txt.md)). There is no `--plugins-txt` flag: the env var
already covers a one-off run, and every command that reads plugins picks it up.

## Subcommands

| command | does |
| --- | --- |
| `vfs ls [pattern]` | list archive entries as `path<TAB>archive`; fnmatch wildcards (`FNM_NOESCAPE` — `\` stays a separator) or substring match; count on stderr |
| `vfs cat <key> --out <file>` | extract one resource (loose files win, as in the engine) |
| `record <formid-or-editorid>` | dump one Skyrim.esm record: header, decoded view (WRLD/CELL/STAT/REFR, with every REFR pose rendered as an `(x, y, z)` tuple), field list capped at 64 with a per-type tail summary |
| `plugins` | print the resolved [plugin load order](/formats/plugins-txt.md): the `plugins.txt` the search found and where, then one row per active plugin — position, name, and whether it came from the pinned masters, `Skyrim.ccc`, or `plugins.txt` — plus any plugin listed active that `Data/` does not hold. `OPENSKY_PLUGINS_TXT` overrides the search, which is how a load order is checked on a machine where the game has never been launched |
| `gmst combat` | resolve melee combat's GMSTs across the active plugins; print `fCombatDistance` and the six block-formula settings with the winning plugin or the documented fallback ([melee combat](/engine/melee-combat.md)) |
| `gmst archery` | resolve archery's three GMSTs across the active plugins; print the two arrow tilt-up angles and `fVisibleNavmeshMoveDist` with the winning plugin or the UESP-documented fallback ([archery and projectiles](/engine/archery.md)) |
| `archery [--census] [--ammo <substring>]` | walk the ammunition chain a shot takes: the archery GMSTs, the PROJ record count, then one row per AMMO that names a flyable PROJ with its damage, launch speed, `gravity`, `range`, and the drop each reading of `gravity` predicts at 1,000 units. `--census` adds the per-type `gravity`/`speed` distribution that settles which reading is right; `--ammo` filters by editor-ID substring ([archery and projectiles](/engine/archery.md)) |
| `gmst detection` | resolve perception's GMSTs across the active plugins; print the ten `fSneak*` settings and the thirteen OpenSky constants beside them, each with the winning plugin or the source string that says the number is ours ([perception and detection](/engine/detection.md)) |
| `gmst list --prefix <s>` | print every resolved GMST whose editor ID starts with `<s>`, with its value and winning plugin. The provenance probe behind every settings table in the wiki: reading a family off the install is how a documented fallback is checked against the number the shipped game carries |
| `gmst movement` | resolve the player's movement tuning across official, Creation Club, and starred active plugins; print walk, run, sprint, sneak, swim, step-height, and jump-takeoff values with units and the winning plugin, MOVT record, or fallback source |
| `footstep [--set <editorID>] [--armature <formid-or-edid>] [--material <edid-or-formid>]` | walk the footstep chain read-only: record counts (`FSTS`/`FSTP`/`IPDS`/`IPCT`/`ARMA` with `SNDD`), the `MATT` count and how many of them a collision mesh can reach by hash, the set chosen, the surface material, then per gait every `FSTP` in that gait's list as `tag: footstep -> impact -> sound file`, with unresolvable links reported rather than skipped; defaults to `DefaultFootstepSet`, `--set` names another by editor ID, `--armature` reads the set off an `ARMA`'s `SNDD` the way an actor's boots do, and `--material` names the surface under the foot by editor ID, Creation Kit material name, or FormID, which is what selects the impact ([footstep records](/formats/footstep.md), [material types](/formats/material-type.md)) |
| `cell [--worldspace <edid>] [--x n] [--y n] [--refs]` | exterior-cell summary without Metal: ref count, base-type histogram, other cell records; `--refs` lists placements |
| `actor [--worldspace <edid>] [--x n] [--y n] [--radius n] [--npc <formid-or-edid>]` | list ACHR placed actors in the (2r+1)^2 cell block (persistent-cell ACHRs mapped in by position); per actor: base NPC_+ editor ID, placement, TPLT chain with chosen LVLN entries, source NPC_ of every appearance field, then visuals — skeleton path, `part` lines (origin ARMO, ARMA, biped slots, gendered model path), FaceGen mesh path, reason-tagged skips; summary counts discovered/resolved/failed/deleted/malformed (visual failures count as failed); `--npc` resolves one base NPC_ directly (named residents live in interior cells), exit 1 on failure; default radius 1 |
| `actor-values [--npc <formid-or-edid>] [--race <formid-or-edid>] [--player-level n]` | read-only derivation report. `--npc` walks the template chain and prints the resolved race, class, level and auto-calc flag, the ACBS offsets with the record each came from, the class attribute weights, the race's starting attributes, the derived maximums, the editor's baked DNAM triple for comparison, and the regen rates. Both forms then print the non-primary actor values the records author, by index and vanilla name — the eighteen skills, speed multiplier, carry weight, unarmed damage and mass (issue #468). `--race` prints one RACE's starting attributes, regen rates, carry weight, mass and unarmed damage instead; exactly one of the two is required. `--player-level` scales PC-level-mult actors, defaulting to 1. Both forms print the resolved `iAVDhmsLevelUp`, `fNPCHealthLevelBonus` and `iAVDSkillsLevelUp` first ([actor values](/engine/actor-values.md)) |
| `collision [--worldspace <edid>] [--x n] [--y n] [--radius n]` | center-cell unique-model bhk sweep + production placed collision grid; per model a `materials:` line naming each surface's `MATT` (issue #358; a Havok value no `MATT` hashes to prints raw), per cell shapes/tris/build ms/KiB, void cells, aggregate filters/failures; fail acceptance gaps |
| `interior --out <file> [--worldspace/--x/--y] [--radius n]` | scan exterior doors near target for exterior -> interior -> paired exterior round trip, render exact XTEL arrival pose to PNG; default radius 16 |
| `nif <key>` | container stats + named node/shape rows + flattened model summary (meshes, verts/tris, bounds, materials with texture paths) |
| `dds <key>` | header + mip chain (size, BCn format, sRGB declaration) |
| `hkx <key>` | Havok packfile container: header (version string, fileVersion, pointer size, section count, resolved root class), section table (name, data start/size, local/global/virtual fixup counts), class-name table (signature hex + name), object inventory (total, per-class histogram, first 8 offset/class rows + truncation count); then the behavior census — file role, root-container variant classes, behavior graph name + root generator class, and the variable (with declared type), event, character-property, content-path and referenced behavior/character/animation inventories, each as a total plus the first 12 names, ending with any unresolved members and their reason; then the node decode — every registered object decoded through the class registry as a per-class histogram, any class with no decoder or object that failed to decode, and the node tree below the root generator as an indented `class "name" — summary` listing (first 40 nodes, depth 4), each summary naming that class's own fields (state counts, clip animation paths, blend weights, transition durations); unresolved root class and misread members warn on stderr |
| `skeleton <hkx-key> [--nif <nif-key>]` | decode every hkaSkeleton in a Havok packfile: per object name, bone count, root count, first 12 bones with parent index; `--nif` name-maps the rig (most bones) onto the NIF skeleton NiNode names — `M of N matched` plus one reason-tagged `unmatched hkx bone`/`unmatched nif node` line per mismatch, both directions |
| `animation <hkx-key>` | decode every hkaSplineCompressedAnimation + matching hkaAnimationBinding, sample every stored frame as bone-indexed local transforms, report frame/track/block/mapping counts + max translation/scale + normalized-quaternion range; malformed/unbound/non-finite/unbounded sample exits 1 |
| `lod [--worldspace edid]` | parse lodsettings + sweep every worldspace BTR/BTO and tree LST/BTT through production decoders; any failed container/type reference exits 1 |
| `swf sweep` | parse every `interface\*.swf` movie through `SWFFile`; per-file header line (version, compression, frame size, frame count, tag count) plus final tallies: files parsed/unsupported (ZWS)/failed, total tags, known vs. unknown tag-code counts, shapes decoded + tessellated (`swf sweep shapes:` — per-tag counts, triangle total, failures), bitmaps decoded (`swf sweep bitmaps:` — per-source-format counts, failures), fonts decoded (`swf sweep fonts:` — glyphs, layout, kerning, CGPaths built, failures), static text (`swf sweep text:` — DefineText/2/EditText counts, failures), frame-1 display lists (`swf sweep display:` — movies, placements, background colors; `swf sweep display tags:` — place/move/remove/ShowFrame/sprite/clip counts; `swf sweep display draws:` — flattened shape/text draws, clip ranges, fully transparent draws; `swf sweep display deferred:` — filters, blend modes, ClipActions; `swf sweep display text:` — glyphs laid out, unresolved fonts), and fontconfig alias resolution (`swf sweep fontconfig:` — fontlibs, aliases resolved/unresolved); ZWS (LZMA) movies count as accounted-but-unsupported, not a failure; a malformed/truncated file or any shape/bitmap/font/text/display-list decode failure exits 1 |
| `swf render-sweep [--size WxH] [--movie substring] [--out dir]` | assign every `interface\*.swf` movie in turn to the production `Renderer` and render its frame-1 display list offscreen over a movie-free baseline; per-movie line with draw/triangle/glyph/mask/skipped counts and changed-pixel count, then `swf render-sweep:` (movies, rendered, unchanged frames, failed) and `swf render-sweep draws:` totals; `--movie` filters by path substring (a fresh renderer per run gives honest per-movie glyph counts), `--out` writes one PNG per movie — point it at `logs/`, the frames embed game art; any decode or render error exits 1 |
| `swf action-sweep [--movie substring] [--limit n]` | decode every movie's action side (main-timeline + sprite DoAction, CLIPACTIONS, DoInitAction) through `SWFActionInventory`; per-movie line (blocks, records, distinct opcodes, unknown, undecoded, warnings), then `swf action-sweep opcodes:` (every observed opcode descending by count, `0x<hex> <name-or-unknown> <count> <movies>`), `swf action-sweep unknown:` (opcodes absent from `SWFActionName`, expect 0), `swf action-sweep hostapi:` (member/method names structurally resolved from the immediately preceding `ActionPush`, capped by `--limit`, default 120), `swf action-sweep clipevents:` (per-`SWFClipEventFlags` handler usage, fixed bit order), `swf action-sweep structure:` (DefineFunction/2, register/With/Try/ConstantPool counts, largest block), and `swf action-sweep ranking:` (top 20 movies by action-record count); `--movie` filters by path substring; any decode failure exits 1, and reported unknown opcodes fail the probe gate even though the command itself does not exit non-zero for them |
| `swf action-run [--movie substring] [--ticks n] [--limit n] [--tree-depth n] [--dump paths] [--dump-class names] [--dump-proto paths] [--call names]` | bring one movie up through `SWFMovieRuntime` (every `DoInitAction`, frame 1 with class instantiation, the frame `DoAction`), tick it `--ticks` times (default 10), and print what came out: a summary line (ticks, display nodes, faults, unimplemented opcodes, distinct missing names and total hits), `swf action-run faults:` by fault kind, `swf action-run placements:` (total placements, character ids the movie's own dictionary does not hold, imported-name count) with each import URL and its assets, `swf action-run import merge:` (`SWFImportMergeDiagnostics.summary` plus each merged path), `swf action-run missing:` (the ranked missing-API tally, capped by `--limit`, default 40), `swf action-run classes:` (registered linkage names), `swf action-run callbacks:` (`GameDelegate` names the movie registered), `swf action-run invokes:` (totals plus every unhandled call), and `swf action-run tree:` (the display tree by instance path with each clip's frame and labels, to `--tree-depth`, default 4); `--dump` takes a comma-separated list of display paths and prints each node's own AS2 properties, `--dump-class` takes registered linkage names and prints each class's constructor and prototype members — the method surface a page class publishes, which no node dump reaches — `--dump-proto` takes display paths and walks each node's whole prototype chain level by level, which is how a list widget's contract is read off the base class the movie never registers, `--call` invokes comma-separated movie callbacks before ticking; `--movie` must match exactly one movie. This is the per-menu bring-up probe — the measurement behind [AS2 runtime](/engine/as2-runtime.md) and [inventory menu](/engine/inventory-menu.md) |
| `swf inventory-menu [--ticks n] [--down n] [--right n]` | drive `interface\inventorymenu.swf` through `InventoryMenuMovieBridge` with a player inventory seeded from the install's own item index, publish it, and report what the movie built: per stage the movie's category and row labels read back out of `EntriesA`, both selections, and the engine's own for comparison, then `swf inventory-menu diagnostics:` (nodes, faults, unimplemented opcodes, unhandled of total invokes, distinct missing names) with the ranked missing names and every unhandled call; `--right` steps category, `--down` steps row through the movie's CLIK focus path. The M12.2.2 bring-up gate, in the CLI because the real-data XCTest host is unreliable here (see [environment](/tools/environment.md)) |
| `swf quest-journal [--quest editorID] [--ticks n] [--down n] [--text] [--objective-state displayed\|completed\|failed] [--probe-rows n]` | drive the Quests page of `interface\\quest_journal.swf` through `QuestJournalMovieBridge` against one real quest — started, walked to its last stage, objectives displayed — and report what the movie built: `swf quest-journal page:` (the movie's own `PAGE_QUEST` constant beside the one the bridge uses, and whether the page is frontmost), per stage the movie's quest and objective rows read back out of `EntriesA`, both selections, the page's title and description fields, the engine's journal paragraphs, and the visible objective entry clips' frame labels, then `swf quest-journal diagnostics:` (nodes, faults, unimplemented opcodes, unhandled of total invokes, distinct missing names); `--quest` picks the quest (default `MGRArniel01`, the M13 target), `--down` steps the selection, `--text` resolves every `FULL`, `CNAM` and `NNAM` out of all three string tables and prints what each answered — which is how the table per field stays measured — `--objective-state` drives the objective's display flags so the entry clip's frame can be read back, `--probe-rows` publishes rows carrying no fields at all and reports which missing-API counts moved, which is how the row-field names were measured. The M13.5 bring-up gate, in the CLI for the same reason `swf inventory-menu` is |
| `swf container-menu [--mode container\|barter] [--side container\|player] [--ticks n] [--down n] [--transfer n]` | drive `interface\\containermenu.swf` or `interface\\bartermenu.swf` through `ContainerMenuMovieBridge` against a container and a player both seeded from the install's own item index, publish the two-pane list, and report what the movie built: the resolved barter pricing and where its two GMSTs came from, per stage the movie's row labels read back out of `EntriesA`, both selections, both purses and the movie's own vendor-gold field, the selected row's price, then `swf container-menu diagnostics:` (nodes, faults, unimplemented opcodes, unhandled of total invokes, distinct missing names) with the ranked missing names and every unhandled call; `--side` opens on the player's half, `--down` steps row through the movie's CLIK focus path, `--transfer` takes, stores, buys or sells the selected row through the engine. The M12.2.3 bring-up gate, in the CLI for the same reason `swf inventory-menu` is |
| `swf dialogue-menu [--ticks n] [--rows n] [--down n] [--speak] [--text] [--probe-rows n]` | drive `interface\\dialoguemenu.swf` through `DialogueMenuMovieBridge` against real DIAL/INFO records and report what the movie built: `swf dialogue-menu class:` (the `DialogueMenuObj` state constants read off the registered class), `swf dialogue-menu entry points:` (how many of the bridge's required entry points the movie publishes and which are missing) and `swf dialogue-menu deferred:` (the ones OpenSky knowingly does not drive yet), then per stage the movie's topic rows read back out of `EntriesA`, both selections, the speaker and subtitle fields, the engine state beside the movie's own `eMenuState` and the list holder's frame label, then `swf dialogue-menu diagnostics:` (nodes, faults, unimplemented opcodes, unhandled of total invokes, distinct missing names) with the ranked tally and every unhandled call; `--rows` picks how many player-category topics to publish, `--down` steps the selection, `--speak` says the selected topic's response so the subtitle field and `TOPIC_CLICKED` can be read back, `--text` resolves the DIAL `FULL`, the INFO `RNAM` prompt and every response run out of all three string tables and prints what each answered — which is how the table per field stays measured — and `--probe-rows` publishes rows carrying no fields at all and reports which missing-name counts moved. The M17.3 bring-up gate, in the CLI for the same reason `swf quest-journal` is |
| `swf info <key>` | parse one movie and print its header line plus every tag (code, name or "unknown", body byte count) |
| `audio info <key>` | frame one `.xwm` — or one `.fuz`, whose FUZE version, lip byte count and audio byte count print first — through `XWMFile` and print its WAVEFORMATEX fields (`wFormatTag`, `nChannels`, `nSamplesPerSec`, `nAvgBytesPerSec`, `nBlockAlign`, `wBitsPerSample`, `cbSize`), payload size + packet count, `dpds` entry count, declared decoded bytes/sample frames, and whether the packet table matches the payload; framing only, no decode |
| `audio sweep` | frame every `.xwm` the archives provide through `XWMFile` and decode it packet-by-packet through `WMADecoder`, streaming one file at a time (per-chunk PCM is counted and dropped); per-file summary line (channels, rate, block align, packets, payload bytes, declared duration) plus `audio sweep:` (files, framed, decoded, unsupported, failed), `audio sweep decode:` (total decoded frames, frame-count mismatches against `dpds`), `audio sweep format:` (format-tag/channel/rate/block-align/cbSize histograms), `audio sweep packets:` (files without `dpds`, `dpds`/packet mismatches, partial final packets), and `audio sweep payload:` (total bytes, declared minutes); an unexpected format tag counts as unsupported, any framing or decode failure exits 1 |
| `audio voice-sweep [--limit <n>] [--names-only]` | two checks over the voice corpus. Naming: rebuild a voice file name for every INFO response in every loaded plugin and compare it against the archive listing, printing per plugin how many archive names the rule explains, how many it spells differently (each beside the name and editor IDs it derived) and how many name no INFO response at all. Framing: frame every `.fuz` through `FUZFile` and its payload through `XWMFile`, one file at a time, reporting lip-blob presence, payload bytes, declared minutes and version/format/channel/rate histograms. `--limit` bounds the framing walk and the report states how many entries it skipped; `--names-only` stops after the naming check; any framing failure exits 1 |
| `screenshot --out <file> [--worldspace/--x/--y] [--size WxH] [--zoom f] [--time-of-day 0-24] [--neighbors] [--ui-sample] [--navmesh-overlay]` | cell scene build + distant LOD -> framing camera -> `Renderer.renderOffscreen` -> PNG; prints load/LOD/draw stats + non-background fraction; `--zoom` (0.1-10) moves eye toward framed center; `--time-of-day` controls procedural sky (default 13); `--neighbors` builds production-size 5x5 (shared libraries) and frames full-cell bounds only; missing cell warns + skips; `--ui-sample` sets `uiScene = .labSample` ([screen-space UI](/rendering/ui.md)) and prints its quad/glyph/dropped/atlas stats; `--navmesh-overlay` draws resident NAVM triangles and prints submitted/drawn/truncation stats ([runtime navigation](/engine/navigation.md)); `render` is identical alias |
| `bench [--worldspace/--x/--y] [--size WxH] [--frames n] [--budget-ms f]` | sustained offscreen render (default 360 frames @ 1280x720) through `Renderer.renderOffscreenSustained` — FrameStats windows + per-frame wall and animation-update times; prints avg/p95/max + fps, exit 1 when avg or p95 misses the budget (default 33.33 ms = 30 fps, todo 2.11 gate) |
| `bench --fly-path [--worldspace/--x/--y] [--size WxH] [--budget-ms f] [--max-frames n] [--footprint-cap-mb f] [--collision-build-budget-ms f] [--actor-build-budget-ms f] [--animation-budget-ms f] [--shadow-budget-ms f] [--audio-budget-ms f]` | scripted launch-center -> east -> north cell flight through live `CellStreamer`; requires physical-footprint plateau/cap, exact 35-cell build union, zero failed builds, collision-build p95 (default 750 ms), actor-build p95 (default 3000 ms; includes cold rig/clip decode), exact/reason-tagged actor + animation accounting, animation-update avg/p95 (default 4 ms), shadow-update avg/p95 (default 14 ms), audio-update avg/p95 (default 0.5 ms), selected rainy weather, updated actor bones, live world particles + rain, shadow casters, drawn grass with zero hard-budget drops, and frame avg/p95 budget; prints living-system peaks, build/update budgets, per-cell accounting, shadow culling + grass instancing |
| `bench --walk-path [--size WxH] [--budget-ms f] [--max-frames n] [--audio-budget-ms f] [--out file]` | fixed M4 production walk from Tamriel `(6,-2)` to Chillfurrow Farm `(7,-3)`, stair ascent, interior floor crossing + paired exterior return; gates timeout, grounding/penetration, destination/build errors, active-physics average (default 33.33 ms), build-aware p95 (Debug 66.67 ms, Release 33.33 ms), and audio-update avg/p95 (default 0.5 ms); explicit `--budget-ms` is strict for both frame metrics; optional final PNG; sustained-only `--frames` and fly-only footprint/build/update budgets are usage errors |

`cell`/`screenshot`/`render` default to the first-render cell
([decision](/decisions/first-render-cell.md), constants in
`opensky/Engine/FirstRenderCell.swift`). Exit codes: 0 ok, 1 failure, 2 usage.

Implementation notes:

* `vfs ls` uses `VirtualFileSystem.archiveEntries()` (engine addition): every archive
  entry path attributed to the winning archive, sorted. Loose files not enumerated —
  walking all of `Data/` is not worth it for a lookup layer; `cat` still resolves them.
* Editor-ID lookup scans EDID fields of every record (whole-file decompression):
  ~6 s worst case on Skyrim.esm, fine for a dev tool.
* `record` prints the shared `RecordTextDump` string; walk helpers live in
  `opensky/Engine/Formats/ESM/ESMWalk.swift` (shared with the
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
* `swf sweep` is the milestone 8.2.1-8.2.4 gate probe. It enumerates every
  archive path under `interface\` ending `.swf` and decodes each through the
  production `SWFFile` container parser, tallying `SWFTagName.isKnown` per tag.
  `ZWS` (LZMA) movies raise the documented `SWFError.unsupportedCompression`
  and are counted as accounted-but-unsupported rather than a failure; any
  other thrown error (malformed/truncated data) is unexpected and exits 1. For
  8.2.2 it additionally decodes every DefineShape-DefineShape4 body through
  `SWFShapeDefinition.parse(tag:)` + `SWFShapeTessellator.tessellate(_:)` and
  every bitmap tag through `SWFBitmapDecoder.decode(tag:jpegTables:)`. For 8.2.3
  it decodes every DefineFont2/3 (`swf sweep fonts:`, with glyph -> CGPath
  conversion) and DefineText/2/EditText tag (`swf sweep text:`), and reports
  fontconfig alias resolution (`swf sweep fontconfig:`) by loading the fontlib
  movies named in `Interface/fontconfig.txt`; any shape/bitmap/font/text decode
  failure on vanilla data exits 1. For 8.2.4 it assembles every movie's frame-1
  display list (`SWFMovie`), flattens it into the renderer's draw-command stream
  (`SWFScene`), and lays out every edit text with the font fontconfig resolves —
  any display-list decode failure exits 1. Vanilla install: 2,677 shapes
  (2,195,435 triangles), 453 bitmaps, 97 fonts (54,988 glyphs), 665
  DefineEditText, 20/20 fontconfig aliases resolved, 53 movies with 130 frame-1
  placements and 15,238 laid-out glyphs, 0 failed. See
  [SWF container](/formats/swf.md).
* `swf render-sweep` is milestone 8.2.4's GPU gate: one `Renderer` over the
  synthetic demo scene, a movie-free baseline frame, then `setSWFMovie` +
  `renderOffscreen` per movie with a per-channel changed-pixel count against
  that baseline. Vanilla install: 53 movies rendered, 0 failed, 2,277 draws,
  692,328 triangles, 44 stencil mask draws; 20 movies change no pixels because
  vanilla hides most frame-1 content behind a zero-alpha CXFORM and reveals it
  from ActionScript. See [screen-space UI layer](/rendering/ui.md).
* `swf action-sweep` is the milestone 8.3.1 stage-2 gate probe: `SWFActionInventory`
  (`opensky/Engine/Formats/SWF/SWFActionInventory.swift`) walks every movie's
  `SWFMovie.actionBlocks` plus every placement's CLIPACTIONS handlers, tallying
  opcode frequency, the host/GFx API surface (resolved from the record
  immediately preceding `ActionGetMember`/`ActionSetMember`/`ActionCallMethod`/
  `ActionCallFunction`/`ActionGetVariable`/`ActionSetVariable`/`ActionNewMethod`/
  `ActionDefineLocal`), clip-event usage, and function/structure stats; the CLI
  file only parses args and prints. Vanilla install: 53 movies, 3,414 action
  blocks (2,163 DoAction, 1,127 DoInitAction, 124 ClipActions), 533,562 action
  records, 56 distinct opcodes, 0 unknown, 3,382 distinct host-API names. See
  [SWF container](/formats/swf.md).
* `audio sweep` is the milestone 9.1.2 + 9.1.3 gate probe. It enumerates every
  archive path ending `.xwm`, frames each through the production `XWMFile`
  container parser and decodes it packet-by-packet through `WMADecoder`,
  keeping only counts and histograms — one file's bytes are read, decoded chunk
  by chunk, tallied and dropped before the next path opens, because an
  unbounded audio sweep is exactly the shape that has run this machine out of
  memory. Vanilla install: 269 files, 269 framed, 269 decoded, 0 unsupported,
  0 failed, all WAVE_FORMAT_WMAUDIO2 stereo, 0 `dpds` mismatches, 869,476,352
  decoded frames with 0 frame-count mismatches, 347.0 declared minutes. See
  [xWMA container](/formats/xwm.md) and
  [World audio playback](/engine/audio.md).
* `audio voice-sweep` is item 17.5's gate probe, and it answers two different
  questions. The naming half re-derives a voice file name for every INFO
  response in every loaded plugin and measures it against the archive listing:
  the rule was derived from that listing in the first place, so this is what
  keeps it honest. The framing half walks the `.fuz` corpus one file at a time,
  the same counts-only shape `audio sweep` uses and for the same reason.
  Vanilla install: 75,408 entries, all container version 1, all mono 44.1 kHz
  WMAv2, 0 framing failures; 43,753 of 44,325 distinct names explained
  (98.71%), 86 spelled differently and 486 naming no INFO response — both
  residues are Bethesda's, and [the `.fuz` page](/formats/fuz.md) says why.
  `make probe` runs it with `--limit 2000`, because framing all 75,408 files is
  minutes of I/O and a smoke run should not pay it; the report states the
  skipped count, so the cap never reads as full coverage.
* `hkx` is M6.1's container probe, extended at M14.1 with the behavior census and at M14.2
  with the node decode. It parses the Havok packfile via shared `HKXFile` (header + section
  table + class-name table + fixup-derived object inventory), summarises it via shared
  `HKBBehaviorCensus`, then decodes every object through `HKBClassRegistry` and walks the
  node tree with `HKBGraphTopology` — the same code the env-gated sweeps run, so any
  behavior file is inspectable without the test suite. Evaluation stays item 14.3. CLI
  parses/prints only; a bad magic/layout/section index exits 1, while a census or topology
  failure is a stderr warning that leaves the container dump standing. See
  [HKX container](/formats/hkx-container.md),
  [HKX behavior graph objects](/formats/hkx-behavior.md) and
  [HKX behavior node classes](/formats/hkx-behavior-nodes.md).
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
  cell/door build, <16-unit stair gain, short interior crossing, or active-physics timing
  over budget exits 1. The default average budget is one 30 fps interval in every build.
  Release p95 uses the same interval; Debug p95 allows two intervals for synchronous
  offscreen scheduler/runtime variance. Passing `--budget-ms` applies that value strictly to
  both metrics.

## Probe harness (make probe)

`tools/probe.sh` (POSIX sh): env-gated smoke run against the local install —
default `/Volumes/data/steam/steamapps/common/Skyrim Special Edition`, override via
`OPENSKY_DATA_ROOT`. Install absent -> `[INFO]` + exit 0 (CI safe). Checks: `vfs ls`
finds meshes; `record 0x3C` decodes Tamriel (UESP "Skyrim Mod:FormIDs");
`gmst movement` reports every resolved gait, step height, and jump takeoff with its source; `cell`
summary; `actor` requires zero unresolved ACHR template+visual chains in the default
3x3 block, then `actor --npc Heimskr` must report skeleton, parts + FaceGen path;
`collision --radius 2` gates placed 5x5 collision; `nif`/`dds` inspect first listed
assets; `hkx` dumps the container inventory for `skeleton.hkx` (must show
`hk_2010.2.0-r1`, `__classnames__`/`__data__` sections, an `hkaSkeleton` class) and a
human idle `.hkx` (must show `hkaSplineCompressedAnimation`), and censuses
`mt_behavior.hkx` (M14.1 gate: role `behavior`, root generator `hkbStateMachine`, 67
variables, 931 events, no unresolved members; M14.2 gate: 5,115 objects decoded, no class
without a decoder, 5,110 nodes reached from the root generator, root state machine named
`MT_RootBehavior`); `animation` decodes
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
`bench --walk-path` runs M4's 640x360 physics/route gate with the build-aware default frame
budgets + writes `probe-walk-path.png`. Before touching game data, the harness also
checks that `--walk-path` rejects `--frames`, `--footprint-cap-mb`, and
`--collision-build-budget-ms` with exit status 2. Every capture and the full output
(`probe.log`) go to the run directory the probe prints, `logs/probe/<UTC timestamp>/`,
with `logs/probe/latest` pointing at the newest run
([run output layout](/tools/run-output.md)).
