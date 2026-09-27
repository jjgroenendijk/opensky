---
type: File Format
title: plugins.txt load order
description: The text-file load order Skyrim SE uses, where OpenSky looks for it on macOS,
  and the plugin order it builds.
tags: [format, plugin, load-order, esm]
---

# plugins.txt load order

`plugins.txt` is a plain text list. It says which plugins load and in what order. When two
plugins define the same record, the later one wins. So every merge of records across
plugins depends on this file.

Reference: [libloadorder](https://github.com/Ortham/libloadorder), the load order library
that LOOT and several mod managers use. It describes the enable flag and the text-file load
order system. OpenSky has not seen a `plugins.txt` that the game itself wrote on this
machine. See [environment](/tools/environment.md).

## Format

One plugin file name per line. The first line loads first, and every later line wins over
it. Skyrim SE uses the "text-file based" system: the same file holds the order and the
on/off state.

| Line | Meaning |
| --- | --- |
| `*Mod.esp` | Active. The `*` is the enable flag |
| `Mod.esp` | Installed but turned off. Not loaded |
| `# text` | Comment |
| empty | Ignored |

Names are file names inside `Data/`, not paths. They match without case, because tools do
not always write the spelling on disk. OpenSky keeps the spelling on disk. The file is
normally UTF-8, sometimes with a byte-order mark. If it is not valid UTF-8, OpenSky reads it
as windows-1252. One accented mod name then does not lose the whole order.

The official masters cannot be turned off and do not need to be listed. The game always
loads `Skyrim.esm` and `Update.esm`, and always keeps the official masters first.

Creation Club content is listed in `Skyrim.ccc` in the install root. It has one name per
line and no enable flag. An entry is active when its file is in `Data/`.

## Where the file lives

The game writes it to `%LOCALAPPDATA%\Skyrim Special Edition\plugins.txt` on Windows. There
is no macOS version of Skyrim SE. So on a Mac this folder exists only inside a Windows
compatibility layer (Proton, Wine, CrossOver, or Whisky). It does not exist at all when the
install was copied from a Windows machine.

## Where OpenSky looks

In this order. The first file found wins.

1. The `OPENSKY_PLUGINS_TXT` environment variable. Used by tests and CLI runs.
2. `OpenSkyPluginsText` in the defaults domain `nl.jjgroenendijk.opensky`, written by
   Settings. The app and `openskycli` share this domain.
3. `<install>/plugins.txt`, next to the game.
4. `~/Library/Application Support/Skyrim Special Edition/plugins.txt`.
5. `drive_c/users/<name>/AppData/Local/Skyrim Special Edition/plugins.txt` inside each
   Windows prefix that exists: the Steam Proton prefix next to the install
   (`<library>/steamapps/compatdata/489830/pfx`), `~/.wine`, and every bottle under
   `~/Library/Application Support/CrossOver/Bottles` or
   `~/Library/Containers/com.isaacmarovitz.Whisky/Bottles`. The shared `Public` user is
   skipped.

If source 1 or 2 names a file that cannot be read, OpenSky reports it. A wrong configured
path is a mistake to show, not a reason to load a different order. Finding no file is not
an error. OpenSky then loads the vanilla masters, as a stock install does.

## The order OpenSky builds

Lowest priority first:

1. The official masters, in this order: `Skyrim.esm`, `Update.esm`, `Dawnguard.esm`,
   `HearthFires.esm`, `Dragonborn.esm`. Only those in `Data/`. A missing DLC is normal.
2. `Skyrim.ccc` entries, in file order.
3. Active (`*`) `plugins.txt` entries, in file order.

A name listed twice keeps its first position. So a master that is also starred in
`plugins.txt` does not move behind the mods.

A `plugins.txt` entry with no file in `Data/` is shown as missing in the Load Order panel.
This usually means a mod was removed without updating the list. Missing entries from the
other two sources are not shown. A missing master means the DLC is not owned. `Skyrim.ccc`
lists everything Creation Club sells, not what is installed; on a stock install most of its
entries are absent.

## Archive order

Archives follow plugin order, so a mod's archive wins over the archives of every plugin
before it. See [virtual file system](/formats/vfs.md).

OpenSky differs from the game in one case. An archive whose plugin is not in the load order
still opens, at the bottom of the list. The game would ignore it. On macOS OpenSky often
finds no `plugins.txt`. Ignoring these archives would then drop every mod archive, which is
worse than loading one archive the game would skip.

## Settings

- Settings (Cmd+,) has a "Plugin Load Order (plugins.txt)" group: the path in use, where it
  came from, "Choose...", and "Search Automatically".
- Library > Load Order lists the order: position, plugin, source (masters, `Skyrim.ccc`, or
  `plugins.txt`), and missing plugins. It has the same buttons and "Reload".

## Not supported

- Light plugins (`.esl`) load into the shared `0xFE` index space. OpenSky orders them
  correctly but does not model that space. The panel shows a plain position, not the hex
  index a mod manager shows. See [FormID](/formats/formid.md).
- `loadorder.txt`, which some mod managers write to also order inactive plugins. OpenSky
  does not need it.
- A `plugins.txt` that changes while the app runs. OpenSky reads the order when asked and
  does not watch the file.
