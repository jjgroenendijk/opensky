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

## Engine

* [Game data locator](/engine/game-data-locator.md) - how the Skyrim SE install is
  found and validated at launch; override settings.

## Rendering

<!-- Metal 4 renderer notes -->

## Decisions

* [Native macOS app skeleton](/decisions/native-macos-app.md) - macOS-only target,
  programmatic AppKit, Metal 4 pipeline, ad-hoc signing, no sandbox.

## Meta

* [Roadmap](/todo.md) - mission roadmap, milestones, open questions.
