# OpenSky knowledge base

Wiki in Open Knowledge Format (OKF v0.1). Reverse-engineered formats, subsystem design,
and decisions live here so knowledge survives across sessions. See AGENTS.md
"Documentation wiki".

## Formats

* [BSA Archive](/formats/bsa.md) - Skyrim SE v105 archive layout, LZ4 frames,
  system-accelerated independent blocks, and linked-block fallback.
* [Virtual file system](/formats/vfs.md) - resource path resolution: loose
  files over archives, archive load order, lazy open.
* [ESM/ESP plugin container](/formats/esm.md) - record/GRUP/field framing,
  zlib-compressed records, lazy traversal.
* [Game settings](/formats/gmst.md) - typed GMST DATA values, selected movement
  tuning, active-plugin precedence, and explicit fallback policy.
* [FormID + TES4 header](/formats/formid.md) - plugin header fields, master
  lists, raw FormID -> (plugin, objectID) resolution.
* [Localized string tables](/formats/strings.md) - .strings/.dlstrings/
  .ilstrings layout, lenient encoding policy, lstring lookup wiring.
* [UI translation strings](/formats/translation-strings.md) - UTF-16
  Interface/Translations/*.txt files, $KEY token resolution, label provider.
* [Record decoders](/formats/records.md) - WRLD/CELL/REFR/STAT/GLOB/MOVT field layouts
  and their engine types, including REFR XLKR linked references and the XPRM
  primitive volume, and the GLOB float-on-disk typing trap. Also the inventory
  families MISC/BOOK/ALCH/INGR/WEAP/AMMO, CONT contents, REFR ownership, the
  `ItemDefinitionStore` index, and the order-dependent QUST record - stages, log
  entries, objectives, alias fill types, and the `QuestStore` index.
* [Interior lighting records](/formats/lighting.md) - CELL XCLL/LTMP, LGTM DATA/DALC,
  LIGH DATA/FNAM, REFR XRDS/XEMI, inheritance + decode policy.
* [Exterior water records](/formats/water.md) - CELL XCLW/XCWT, WRLD defaults + parent
  inheritance, WATR DNAM color offsets and sentinel policy.
* [Terrain records](/formats/land.md) - LAND/LTEX/TXST layouts: VHGT gradient
  height field, VNML/VCLR, BTXT/ATXT/VTXT splat layers, texture sets.
* [Grass records](/formats/grass.md) - GRAS fixed DATA controls + repeated LTEX GNAM links.
* [Weather records](/formats/weather.md) - WTHR NAM0 color layers/FNAM fog/DATA
  wind + precipitation, CLMT weather lists + timing, REGN weather and sound areas.
* [Sound records](/formats/sound.md) - SNDR descriptor tracks, SNCT category hierarchy,
  SOUN SDSC links, attenuation, looping, and separator-led canonical VFS path resolution.
* [Acoustic space (ASPC)](/formats/acoustic-space.md) - interior-ambience bridge:
  ASPC fields, the `RDAT` FormID collision with REGN's area header, and the
  interior-only region borrow.
* [Music records (MUSC, MUST)](/formats/music.md) - MUSC playlist flags/priority/
  ducking plus MUST track type, loop and cue data, the CELL/WRLD/REGN music links,
  and the `music\` path rules.
* [Conditions (CTDA, CITC, CIS1, CIS2)](/formats/conditions.md) - the shared 32-byte
  condition payload: operator and flag bits, float or GLOB comparison value, raw
  function index and parameters, run-on types, and the skip-don't-throw decode policy;
  plus evaluation - the function registry, OR grouping, run-on resolution, the
  reason-tagged-false failure model, and the coverage tally with its vanilla sweep.
* [Papyrus compiled scripts](/formats/pex.md) - big-endian Skyrim PEX 3.2
  framing, typed objects/functions/instructions, VFS loading, defensive error
  policy, opcode inventory, and typed native-call coverage census.
* [Papyrus attachment data](/formats/vmad.md) - ESM VMAD script and property
  decode, both object layouts, fragment and alias skip policy, FormID-to-
  ReferenceKey resolution, and exact PEX backing-variable binding.
* [Distant LOD](/formats/lod.md) - lodsettings plus BTR/BTO paths and LOD-specific NIF
  blocks, tree LST/BTT layouts, placement rules, full vanilla sweep evidence.
* [Skyrim INI settings](/formats/ini.md) - read-only decode, file precedence, typed
  terrain-distance values, and OpenSky override policy.
* [NIF mesh](/formats/nif.md) - Gamebryo 20.2.0.7 container, scene graph,
  row-vector `Matrix33` convention, geometry/materials, SSE skin blocks,
  dynamic FaceGen + skeleton bind pose.
* [NIF Havok collision](/formats/nif-collision.md) - bhk root/body/shape graphs,
  compressed mesh reconstruction, unit/filter policy, SkyrimLayer 12 trigger routing,
  Whiterun sweep evidence.
* [NIF particle systems](/formats/nif-particles.md) - NiParticleSystem/NiPSysData,
  emitter + modifier blocks, effect-shader wiring, Whiterun sweep evidence.
* [DDS texture container](/formats/dds.md) - DDS_HEADER/DXT10 layout, BCn + 32-bit RGB,
  mip chain math, color-space policy.
* [Actor records](/formats/actors.md) - ACHR/NPC_/LVLN/LVLI/RACE/ARMO/ARMA/OTFT
  layouts, TPLT chain + visual appearance resolution (skin/outfit/slot
  masking), FaceGen path convention + actor GPU assembly.
* [HKX packfile container](/formats/hkx-container.md) - Havok hk_2010 packfile
  header, section + fixup tables, class-name inventory, object enumeration.
* [hkaSkeleton object](/formats/hka-skeleton.md) - bone names, parent indices,
  reference pose decode + name-map onto the NIF skeleton nodes skinning uses.
* [hkaSplineCompressedAnimation](/formats/hka-animation.md) - idle-clip metadata,
  spline blocks, 16-bit vector/40-bit quaternion decode + local-transform sampling.
* [HKX behavior graph objects](/formats/hkx-behavior.md) - shared object-graph pointer,
  array and string resolution; hkRootLevelContainer, hkbBehaviorGraph, graph/string data,
  variable value set, project + character string data, file role, vanilla census.
* [HKX behavior node classes](/formats/hkx-behavior-nodes.md) - byte layouts of every
  node, modifier, condition and Bethesda extension class the vanilla player behavior
  files contain, the class registry keyed by class name, and the graph walk on it.
* [SWF container](/formats/swf.md) - FWS/CWS signature + compression, bit-packed
  FrameSize RECT, tag stream framing, standard tag-name table (Scaleform UI);
  DefineShape-DefineShape4 decode + tessellation, lossless/JPEG bitmap tags,
  DefineFont2/3 glyphs + text tags, fontconfig.txt alias mapping, and the
  display-list control tags (place/remove, sprites, clip depth, asset imports).

* [xWMA container](/formats/xwm.md) - .xwm music files: RIFF/XWMA framing, fmt
  WAVEFORMATEX parameters, dpds packet table, data payload, frame-only policy
  and vanilla sweep evidence.

* [OpenSky save container](/formats/opensky-save.md) - our own .osav format, not
  Bethesda's: header metadata, load-order fingerprint, tagged chunks and the
  reference-delta, global-variable, Papyrus script-instance, Papyrus update-timer,
  runtime-inventory and spawned-reference entry layouts, determinism and version rules,
  atomic write, and the
  `OpenSkySaveStore` slot façade + fingerprint builders above it.

## Engine

* [Game data locator](/engine/game-data-locator.md) - how the Skyrim SE install is
  found and validated at launch; override settings.
* [Cell scene build](/engine/cell-scene.md) - exterior cell -> draw list: WRLD walk,
  STAT resolution, skip taxonomy, grouping, world bounds.
* [Cell streaming](/engine/cell-streaming.md) - camera position -> desired NxN exterior-cell
  grid, built off the main thread on one serial queue with a per-frame residency budget, and
  the world-state snapshot every dispatched build carries.
* [Terrain mesh build](/engine/terrain.md) - LAND -> per-quadrant meshes under the cell's
  objects: grid topology, base textures, XCLC quad-hiding, DNAM fallback plane, placement.
* [Procedural grass](/engine/grass.md) - deterministic LAND-driven placement, cell-owned
  instanced rendering, weather wind, distance fade, budget, and app controls.
* [Distant LOD streaming](/engine/distant-lod.md) - INI-driven cell-clipped rings, tree
  billboards, atomic replacement, asset lifetime, real-render evidence.
* [Sky + water environment](/engine/sky-water.md) - procedural time-of-day sky, per-cell
  water resolution/build, animated alpha-blend render path.
* [Weather runtime](/engine/weather.md) - region/climate weather selection, timed
  sky/fog/ambient transitions over time-of-day, published wind, force/pause app controls.
* [Interior door transitions](/engine/interiors.md) - interior CELL build, DOOR/XTEL
  resolution, selected activation, camera teleport, suspended exterior streaming.
* [Interaction targeting](/engine/interaction.md) - walk-mode view-ray selection,
  localized record names and action labels, typed activation events, HUD publication,
  exact door dispatch, and the world-item layer above it: taking a loose item, container
  transfer sessions, dropping into the world, and the `World > HUD & Interaction > Items`
  acceptance surface.
* [Free-fly camera](/engine/free-fly-camera.md) - WASDQE + mouse-look input capture,
  yaw/pitch pose -> view matrix, movement speeds tuned to Skyrim scale.
* [Terrain walk mode](/engine/walk-mode.md) - fixed-step capsule, terrain + mesh
  collide-and-slide, slope/ceiling response, bounded stairs, door pose reset, build-aware
  route timing gate, the three camera modes, the third-person orbit camera with
  collision-aware zoom, the rendered player body, and the first-person acceptance surface.
* [Static collision world](/engine/collision-world.md) - per-cell placed bhk shapes,
  immutable BVH broadphase, fail-loud geometry accounting, streaming lifetime + budgets,
  trigger volumes and their per-frame OnTriggerEnter/OnTriggerLeave occupancy diff.
* [Actor idle animation](/engine/actor-animation.md) - HKX idle sampling, skeleton-world
  pose composition, NIF palette refresh, streamed lifetime, fallback accounting + budget,
  the graph-driven player path and its simulation clock.
* [Behavior graph runtime](/engine/behavior-runtime.md) - headless Havok Behavior
  evaluation: instance model, fixed update order, variables, events, bindings, clip time
  and triggers, weighted blends, state machines with event-driven transitions, crossfades
  and nesting, the transition-condition language, clip phase synchronization, root-motion
  extraction, multi-file behavior references, the first-person rig and its second graph
  instance, and the honest-coverage tally.
* [Living environment integration](/engine/living-environment.md) - combined M7 runtime,
  app A/B controls, exterior/interior evidence + frame/build/footprint gate.
* [Menu mode](/engine/menu-mode.md) - push/pop menu stack, world-vs-menu input-capture
  switch, world-sim pause via a pausable frame clock (no time jump on resume).
* [System menu](/engine/system-menu.md) - Resume/Settings/Quit selector, the menu-stack
  handoff that pauses the world, the data-root and audio-volume settings placeholders,
  and synchronized keyboard navigation through the visible vanilla `quest_journal.swf`
  System and Settings pages.
* [Quest journal](/engine/journal.md) - the Quests page of vanilla `quest_journal.swf`
  driven from quest state: the measured list contract, the row model and its string tables,
  `<Alias=...>` text substitution, the world-mode `J` key, the
  `World > Quests & Journal` surface, and the M13 gate that drives a quest end to end
  through it.
* [Inventory menu](/engine/inventory-menu.md) - the player's item list and its categories,
  the cross-movie character import vanilla `inventorymenu.swf` needs before it has a list
  at all, the `EntriesA` data contract, and the equip/unequip/drop actions behind it.
* [Container and barter menus](/engine/barter.md) - the two-pane transfer list shared by
  vanilla `containermenu.swf` and `bartermenu.swf`, the cited `fBarterMin`/`fBarterMax`
  price formula, gold-conserving merchant transactions, and the merchant nomination seam.
* [Inventory and equipment gate](/engine/inventory-equipment.md) - the M12 milestone gate:
  the take/transfer/equip/buy/sell/drop/save/load loop proved end to end with conservation
  at every step, the `World > Inventory & Equipment` destination, dev item grants, `XOWN`
  ownership reporting, and per-actor appearance-skip accounting.
* [AS2 runtime](/engine/as2-runtime.md) - ActionScript 2 interpreter and the movie it
  drives: value model + coercions, bounded execution, display objects and timeline,
  Scaleform Stage rectangles, events, indexed global mouse input and hit testing, the
  GameDelegate bridge, path-targeted HUD calls, missing-API tally.
* [Papyrus virtual machine](/engine/papyrus-vm.md) - bounded Skyrim PEX execution: typed
  values, explicit frames, arrays, states, a native registry, deterministic real/game-time
  suspension scheduling, faults and coverage tallies, with VMAD-supplied initial values;
  plus the main-actor world runtime, use-key and trigger dispatch, persistent world
  mutation, update timers, save state, the `World > Scripts` surface, and the M11 gate.
* [World audio playback](/engine/audio.md) - AVAudioEngine graph with 3D positional
  sources and non-positional music/ambience beds, streaming WMA decode off the main
  thread, vanilla SNCT category volumes, per-category mute and solo, source
  budget/eviction, the per-frame audio-update budget, and the `World > Audio` surface
  plus the M9 acceptance record.
* [World SFX + ambience](/engine/world-sfx.md) - world sound director wiring
  activation and animation events to one-shot and movement-loop SFX, per-cell
  ASPC/REGN ambience bed resolution into category submixes, and the
  `World > Audio > SFX & Ambience` verification surface.
* [Music playlists](/engine/music.md) - MUSC/MUST playlist selection through the
  CELL/REGN/WRLD precedence chain, the derived exploration/town/interior states,
  palette expansion and flag handling, the shipped-file `.xwm` resolution the
  vanilla `.wav` track names need, and the crossfading music director.
* [Game clock and calendar](/engine/game-clock.md) - timescale-driven game time over the
  Tamriel calendar: the deterministic GameClock value, the clock-owns-time authority rule
  for the vanilla time globals, weather's elapsed-game-hours feed, the CLOK save chunk,
  and the fixed-clock offscreen/CLI story.
* [Runtime reference identity and world state](/engine/runtime-state.md) - session-stable
  ReferenceKey identity over plugin and generated references, the per-cell
  RuntimeReferenceIndex, and the mutable WorldStateStore above it: typed component deltas,
  dirty tracking, reset-to-plugin-default, the bounded change journal, the
  deterministic snapshot, how a cell build applies that snapshot to render and
  collision together, how a mutation to an already-resident cell reaches the screen
  through a streamer-driven rebuild, the runtime global-variable layer and the value-lookup
  seam conditions and the clock read through, the save/load round trip through
  OpenSkySaveStore, and the `World > Runtime State` panel with its time, globals and
  conditions sections, the interleaved journal tail, the M10.1 and M10 acceptance
  records, and the inventory component above all of it: full-override stacks, re-derived
  container/actor/player baselines, the add/remove/transfer accounting layer with its
  conservation guarantees, carry weight and gold, and the additive INVN save chunk; plus
  the spawned-reference component that lets the running game place objects no plugin
  authored, its synthesized 0xFF-prefixed FormID, and the additive SPWN save chunk.

## Rendering

* [Metal 4 mesh renderer](/rendering/metal4-renderer.md) - static + animated skinned paths:
  pipeline variants, uniform/palette rings, argument tables, counter-heap frame stats plus
  the live snapshot seam, offscreen render, scene types.
* [Cascaded sun shadows](/rendering/shadows.md) - cascade fit math, depth-only
  pre-pass with per-cascade caster culling clamped to resident cells, off/low/high
  quality + `World > Environment` surface, fly-bench CPU budget, PCF sun-term
  filtering, A/B verification.
* [Particle playback](/rendering/particles.md) - deterministic CPU emitters, weather-wind
  modifiers, instanced Metal billboards, effect blend pipelines, app controls + Whiterun
  offscreen acceptance.
* [Precipitation volumes](/rendering/precipitation.md) - WTHR-driven camera rain/snow,
  shared particle rendering, wind, roof ray occlusion, storm sky darkening + acceptance.
* [Screen-space UI layer](/rendering/ui.md) - 2D overlay over the finished frame:
  anchored scene, layout + text primitives, system-font glyph atlas, scale handling,
  UI Lab surface, and the SWF display-list render layer (per-draw uniforms,
  stencil clips, live vanilla HUD, UI Lab movie selector).

## Decisions

* [Native macOS app skeleton](/decisions/native-macos-app.md) - macOS-only target,
  programmatic AppKit, Metal 4 pipeline, stable local signing, no sandbox.
* [Coordinates + units](/decisions/coordinates.md) - Skyrim Z-up world kept verbatim,
  view/projection convert to Metal; matrix convention, winding, near/far, REFR euler.
* [First render cell](/decisions/first-render-cell.md) - WhiterunExterior06 at Tamriel
  (6,-2) as the 2.7/2.9 target; probe ranking, MODL `meshes\` prefix rule.
* [Metal shader tooling](/decisions/metal-tooling.md) - clang-format for .metal,
  compiler warnings-as-errors as the linter; documented exception to per-language rule.
* [AS2 runtime scope](/decisions/swf-as2-scope.md) - implement the closed 56-opcode
  set vanilla menus use in full; phase the open-ended host API behind a logged
  no-op plus tally.
* [Havok behavior scope](/decisions/havok-behavior-scope.md) - full-graph evaluation over
  the 55 classes the vanilla player files use; swim in, first person with full arms,
  clean-room sourcing rule.
* [App logo + icon pipeline](/decisions/app-logo.md) - original "North Peak" SVG mark,
  `make icon` renders AppIcon set via rsvg-convert; legal rationale.
* [ffmpeg for audio decode](/decisions/ffmpeg-audio.md) - vendored decode-only LGPL build
  in a gitignored prefix, `import CFFmpeg` module map, dylibs embedded in the app bundle;
  why the Homebrew build is unusable and what LGPL requires.

## Tools

* [CLI dev tool](/tools/cli.md) - openskycli target sharing the engine sources:
  commands, mode-specific benchmark validation, and env-gated make probe harness.
* [Main-app asset browser](/tools/preview-gui.md) - Library > Asset Browser destination:
  VFS + record browsing, toolbar World PNG capture, offscreen NIF/DDS previews.
* [Main-app UI framework + placement](/tools/app-ui.md) - unified sidebar shell,
  destination registry, panel base classes, hosted sections, placement tree,
  layout + interaction invariants, accessibility-id contract.
* [Sidebar verification convention](/tools/sidebar-acceptance.md) - the record every
  milestone acceptance writes (path, destination id, control ids, readout, covering
  tests), what counts as evidence, and the per-milestone ledger.
* [Build system and xcodebuild invocation](/tools/build-system.md) - the one xcodebuild
  command line every make target and tools/ script shares: knobs and their defaults,
  `-quiet` versus the transcripts kept in `logs/`, the derived built-products path, the
  `Config/*.xcconfig` layer that holds every build setting, and what `-only-testing` does
  not save.
* [Swift toolchain and language mode](/tools/swift-toolchain.md) - the Apple Swift 6.3.3
  baseline, Swift 6 language mode across every target, the `make swift-baseline` gate that
  enforces both, default main-actor isolation, and the isolation patterns the migration
  settled on.
* [Local environment and external state](/tools/environment.md) - dated record of
  machine-specific and third-party facts skills must not hardcode: TCC permissions,
  CI suspension, upstream spec-host quirks, each with the condition that retires it.

## Meta

* [Testing setup](/testing.md) - test targets, make entrypoints, real-data
  suites + watchdog, result reporting, machine-specific quirks.
* Roadmap - not in this wiki. Open work lives in GitHub issues and milestones, where
  milestone `#n` is OpenSky milestone `Mn`. See AGENTS.md "Roadmap and open work".
