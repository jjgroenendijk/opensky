---
type: Tool
title: Main-app asset browser
description: Library > Asset Browser destination in the unified sidebar shell — engine VFS
  and Skyrim.esm browsing, offscreen-rendered NIF/DDS previews, toolbar World screenshots.
tags: [tool, gui, dev, preview, rendering]
timestamp: 2026-08-13T00:00:00Z
---

# Main-app asset browser

## Contents

- Sidebar shell
- UI + browse model
- M18 reference-record inspectors
- Menu + Settings
- Preview pipeline
- Verification
- M19 magic record families

`Library > Asset Browser` sidebar destination: browse local install assets and preview
one at a time — parser/renderer's eye view beside World, with no second product or
render pipeline. Browser remains dev tooling, not shipped game UI.

## Sidebar shell

One window, one unified sidebar (`AppShellViewController`, issue #98 PR 2 — see
[app-ui](/tools/app-ui.md) for the shell anatomy). Asset Browser is the `Library`
section's full-content destination: selecting it covers the game view, which is
paused and hidden while covered (`ShellContentViewController.setGameCovered`) so
it costs nothing; returning to a World destination unhides and resumes it, and
the streamed scene is still in memory, so the switch is instant. The browser
controller is built lazily on first selection and cached forever — loaded catalog,
filter, selection, and warm renderer caches survive destination round trips and
Settings reloads. Selected preview images have low
compression resistance -> intrinsic bitmap size never resizes the window. Build via
`make build`.

The window toolbar (`unifiedCompact`) carries the `Screenshot…` button. It opens
`NSSavePanel` for a PNG destination, then asks `GameViewController` to synchronously
offscreen-render the live free-fly camera + current streamed scene at drawable pixel
size (`ScreenshotCoordinator`). App chrome is excluded. The button is enabled only
while a World destination is frontmost: asset previews already render individually in
the detail pane. Capture failure appears as an action-scoped error sheet. App + CLI
share `FrameScreenshot` for BGRA readback + PNG encoding.

App-only AppKit shells live under `opensky/App/` (`PreviewViewController`,
`PreviewDetailBuilder`, `SettingsWindowController`, and the shell + panel framework
under `opensky/App/Shell/`); `openskycli` does not synchronize that folder, so they never
enter the CLI build. Browse/preview model stays AppKit-free under `opensky/Engine/Preview/`. The
sidebar destinations + control panels are built on the shared UI framework — see
[app-ui](/tools/app-ui.md).

## UI + browse model

Programmatic AppKit (repo precedent, no storyboard): split view. Sidebar =
category popup (Meshes/.nif, Textures/.dds, Skyrim.esm records, load-order reference
records, All files) + filter field + lazy `NSTableView` + status line. Detail pane =
preview image + monospace info text. Data root comes from the
[game data locator](/engine/game-data-locator.md) chain; missing install ->
in-window message, app still launches (no crash, no alert loop).

## M18 reference-record inspectors

`Reference records (load order)` adds two selectors above the existing table. The plugin
selector filters by the plugin whose structurally valid definition won; the record-type
selector covers KYWD, FLST, LCTN, LCRT, ECZN, AACT, COLL and DOBJ, and M19 added the nine
magic families below. Rows sort by editor ID
and name the winning plugin plus the load-order-independent `ResolvedFormID`, so an override
is never presented as though it came from its defining master.

`ReferenceRecordCatalog` owns these queries over one `RecordIndex`. The index also collects
the seven item families already decoded by `RecordTextDump`, allowing the inspector to build
the KYWD reverse-use view once during the off-main catalog load. `ReferenceRecordInspector`
owns the detail text shared by the app and `openskycli record`: winning plugin and identity,
keyword users, flattened form-list membership, location parent chains with keyword names,
resolved encounter-zone and collision-layer links, and the merged default-object table.
Null links say `NULL`; a dangling identity is prefixed `[UNRESOLVED]` instead of disappearing
or becoming an unexplained number.

The original `Records (Skyrim.esm)` category remains available. Selecting an item there now
passes its actual source-plugin context into the same inspector, so existing item summaries
show resolved KWDA editor IDs. The CLI gets the same decoded and resolved summaries without
an AppKit dependency.

## Menu + Settings

Main menu: app menu (Settings… Cmd+, / Quit) + standard Edit menu (copy/paste
for the filter field). Settings window
(`SettingsWindowController`) shows the resolved data root path + source
note (env override flagged as winning over the stored choice) and two actions:

- Choose… — `NSOpenPanel` folder pick, validated + persisted via
  `GameDataLocator.saveUserChoice` (shared defaults domain, so CLI sees it too).
  Invalid folder -> red note, stored setting untouched.
- Use Default — `clearUserChoice`, falls back to the Steam default path.

Either change makes `AppDelegate` re-run `GameDataLocator`, then hand the shell a fresh
`GameViewController` (new renderer + streamer over the new root) plus a new
`FullContentContext`; the shell rebuilds inspector panels, reloads the cached browser in
place (`FullContentReloadable` -> `PreviewViewController.reload(root:errorMessage:)`),
and re-applies the current sidebar selection — the flow works regardless of which
destination is frontmost. Current catalog drops, new catalog loads off-main;
catalog-load generation drops stale in-flight work (same pattern as filtering). Failed
re-locate -> in-window message in every destination, no modal alert or relaunch needed.

Browse logic is AppKit-free in `opensky/Engine/Preview/` so it unit-tests without a
window (`PreviewCatalogTests`, `RecordTextDumpTests`,
`TexturePreviewSceneTests`):

- `PreviewCatalog` — archive entries (`VirtualFileSystem.archiveEntries()`)
  plus a headers-only `ESMWalk` over every Skyrim.esm record (~870k)
  flattened to filterable rows ("TYPE FORMID" for records). Filter:
  case-insensitive substring, `/` matches the canonical `\` separator.
  Load runs off the main thread (opening every archive + the record walk
  takes seconds -> loading status); filtering the record list runs off-main
  too, a generation counter drops stale results. Missing/broken esm ->
  file browsing still works, note in the status line.
- `RecordTextDump` — one-record dump (header line, decoded
  WRLD/CELL/STAT/REFR view, field list capped at 64 with per-type tail
  summary). The CLI `record` command prints the same string — single impl.
- `AssetInfoText` — NIF container/model summary + DDS header/mip chain text
  (same content the CLI `nif`/`dds` commands print).
- `ESMWalk` moved `openskycli/` -> `opensky/Engine/Formats/ESM/` (shared by CLI +
  preview; malformed-group warning now goes to os_log instead of stderr).

## Preview pipeline

Selection -> `PreviewDetailBuilder` (main-app side, main thread; MeshLibrary /
TextureLibrary caches make repeat selections cheap):

- NIF -> `MeshLibrary.model(path:)` (same cache the cell build uses) ->
  single-instance `RenderScene` at identity -> `SceneCamera.framing` over
  the captured `ModelBounds` -> `Renderer.renderOffscreen` -> CGImage.
- DDS -> `TexturePreviewScene`: camera-facing textured quad (height 1000
  units, width follows texture aspect, UV v=0 at +Z = image top, CCW toward
  the head-on -Y camera) lit with black sun + white ambient -> fragment
  output is the sampled texel unchanged. Preview shows exactly what the
  engine samples (TextureLoader upload, BCn + sRGB policy included).
  Output image texture-sized, capped 1024 on the long edge.
- Records -> `RecordTextDump` text, no image.
- Any failure -> `[ERROR]`/`[WARNING]` text in the pane, never a crash
  (mod-quirk rule). No Metal 4 GPU -> text-only previews.

`FrameScreenshot` does shared BGRA readback -> CGImage/PNG. Env-gated
`PreviewRealDataTests` (skips without `OPENSKY_DATA_ROOT`; pass it as
`TEST_RUNNER_OPENSKY_DATA_ROOT` through xcodebuild) drives catalog + both preview paths
against local install and writes `logs/preview-dds.png` / `logs/preview-nif.png` for human
review. Env-gated `OpenSkyUITests` captures full World + Asset Browser windows to runner
temp; verification copies them to `logs/app-world.png` / `logs/app-asset-browser.png`.

## Verification

```text
Milestone: M18
Sidebar path: Library > Asset Browser > Reference records (load order)
Destination id: Destination-assetBrowser
Controls exercised: AssetCategory, AssetPluginControl, AssetRecordTypeControl, AssetFilter,
AssetTable
Readout: AssetRecordInspectorStatsLabel
Deterministic tests: M18AcceptancePanelTests, ReferenceRecordCatalogTests,
PreviewCatalogTests, DestinationRegistryTests
Local A/B (optional, never committed): none
```

## M19 magic record families

M19 extends the same surface with nine families rather than a browser of its own, because
the load-order record surface M18 built already answers the questions a magic record raises:
which plugin won, what the links resolve to, and what is dangling. The record-type selector
gains `MGEF — Magic effects`, `SPEL — Spells`, `SCRL — Scrolls`, `ENCH — Enchantments`,
`SHOU — Shouts`, `WOOP — Words of power`, `LVSP — Leveled spells`, `DUAL — Dual cast data`
and `EQUP — Equip slots`, and `ReferenceRecordInspector` builds the magic stores once during
the off-main catalog load so a summary can name what a record points at.

What each summary resolves, all of it read-only:

- **MGEF** — display name, archetype, casting type, delivery, base cost, the related and
  resistance actor values by vanilla name, and the keyword editor IDs. ALCH and INGR
  summaries name their resolved effects through the same store.
- **SPEL** and **SCRL** — the SPIT header, then the effect table: one line per entry with
  the MGEF's display name, magnitude, area, duration and the entry's computed cost, under a
  spell cost that states whether it was authored manually or auto-calculated and how many
  entries went unresolved.
- **ENCH** — the same effect table, the ENIT header with the base enchantment and worn
  restrictions named through their own stores, and — as a resolved-detail block —
  the base-enchantment chain, one line per link, guarded against a mod-authored cycle.
- **SHOU** — the header links plus the SNAM word run, each word named through WOOP and its
  spell through SPEL, with the recovery time.
- **WOOP** — the word and its translation. **LVSP** — the leveled entries by level and
  count, named through the spell store. **DUAL** — the DATA inherit-scale flags, with the
  five art links left as raw FormIDs because nothing indexes PROJ, EXPL, EFSH, ARTO or IPDS
  yet and printing a FormID honestly beats inventing a name. **EQUP** — the parent slots by
  name and the hands the slot resolves to.

A link that resolves to nothing is prefixed `[UNRESOLVED]` rather than dropped, and a null
one says `NULL`, so a spell whose effect left the load order reads as a broken spell instead
of a short one. Without a magic context — the plain `Records (Skyrim.esm)` category — the
tables still print, by raw FormID and without costs, because the base costs live in the MGEF
records.

`openskycli record <formid>` prints the identical string; the formatter is one
implementation in `opensky/Engine/Preview/RecordTextDumpMagic.swift` and
`RecordTextDumpShouts.swift`, split across two files only to stay inside the lint
file-length cap.

The M19 acceptance record for the whole milestone, this surface included, lives in
[magic](/engine/magic.md); `M19AcceptancePanelTests` pins the nine families to the
record-type selector.
