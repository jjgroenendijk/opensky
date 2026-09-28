---
type: Tool
title: Main-app asset browser
description: The Library > Asset Browser destination - browsing the install's archives and records,
  the load-order reference record inspector and what it resolves, NIF and DDS previews rendered by
  the engine, the screenshot button, and the Settings data root flow.
tags: [tool, gui, dev, preview, rendering]
---

# Main-app asset browser

`Library > Asset Browser` browses the local install and previews one asset at a time. It shows what
the parsers and the renderer see, with no second render pipeline. It is developer tooling, not game
UI.

## In the shell

The browser is a full-content destination ([app UI](/tools/app-ui.md)). Selecting it covers the game
view, which is hidden and paused, so it costs nothing. Going back to a World destination resumes it,
and the streamed scene is still in memory, so the switch is instant. The browser is built on first
selection and kept, so the loaded catalog, filter, selection, and warm caches survive switching away
and Settings reloads. Preview images have low compression resistance, so a large bitmap never
resizes the window.

The browse and preview model has no AppKit and lives in `opensky/Engine/Preview/`, so it is tested
without a window and shared with the CLI. Only the AppKit shells live under `opensky/App/`.

## Browsing

The sidebar has a category popup (meshes, textures, `Skyrim.esm` records, load-order reference
records, all files), a filter field, a table, and a status line. The detail pane shows a preview
image and monospaced info text.

- The file list is every archive entry plus a headers-only walk of every `Skyrim.esm` record,
  flattened to rows. The filter is a case-insensitive substring, and `/` matches the `\` separator.
- Loading opens every archive and walks every record, which takes seconds, so it runs off the main
  thread with a loading status. Filtering the record list runs off the main thread too, and a
  generation counter drops stale results.
- A missing or broken plugin leaves file browsing working, with a note in the status line.
- The data root comes from the [game data locator](/engine/game-data-locator.md). A missing install
  is a message in the window. The app still launches, with no alert loop.

## Reference records

`Reference records (load order)` has a plugin selector, which filters by the plugin whose valid
definition won, and a record type selector: `KYWD`, `FLST`, `LCTN`, `LCRT`, `ECZN`, `AACT`, `COLL`,
`DOBJ`, the magic families (`MGEF`, `SPEL`, `SCRL`, `ENCH`, `SHOU`, `WOOP`, `LVSP`, `DUAL`, `EQUP`),
`AVIF`, `PERK`, `FACT`, `RELA`, and `ASTP`. Rows sort by editor ID and name the winning plugin and
the load-order-independent resolved form ID, so an override never looks as if it came from its
defining master.

The inspector text is shared by the app and `openskycli record`. It shows the winning plugin and
identity, the records that use a keyword, flattened form list membership, location parent chains,
resolved encounter zone and collision layer links, and the merged default object table. The keyword
reverse index is built once, during the catalog load.

For the magic families:

- `MGEF`: name, archetype, casting type, delivery, base cost, the related and resistance actor values
  by name, and keywords. `ALCH` and `INGR` summaries name their effects through the same store.
- `SPEL` and `SCRL`: the header, then one line per effect with the effect's name, magnitude, area,
  duration, and computed cost, under a total that says whether it was set by hand or calculated,
  and how many entries did not resolve.
- `ENCH`: the same table, the header's links named through their stores, and the base enchantment
  chain, one line per link, guarded against a cycle a mod could author.
- `SHOU`: the words, each named through `WOOP`, its spell through `SPEL`, and the recovery time.
- `WOOP`, `LVSP`, and `EQUP`: the word and translation, the leveled entries, and the parent slots and
  hands.
- `DUAL`: the inherit-scale flags. Its five art links print as raw form IDs, because nothing indexes
  `PROJ`, `EXPL`, `EFSH`, `ARTO`, or `IPDS` yet, and a form ID is more honest than an invented name.

A link that resolves to nothing is prefixed `[UNRESOLVED]` instead of being dropped, and a null link
says `NULL`. So a spell whose effect left the load order reads as broken, not as short. In the plain
`Records (Skyrim.esm)` category, the tables still print, by raw form ID and without costs, because
the costs live in the `MGEF` records.

## Previews

- A NIF goes through the same mesh cache the cell build uses, becomes a one-model scene framed on its
  bounds, and is rendered offscreen.
- A DDS draws on a quad facing the camera, 1000 units high with the texture's aspect, lit by a black
  sun and white ambient, so the output is the sampled texel unchanged. The preview shows exactly
  what the engine samples, upload rules and sRGB included. The image is capped at 1024 on the long
  edge.
- A record shows the text dump, with no image.
- Any failure is `[ERROR]` or `[WARNING]` text in the pane, never a crash. With no Metal 4 GPU, all
  previews are text.

## Screenshot

The toolbar's Screenshot button asks for a PNG path, then renders the live camera and the current
streamed scene offscreen at the drawable's pixel size. App chrome is not in it. The button works only
while a World destination is in front, because asset previews already render on their own. A failure
shows an error sheet. The app and CLI share one PNG readback.

## Settings

Settings (Cmd+,) shows the resolved data root and where it came from, noting when the environment
variable wins over the saved choice. Choose picks a folder, checks it, and saves it in the shared
defaults, so the CLI sees it too. An invalid folder shows a red note and changes nothing. Use Default
clears the choice and falls back to the Steam path.

Either change runs the locator again and hands the shell a new game controller (a new renderer and
streamer over the new root). The shell rebuilds inspector panels, reloads the cached browser in
place, and selects the current destination again, whichever one is in front. A failed locate shows a
message in every destination, with no modal alert and no relaunch.
