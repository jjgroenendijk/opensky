---
type: Subsystem
title: Virtual file system (resource lookup)
description: How OpenSky finds a game resource path in loose files and BSA archives.
tags: [engine, vfs, archive, io]
---

# Virtual file system

The virtual file system (VFS) turns a game resource path, for example
`meshes\clutter\cup.nif`, into bytes. The bytes come from a loose file under `Data/` or from
a BSA archive. The code is in `Sources/OpenSkyGameData/`.

These rules are OpenSky's own. They match what the game and mod tools do. Background on
archive loading: UESP
[Archive File Format](https://en.uesp.net/wiki/Skyrim_Mod:Archive_File_Format).

## Path keys

- Paths ignore case, and `/` is the same as `\`. The key is lowercase with backslashes and
  no double separators.
- An empty path, or a path with a `.` or `..` part, is rejected. Game data never uses them,
  and they could leave the data root.

## Lookup order

1. A loose file under `Data/`. Mods expect loose files to win over archives.
2. The archives. The archive opened last wins, so plugin archives win over base archives.
3. Nothing found: the lookup fails.

Loose lookup matches each path part without case. This works on case-sensitive disks too.
The directory listings are cached and never refreshed. A file added to `Data/` while
OpenSky runs is not seen.

## Archive open order

The first archive opened has the lowest priority.

1. The INI lists `sResourceArchiveList`, then `sResourceArchiveList2`, from the `[Archive]`
   section. Both `Skyrim_Default.ini` and `Skyrim.ini` in the install root are read, and
   `Skyrim.ini` wins per key. When neither file has either key, OpenSky uses a built-in copy
   of the vanilla Skyrim SE 1.6 lists.
2. Archives named after plugins. For each `.esm`, `.esp`, or `.esl` in `Data/`, OpenSky
   opens `<plugin>.bsa`, then `<plugin> - Textures.bsa`, when they exist. UESP describes
   this automatic loading. Plugins go in [load order](/formats/plugins-txt.md), so a mod's
   archive wins over the archives of every plugin before it. A plugin not in the load order
   keeps its archive at the bottom of the list. The plugins.txt page explains why.

Archive names match the files in `Data/` without case. A name listed twice counts once. A
listed archive that does not exist is logged and skipped. For example, the vanilla INI lists
`Skyrim - Patch.bsa`, which current installs do not ship. `MarketplaceTextures.bsa` matches
no plugin and no INI entry, so it is never opened. The game uses it only for Creation Club
menu previews.

## Opening and errors

- An archive reads its tables on the first lookup, not when the VFS is built. File data is
  read only when asked for (see [BSA](/formats/bsa.md)).
- A broken archive is logged once and skipped from then on. Lookups fall through to the
  archives below it. This is never fatal, because mods sometimes ship broken files.
- A broken file inside a good archive gives an error to the caller. The lookup does not
  fall through to a lower copy. The game behaves the same way.
