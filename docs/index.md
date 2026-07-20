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
* [Distant LOD](/formats/lod.md) - lodsettings plus BTR/BTO paths and LOD-specific NIF
  blocks, placement rules, full vanilla sweep evidence.
* [NIF mesh](/formats/nif.md) - Gamebryo 20.2.0.7 container, scene graph,
  geometry/materials, SSE skin blocks, dynamic FaceGen + skeleton bind pose.
* [NIF Havok collision](/formats/nif-collision.md) - bhk root/body/shape graphs,
  compressed mesh reconstruction, unit/filter policy, Whiterun sweep evidence.
* [DDS texture container](/formats/dds.md) - DDS_HEADER/DXT10 layout, BCn + 32-bit RGB,
  mip chain math, color-space policy.
* [Actor records](/formats/actors.md) - ACHR/NPC_/LVLN/LVLI/RACE/ARMO/ARMA/OTFT
  layouts, TPLT chain + visual appearance resolution (skin/outfit/slot
  masking), FaceGen path convention + actor GPU assembly.
* [HKX packfile container](/formats/hkx-container.md) - Havok hk_2010 packfile
  header, section + fixup tables, class-name inventory, object enumeration.
* [hkaSkeleton object](/formats/hka-skeleton.md) - bone names, parent indices,
  reference pose decode + name-map onto the NIF skeleton nodes skinning uses.

## Engine

* [Game data locator](/engine/game-data-locator.md) - how the Skyrim SE install is
  found and validated at launch; override settings.
* [Cell scene build](/engine/cell-scene.md) - exterior cell -> draw list: WRLD walk,
  STAT resolution, skip taxonomy, grouping, world bounds.
* [Terrain mesh build](/engine/terrain.md) - LAND -> per-quadrant meshes under the cell's
  objects: grid topology, base textures, XCLC quad-hiding, DNAM fallback plane, placement.
* [Distant LOD streaming](/engine/distant-lod.md) - cell-clipped coarsening rings beyond
  5x5, atomic coverage replacement, asset lifetime, real-render evidence.
* [Sky + water environment](/engine/sky-water.md) - procedural time-of-day sky, per-cell
  water resolution/build, animated alpha-blend render path.
* [Interior door transitions](/engine/interiors.md) - interior CELL build, DOOR/XTEL
  resolution, proximity activation, camera teleport, suspended exterior streaming.
* [Free-fly camera](/engine/free-fly-camera.md) - WASDQE + mouse-look input capture,
  yaw/pitch pose -> view matrix, movement speeds tuned to Skyrim scale.
* [Terrain walk mode](/engine/walk-mode.md) - fixed-step capsule, terrain + mesh
  collide-and-slide, slope/ceiling response, bounded stairs, door pose reset.
* [Static collision world](/engine/collision-world.md) - per-cell placed bhk shapes,
  immutable BVH broadphase, serial build/cache confinement, streaming lifetime + budgets.

## Rendering

* [Metal 4 mesh renderer](/rendering/metal4-renderer.md) - static + bind-pose skinned
  paths: pipeline variants, uniform rings, argument tables, counter-heap frame
  stats, offscreen render, scene types.

## Decisions

* [Native macOS app skeleton](/decisions/native-macos-app.md) - macOS-only target,
  programmatic AppKit, Metal 4 pipeline, stable local signing, no sandbox.
* [Coordinates + units](/decisions/coordinates.md) - Skyrim Z-up world kept verbatim,
  view/projection convert to Metal; matrix convention, winding, near/far, REFR euler.
* [First render cell](/decisions/first-render-cell.md) - WhiterunExterior06 at Tamriel
  (6,-2) as the 2.7/2.9 target; probe ranking, MODL `meshes\` prefix rule.
* [Metal shader tooling](/decisions/metal-tooling.md) - clang-format for .metal,
  compiler warnings-as-errors as the linter; documented exception to per-language rule.

## Tools

* [CLI dev tool](/tools/cli.md) - openskycli target sharing the engine sources:
  vfs/record/cell/nif/dds/screenshot commands, env-gated make probe harness.
* [Main-app asset browser](/tools/preview-gui.md) - unified World/browser window: VFS +
  record browsing, World PNG capture, offscreen-rendered NIF/DDS previews.

## Meta

* [Testing setup](/testing.md) - test targets, make entrypoints, headless
  unit-test host, fixture policy.
* [Roadmap](/todo.md) - milestone history, active M6 work, tooling, future direction.
