---
type: Tool
title: Main-app asset browser
description: Library > Asset Browser destination in the unified sidebar shell — engine VFS
  and Skyrim.esm browsing, offscreen-rendered NIF/DDS previews, toolbar World screenshots.
tags: [tool, gui, dev, preview, rendering]
timestamp: 2026-07-23T00:00:00Z
---

# Main-app asset browser

`Library > Asset Browser` sidebar destination: browse local install assets and preview
one at a time — parser/renderer's eye view beside World, with no second product or
render pipeline. Browser remains dev tooling, not shipped game UI.

## Sidebar shell

One window, one unified sidebar (`AppShellViewController`, issue #98 PR 2 — see
[app-ui](/tools/app-ui.md) for the shell anatomy). Asset Browser is the `Library`
section's full-content destination: selecting it covers the always-live game view,
which keeps drawing at a low rate so streaming stays warm; returning to a World
destination is instant. The browser controller is built lazily on first selection and
cached forever — loaded catalog, filter, selection, and warm renderer caches survive
destination round trips and Settings reloads. Selected preview images have low
compression resistance -> intrinsic bitmap size never resizes the window. Build via
`make build`.

The window toolbar (`unifiedCompact`) carries the `Screenshot…` button. It opens
`NSSavePanel` for a PNG destination, then asks `GameViewController` to synchronously
offscreen-render the live free-fly camera + current streamed scene at drawable pixel
size (`ScreenshotCoordinator`). App chrome is excluded. The button is enabled only
while a World destination is frontmost: asset previews already render individually in
the detail pane. Capture failure appears as an action-scoped error sheet. App + CLI
share `FrameScreenshot` for BGRA readback + PNG encoding.

App-only AppKit shells live under `opensky/` (`PreviewViewController`,
`PreviewDetailBuilder`, `SettingsWindowController`, and the shell + panel framework
under `opensky/Shell/`) and are excluded from `openskycli` by its synchronized-group
exception set. Browse/preview model stays AppKit-free under `opensky/Preview/`. The
sidebar destinations + control panels are built on the shared UI framework — see
[app-ui](/tools/app-ui.md).

## UI + browse model

Programmatic AppKit (repo precedent, no storyboard): split view. Sidebar =
category popup (Meshes/.nif, Textures/.dds, Records, All files) + filter
field + lazy `NSTableView` + status line. Detail pane = preview image +
monospace info text. Data root comes from the
[game data locator](/engine/game-data-locator.md) chain; missing install ->
in-window message, app still launches (no crash, no alert loop).

## Menu + Settings

Main menu: app menu (Settings… Cmd+, / Quit) + standard Edit menu (copy/paste
for the filter field). Settings window
(`SettingsWindowController`) shows the resolved data root path + source
note (env override flagged as winning over the stored choice) and two actions:

* Choose… — `NSOpenPanel` folder pick, validated + persisted via
  `GameDataLocator.saveUserChoice` (shared defaults domain, so CLI sees it too).
  Invalid folder -> red note, stored setting untouched.
* Use Default — `clearUserChoice`, falls back to the Steam default path.

Either change makes `AppDelegate` re-run `GameDataLocator`, then hand the shell a fresh
`GameViewController` (new renderer + streamer over the new root) plus a new
`FullContentContext`; the shell rebuilds inspector panels, reloads the cached browser in
place (`FullContentReloadable` -> `PreviewViewController.reload(root:errorMessage:)`),
and re-applies the current sidebar selection — the flow works regardless of which
destination is frontmost. Current catalog drops, new catalog loads off-main;
catalog-load generation drops stale in-flight work (same pattern as filtering). Failed
re-locate -> in-window message in every destination, no modal alert or relaunch needed.

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

Selection -> `PreviewDetailBuilder` (main-app side, main thread; MeshLibrary /
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

`FrameScreenshot` does shared BGRA readback -> CGImage/PNG. Env-gated
`PreviewRealDataTests` (skips without `OPENSKY_DATA_ROOT`; pass it as
`TEST_RUNNER_OPENSKY_DATA_ROOT` through xcodebuild) drives catalog + both preview paths
against local install and writes `logs/preview-dds.png` / `logs/preview-nif.png` for human
review. Env-gated `OpenSkyUITests` captures full World + Asset Browser windows to runner
temp; verification copies them to `logs/app-world.png` / `logs/app-asset-browser.png`.
