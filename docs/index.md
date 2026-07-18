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
* [Terrain records](/formats/land.md) - LAND/LTEX/TXST layouts: VHGT gradient
  height field, VNML/VCLR, BTXT/ATXT/VTXT splat layers, texture sets.
* [NIF mesh](/formats/nif.md) - Gamebryo 20.2.0.7 container: header, block
  table, block walk.
* [DDS texture container](/formats/dds.md) - DDS_HEADER/DXT10 layout, BCn
  formats, mip chain math, color-space policy.

## Engine

* [Game data locator](/engine/game-data-locator.md) - how the Skyrim SE install is
  found and validated at launch; override settings.
* [Cell scene build](/engine/cell-scene.md) - exterior cell -> draw list: WRLD walk,
  STAT resolution, skip taxonomy, grouping, world bounds.
* [Free-fly camera](/engine/free-fly-camera.md) - WASDQE + mouse-look input capture,
  yaw/pitch pose -> view matrix, movement speeds tuned to Skyrim scale.

## Rendering

* [Metal 4 static-mesh renderer](/rendering/metal4-renderer.md) - static-mesh render
  path: pipeline variants, uniform rings, argument tables, counter-heap frame
  stats, offscreen render, scene types.

## Decisions

* [Native macOS app skeleton](/decisions/native-macos-app.md) - macOS-only target,
  programmatic AppKit, Metal 4 pipeline, ad-hoc signing, no sandbox.
* [Coordinates + units](/decisions/coordinates.md) - Skyrim Z-up world kept verbatim,
  view/projection convert to Metal; matrix convention, winding, near/far, REFR euler.
* [First render cell](/decisions/first-render-cell.md) - WhiterunExterior06 at Tamriel
  (6,-2) as the 2.7/2.9 target; probe ranking, MODL `meshes\` prefix rule.

## Tools

* [CLI dev tool](/tools/cli.md) - openskycli target sharing the engine sources:
  vfs/record/cell/nif/dds/render subcommands, env-gated make probe harness.
* [Asset preview GUI](/tools/preview-gui.md) - openskypreview target: VFS +
  record browser with offscreen-rendered NIF/DDS previews.

## Meta

* [Testing setup](/testing.md) - test targets, make entrypoints, headless
  unit-test host, fixture policy.
* [Roadmap](/todo.md) - mission roadmap, milestones, open questions.
