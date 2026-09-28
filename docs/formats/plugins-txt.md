---
type: File Format
title: plugins.txt load order
description: The load-order text file Skyrim SE uses, where OpenSky looks for it on macOS, and
  the plugin order it builds.
tags: [format, plugin, load-order, esm]
---

# plugins.txt load order

`plugins.txt` is a text file. It says which plugins load and in what order. When two plugins
define the same record, the later plugin wins. So every merge across plugins depends on this
file.

## Format

One plugin file name per line. The first line loads first, and every later line overrides it.
Skyrim SE keeps both the order and the on/off state in this one file:

| Line | Meaning |
| --- | --- |
| `*Mod.esp` | Active. The `*` turns the plugin on |
| `Mod.esp` | Installed but turned off. Not loaded |
| `# text` | Comment |
| empty | Ignored |

Names are file names in `Data/`, not paths. They match case-insensitively, because launchers
and mod managers do not always write the real spelling. OpenSky keeps the spelling from the
disk. The file is normally UTF-8, sometimes with a byte-order mark. If it is not valid UTF-8,
OpenSky reads it as windows-1252. One accented mod name should not break the whole list.

Source for the `*` flag and this file system: [libloadorder](https://github.com/Ortham/libloadorder),
the load-order library that LOOT and several mod managers use. OpenSky has only seen files
written by those tools, not one written by the game (see [environment](/tools/environment.md)).

The official masters do not need a line. `Skyrim.esm` and `Update.esm` load even when they
are not listed. The game always loads the official masters before everything else.

Creation Club content is listed in `Skyrim.ccc` in the install root. It is one name per line,
with no `*` flag. An entry is active when its file is in `Data/`.

## Where the file lives

The game writes it to `%LOCALAPPDATA%\Skyrim Special Edition\plugins.txt`, a Windows folder.
There is no macOS version of Skyrim SE. So on a Mac that folder exists only inside the tool
that runs the game (Steam Proton, Wine, CrossOver, or Whisky), or not at all when the install
was copied from a Windows PC.

## Where OpenSky looks

The first file found wins:

1. The `OPENSKY_PLUGINS_TXT` environment variable. Used by tests and the CLI.
2. `OpenSkyPluginsText` in the defaults domain `nl.jjgroenendijk.opensky`, set in Settings.
   The app and `openskycli` share it.
3. `<install>/plugins.txt`, beside the game.
4. `~/Library/Application Support/Skyrim Special Edition/plugins.txt`.
5. `drive_c/users/<name>/AppData/Local/Skyrim Special Edition/plugins.txt` inside each
   Windows prefix that exists: the Steam Proton prefix
   (`<library>/steamapps/compatdata/489830/pfx`), `~/.wine`, and every bottle under
   `~/Library/Application Support/CrossOver/Bottles` or
   `~/Library/Containers/com.isaacmarovitz.Whisky/Bottles`. The `Public` profile is skipped.

A path set in step 1 or 2 that cannot be read is an error. A wrong setting should be shown,
not replaced by another file. Finding no file is not an error. Then only the vanilla masters
load, which is what a stock install loads.

## The order OpenSky builds

From lowest to highest priority:

1. The official masters, in this order: `Skyrim.esm`, `Update.esm`, `Dawnguard.esm`,
   `HearthFires.esm`, `Dragonborn.esm`. Only those in `Data/`. A missing DLC is normal.
2. `Skyrim.ccc` entries, in file order.
3. Active (`*`) `plugins.txt` entries, in file order.

A name that appears twice keeps its first place. So a master with a `*` line does not move
behind the mods or load twice.

A `plugins.txt` entry that is not in `Data/` is listed as missing in the Load Order panel.
Usually a mod was removed without updating the list. Missing entries from the other two
sources are not reported. `Skyrim.ccc` lists everything Creation Club sells, not what is
installed. On a stock install most of its entries are absent.

## Archives follow the plugin order

Archive priority follows plugin priority. A mod's archive overrides the archives of every
plugin before it (see [virtual file system](/formats/vfs.md)).

OpenSky differs from the game in one case. An archive whose plugin is not in the load order
still opens, at the lowest priority. The game would ignore it. But on a Mac there is often
no `plugins.txt` at all. Ignoring those archives would then drop every mod archive. Loading
one extra archive is the smaller problem.

## Settings and sidebar

- Settings (Cmd+,) has a "Plugin Load Order (plugins.txt)" group: the path, its source,
  "Choose...", and "Search Automatically".
- Library > Load Order lists the order: position, plugin, source (official master,
  `Skyrim.ccc`, or `plugins.txt`), and missing plugins. It has the same two buttons and
  "Reload".

## Not modeled yet

- Light plugins (`.esl`) load into the shared `0xFE` index space. OpenSky orders them
  correctly but does not model that space. The panel shows a plain position, not the hex
  index a mod manager shows (see [FormID](/formats/formid.md)).
- `loadorder.txt` is not read. Some mod managers use it to store the order of inactive
  plugins. OpenSky does not need that.
- The order is read on each request. A `plugins.txt` that changes while the app runs is not
  noticed.
