---
type: Tool
title: Asset preview GUI (openskypreview)
description: AppKit browser over the engine VFS + Skyrim.esm records with
  offscreen-rendered NIF/DDS previews - target layout, browse model, preview
  pipeline.
tags: [tool, gui, dev, preview, rendering]
timestamp: 2026-07-18T00:00:00Z
---

# Asset preview GUI (openskypreview)

Third product target (todo 2.10): browse the local install's assets and
preview one at a time — the parser/renderer's eye view without launching the
game app. M2 scope is browse + single-asset preview; grows into the world
viewer/test harness later.

## Target sharing

Same mechanism as [the CLI](/tools/cli.md): macOS app target in
`opensky.xcodeproj` listing the `opensky/` synchronized root group with a
`PBXFileSystemSynchronizedBuildFileExceptionSet` excluding app-only files
(`OpenSkyApp.swift`, `AppDelegate.swift`, `GameViewController.swift`,
`GameMetalView.swift`, `Assets.xcassets`). App entry code lives in
`openskypreview/`; shared scheme `openskypreview`; build via `make preview`.
`Shaders.metal` compiles into the bundle's `default.metallib`, so `Renderer`
works unchanged.

## UI + browse model

Programmatic AppKit (repo precedent, no storyboard): split view. Sidebar =
category popup (Meshes/.nif, Textures/.dds, Records, All files) + filter
field + lazy `NSTableView` + status line. Detail pane = preview image +
monospace info text. Data root comes from the
[game data locator](/engine/game-data-locator.md) chain; missing install ->
in-window message, app still launches (no crash, no alert loop).

Browse logic is AppKit-free in `opensky/Preview/` so it unit-tests without a
window (`PreviewCatalogTests`, `RecordTextDumpTests`,
`TexturePreviewSceneTests`):

* `PreviewCatalog` — archive entries (`VirtualFileSystem.archiveEntries()`)
  plus a headers-only `ESMWalk` over every Skyrim.esm record (~870k)
  flattened to filterable rows ("TYPE FORMID" for records). Filter:
  case-insensitive substring, `/` matches the canonical `\` separator.
  Load runs off the main thread (opening every archive + the record walk
  takes seconds -> loading status); filtering the record list runs off-main
  too, a generation counter drops stale results. Missing/broken esm ->
  file browsing still works, note in the status line.
* `RecordTextDump` — one-record dump (header line, decoded
  WRLD/CELL/STAT/REFR view, field list capped at 64 with per-type tail
  summary). The CLI `record` command prints the same string — single impl.
* `AssetInfoText` — NIF container/model summary + DDS header/mip chain text
  (same content the CLI `nif`/`dds` commands print).
* `ESMWalk` moved `openskycli/` -> `opensky/Formats/ESM/` (shared by CLI +
  preview; malformed-group warning now goes to os_log instead of stderr).

## Preview pipeline

Selection -> `PreviewDetailBuilder` (app side, main thread; MeshLibrary /
TextureLibrary caches make repeat selections cheap):

* NIF -> `MeshLibrary.model(path:)` (same cache the cell build uses) ->
  single-instance `RenderScene` at identity -> `SceneCamera.framing` over
  the captured `ModelBounds` -> `Renderer.renderOffscreen` -> CGImage.
* DDS -> `TexturePreviewScene`: camera-facing textured quad (height 1000
  units, width follows texture aspect, UV v=0 at +Z = image top, CCW toward
  the head-on -Y camera) lit with black sun + white ambient -> fragment
  output is the sampled texel unchanged. Preview shows exactly what the
  engine samples (TextureLoader upload, BCn + sRGB policy included).
  Output image texture-sized, capped 1024 on the long edge.
* Records -> `RecordTextDump` text, no image.
* Any failure -> `[ERROR]`/`[WARNING]` text in the pane, never a crash
  (mod-quirk rule). No Metal 4 GPU -> text-only previews.

`PreviewFrameImage` does the BGRA readback -> CGImage. Env-gated
`PreviewRealDataTests` (skips without `OPENSKY_DATA_ROOT`; pass it as
`TEST_RUNNER_OPENSKY_DATA_ROOT` through xcodebuild) drives catalog + both
preview paths against the local install and writes `logs/preview-dds.png` /
`logs/preview-nif.png` for human review.
