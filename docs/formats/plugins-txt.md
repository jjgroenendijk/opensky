---
type: File Format
title: plugins.txt load order
description: The textfile load order Skyrim SE writes, how OpenSky finds it on macOS, and the plugin order it produces.
tags: [format, plugin, load-order, esm]
timestamp: 2026-08-10
---

# plugins.txt load order

`plugins.txt` is the plain-text list that decides which plugins a Skyrim Special Edition
session loads and in what order. Everything that merges records across plugins depends on
it: the last plugin to define a record wins, and a FormID's master index is an index into
the load order the plugin was compiled against. Before this file was read, OpenSky assumed
the five vanilla masters and nothing else, which is correct for a stock install and wrong
for every modded one (issue #73).

## Contents

* [Format](#format)
* [Where the file lives](#where-the-file-lives)
* [What OpenSky searches](#what-opensky-searches)
* [The order OpenSky builds](#the-order-opensky-builds)
* [Consequences elsewhere](#consequences-elsewhere)
* [Configuring it](#configuring-it)
* [Not modelled yet](#not-modelled-yet)
* [Code and tests](#code-and-tests)

## Format

One plugin file name per line, in load order — earliest line loads first and is overridden
by everything after it. Skyrim SE uses the *textfile-based* load order system, in which the
same file carries both the order and the enabled state:

| Line | Meaning |
| --- | --- |
| `*Mod.esp` | Active. The leading asterisk is the enable flag. |
| `Mod.esp` | Installed but switched off in the launcher. Not loaded. |
| `# text` | Comment. |
| empty | Ignored. |

Names are file names inside `Data/`, not paths. They are matched case-insensitively: what a
launcher or mod manager writes is not always the on-disk spelling, so OpenSky resolves each
line against the real directory listing and keeps the on-disk name. The file is UTF-8 in
practice, sometimes with a byte-order mark; OpenSky falls back to Windows-1252 for a file
that is not valid UTF-8 rather than losing the whole order to one accented mod name.

Reference for the enable-flag semantics and the textfile-based system: libloadorder,
<https://github.com/Ortham/libloadorder>, the load-order library LOOT and several mod
managers use. Verified against the file layout produced by those tools; OpenSky has not
observed a `plugins.txt` written by the game itself on this machine — see
[environment](/tools/environment.md).

The official masters are not toggleable and do not need to appear here. `Skyrim.esm` and
`Update.esm` in particular are loaded whether listed or not, and the game keeps the official
masters ahead of everything else regardless of where a line for one appears.

Creation Club content is listed separately, in `Skyrim.ccc` in the install root: one plain
name per line, no enable flag, active when the file is present in `Data/`.

## Where the file lives

The game writes it into its Windows per-user application data folder,
`%LOCALAPPDATA%\Skyrim Special Edition\plugins.txt`. There is no macOS-native Skyrim SE, so
on this platform that folder only exists inside whatever compatibility layer runs the game
— a Steam Proton prefix, a Wine prefix, a CrossOver or Whisky bottle — or not at all, when
the install was copied over from a Windows machine and never launched here.

## What OpenSky searches

In order, first hit wins:

1. `OPENSKY_PLUGINS_TXT` environment variable (tests, CLI runs).
2. `OpenSkyPluginsText` in the shared defaults domain `nl.jjgroenendijk.opensky`, written by
   Settings. Shared with the data root, so the app and `openskycli` agree.
3. `<install>/plugins.txt` — beside the game, where a hand-managed or portable layout puts
   it.
4. `~/Library/Application Support/Skyrim Special Edition/plugins.txt` — the native place to
   keep one on this platform.
5. `drive_c/users/<name>/AppData/Local/Skyrim Special Edition/plugins.txt` inside each
   Windows compatibility prefix that exists: the Steam Proton prefix beside the install
   (`<library>/steamapps/compatdata/489830/pfx`), `~/.wine`, and every bottle under
   `~/Library/Application Support/CrossOver/Bottles` or
   `~/Library/Containers/com.isaacmarovitz.Whisky/Bottles`. The shared `Public` profile is
   skipped.

A path set through source 1 or 2 that cannot be read is reported rather than ignored: a
configured path that is wrong is a mistake to surface, not a reason to quietly load a
different order. Finding nothing at all is not an error — it resolves to the vanilla
masters, which is what a stock install loads anyway.

## The order OpenSky builds

Lowest priority first:

1. The official masters — `Skyrim.esm`, `Update.esm`, `Dawnguard.esm`, `HearthFires.esm`,
   `Dragonborn.esm` — pinned in that order, filtered to what `Data/` holds. A DLC the user
   does not own is an ordinary install, not a problem to report.
2. `Skyrim.ccc` entries, in file order.
3. `*`-starred `plugins.txt` entries, in file order.

A name that appears twice takes its first position, so a master starred in `plugins.txt`
does not move behind the mods or load twice.

A `plugins.txt` entry that `Data/` does not hold is collected as missing and shown in the
Load Order panel instead of being dropped silently — that is normally a mod uninstalled
without updating the list. Entries from the other two sources are not reported: a master the
install lacks is an install without that DLC, and `Skyrim.ccc` is a catalogue of everything
Creation Club sells rather than a list of what is installed. On the stock install here, 70
of its 80 entries are absent.

## Consequences elsewhere

Archive priority follows plugin priority. `ArchiveLoadOrder` used to place plugin-named
`.bsa` files officials-first then alphabetically; it now walks the resolved plugin order, so
a mod's archive overrides the archives of every plugin loaded before it
([virtual file system](/formats/vfs.md)).

One deliberate deviation from the game: an archive whose plugin the load order does not name
is still opened, at the bottom of the list below everything the order does name. The game
would ignore it. Dropping it would mean that a machine where no `plugins.txt` can be found —
the common case on macOS — loses every mod archive it can read today, which is a worse
failure than loading one archive the game would not have.

## Configuring it

* **Settings** (Cmd+,) has a *Plugin Load Order (plugins.txt)* group beside the game data
  root: the resolved path, where it came from, *Choose…*, and *Search Automatically*.
* **Library > Load Order** in the sidebar lists the resolved order — position, plugin,
  whether the entry came from the pinned masters, `Skyrim.ccc`, or `plugins.txt`, and any
  listed-but-absent plugin — with the same two buttons and a *Reload*.

## Not modelled yet

* Light plugins (`.esl`) load into the shared `0xFE` master-index space. OpenSky orders them
  correctly but does not model that space, so the panel shows a plain 1-based position
  rather than the hex index a mod manager shows ([FormID](/formats/formid.md)).
* `loadorder.txt`, which some mod managers write beside `plugins.txt` to record the order of
  inactive plugins as well, is not read. Nothing OpenSky does needs it.
* The load order is resolved per query rather than held as session state; nothing yet needs
  to notice a `plugins.txt` that changes while the app is running.

## Code and tests

| Where | What |
| --- | --- |
| `opensky/Engine/GameData/PluginsTextLocator.swift` | Finding the file; the sources and prefixes above |
| `opensky/Engine/GameData/PluginLoadOrder.swift` | Parsing and the resolved order |
| `opensky/Engine/GameData/PluginLoadOrderReport.swift` | The rows and summary the UI shows |
| `opensky/App/LoadOrderViewController.swift` | Library > Load Order |
| `openskyTests/PluginsTextLocatorTests.swift` | Every search layout, over synthetic trees |
| `openskyTests/PluginLoadOrderTests.swift` | Enable flags, file order, dedupe, missing plugins |
| `openskyTests/PluginLoadOrderReportTests.swift` | The strings the panel shows |
| `openskyTests/ArchiveLoadOrderTests.swift` | Archive order following plugin order |
