# OpenSky knowledge base

Wiki in Open Knowledge Format (OKF v0.1). Reverse-engineered formats, subsystem design,
and decisions live here so knowledge survives across sessions. See AGENTS.md
"Documentation wiki".

## Formats

* [BSA Archive](/formats/bsa.md) - Skyrim SE v105 archive layout, LZ4 frames,
  how OpenSky parses and extracts.
* [Virtual file system](/formats/vfs.md) - resource path resolution: loose
  files over archives, archive load order, lazy open.
* [ESM/ESP plugin container](/formats/esm.md) - record/GRUP/field framing,
  zlib-compressed records, lazy traversal.
* [FormID + TES4 header](/formats/formid.md) - plugin header fields, master
  lists, raw FormID -> (plugin, objectID) resolution.
* [Localized string tables](/formats/strings.md) - .strings/.dlstrings/
  .ilstrings layout, lenient encoding policy, lstring lookup wiring.
* [Record decoders](/formats/records.md) - WRLD/CELL/REFR/STAT field layouts
  and their engine types.
* [Interior lighting records](/formats/lighting.md) - CELL XCLL/LTMP, LGTM DATA/DALC,
  LIGH DATA/FNAM, REFR XRDS/XEMI, inheritance + decode policy.
* [Exterior water records](/formats/water.md) - CELL XCLW/XCWT, WRLD defaults + parent
  inheritance, WATR DNAM color offsets and sentinel policy.
* [Terrain records](/formats/land.md) - LAND/LTEX/TXST layouts: VHGT gradient
  height field, VNML/VCLR, BTXT/ATXT/VTXT splat layers, texture sets.
* [Grass records](/formats/grass.md) - GRAS fixed DATA controls + repeated LTEX GNAM links.
* [Weather records](/formats/weather.md) - WTHR NAM0 color layers/FNAM fog/DATA
  wind + precipitation, CLMT weather lists + timing, REGN weather areas.
* [Distant LOD](/formats/lod.md) - lodsettings plus BTR/BTO paths and LOD-specific NIF
  blocks, tree LST/BTT layouts, placement rules, full vanilla sweep evidence.
* [Skyrim INI settings](/formats/ini.md) - read-only decode, file precedence, typed
  terrain-distance values, and OpenSky override policy.
* [NIF mesh](/formats/nif.md) - Gamebryo 20.2.0.7 container, scene graph,
  geometry/materials, SSE skin blocks, dynamic FaceGen + skeleton bind pose.
* [NIF Havok collision](/formats/nif-collision.md) - bhk root/body/shape graphs,
  compressed mesh reconstruction, unit/filter policy, Whiterun sweep evidence.
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

## Engine

* [Game data locator](/engine/game-data-locator.md) - how the Skyrim SE install is
  found and validated at launch; override settings.
* [Cell scene build](/engine/cell-scene.md) - exterior cell -> draw list: WRLD walk,
  STAT resolution, skip taxonomy, grouping, world bounds.
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
  resolution, proximity activation, camera teleport, suspended exterior streaming.
* [Free-fly camera](/engine/free-fly-camera.md) - WASDQE + mouse-look input capture,
  yaw/pitch pose -> view matrix, movement speeds tuned to Skyrim scale.
* [Terrain walk mode](/engine/walk-mode.md) - fixed-step capsule, terrain + mesh
  collide-and-slide, slope/ceiling response, bounded stairs, door pose reset.
* [Static collision world](/engine/collision-world.md) - per-cell placed bhk shapes,
  immutable BVH broadphase, serial build/cache confinement, streaming lifetime + budgets.
* [Actor idle animation](/engine/actor-animation.md) - HKX idle sampling, skeleton-world
  pose composition, NIF palette refresh, streamed lifetime, fallback accounting + budget.
* [Living environment integration](/engine/living-environment.md) - combined M7 runtime,
  app A/B controls, exterior/interior evidence + frame/build/footprint gate.

## Rendering

* [Metal 4 mesh renderer](/rendering/metal4-renderer.md) - static + animated skinned paths:
  pipeline variants, uniform/palette rings, argument tables, counter-heap frame stats,
  offscreen render, scene types.
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
  UI Lab surface.

## Decisions

* [Native macOS app skeleton](/decisions/native-macos-app.md) - macOS-only target,
  programmatic AppKit, Metal 4 pipeline, stable local signing, no sandbox.
* [Coordinates + units](/decisions/coordinates.md) - Skyrim Z-up world kept verbatim,
  view/projection convert to Metal; matrix convention, winding, near/far, REFR euler.
* [First render cell](/decisions/first-render-cell.md) - WhiterunExterior06 at Tamriel
  (6,-2) as the 2.7/2.9 target; probe ranking, MODL `meshes\` prefix rule.
* [Metal shader tooling](/decisions/metal-tooling.md) - clang-format for .metal,
  compiler warnings-as-errors as the linter; documented exception to per-language rule.
* [App logo + icon pipeline](/decisions/app-logo.md) - original "North Peak" SVG mark,
  `make icon` renders AppIcon set via rsvg-convert; legal rationale.

## Tools

* [CLI dev tool](/tools/cli.md) - openskycli target sharing the engine sources:
  vfs/record/cell/nif/dds/screenshot commands, env-gated make probe harness.
* [Main-app asset browser](/tools/preview-gui.md) - Library > Asset Browser destination:
  VFS + record browsing, toolbar World PNG capture, offscreen NIF/DDS previews.
* [Main-app UI framework + placement](/tools/app-ui.md) - unified sidebar shell,
  destination registry, panel base classes, placement tree, accessibility-id contract.

## Meta

* [Testing setup](/testing.md) - test targets, make entrypoints, real-data
  suites + watchdog, result reporting, machine-specific quirks.
* [Roadmap](/todo.md) - active M8 work, dependency-ordered milestones, acceptance gates,
  app-sidebar verification paths.
