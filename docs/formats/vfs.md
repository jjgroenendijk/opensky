---
type: Subsystem
title: Virtual file system (resource lookup)
description: How OpenSky finds a game resource path in loose files and BSA archives.
tags: [engine, vfs, archive, io]
---

# Virtual file system

The virtual file system (VFS) finds the bytes for a game path such as
`meshes\clutter\cup.nif`. The bytes can be a loose file or sit inside a BSA archive. These
rules are OpenSky's own. They copy the behavior players and modders see. Background: UESP
[Archive File Format](https://en.uesp.net/wiki/Skyrim_Mod:Archive_File_Format).

## Path keys

- Paths are case-insensitive. `/` and `\` are the same.
- An empty path, or a path with `.` or `..`, is rejected. Game data never uses them, and they
  could leave the data folder.

## Lookup order

1. A loose file under `Data/`. Loose files override archives, as mods expect.
2. Archives. The archive opened last wins.
3. Otherwise the file is not found.

Loose lookup matches each path part case-insensitively, so it works on case-sensitive disks
too. Folder listings are cached and never refreshed. A file added to `Data/` while OpenSky
runs is not seen.

## Archive open order

The first archive opened has the lowest priority.

1. The INI lists `sResourceArchiveList`, then `sResourceArchiveList2`, from `[Archive]`.
   `Skyrim_Default.ini` and `Skyrim.ini` in the install root are merged key by key. Only when
   neither file sets a key does OpenSky use its built-in copy of the vanilla SSE 1.6 lists.
2. Archives named after plugins. For each `.esm`, `.esp`, or `.esl` in `Data/`, OpenSky opens
   `<plugin>.bsa` and then `<plugin> - Textures.bsa` if they exist. Plugins follow the
   [plugin load order](/formats/plugins-txt.md), so a mod's archive overrides the archives of
   plugins before it. A plugin that the load order does not name keeps its archive at the
   bottom. That page explains why OpenSky differs from the game here.

Archive names match `Data/` case-insensitively. A name listed twice opens once.

Two cases seen on an SSE 1.6 install:

- The vanilla INI lists `Skyrim - Patch.bsa`, but current installs do not ship it. OpenSky
  logs this and skips it.
- `MarketplaceTextures.bsa` matches no plugin and no INI entry, so it never opens. The game
  uses it only for Creation Club menu previews.

## Errors

- An archive opens on its first lookup, not when the VFS is created.
- An archive that cannot be read logs one error and is skipped from then on. Lookups fall
  through to lower sources. This is never fatal, because mods can ship broken archives.
- A broken file inside a good archive is an error for the caller. The lookup does not fall
  through to a hidden copy. The game behaves the same way.
