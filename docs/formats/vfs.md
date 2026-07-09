---
type: Subsystem
title: Virtual file system (resource lookup)
description: How OpenSky resolves game resource paths across loose files and BSA archives.
tags: [engine, vfs, archive, io]
timestamp: 2026-07-09T00:00:00Z
---

# Virtual file system

One lookup layer over the game data root (`VirtualFileSystem` +
`ArchiveLoadOrder`, `opensky/GameData/`). Callers ask for game-style resource
paths (`meshes\clutter\cup.nif`); VFS finds the bytes in loose files or BSA
archives. These are OpenSky's own rules, chosen to match observed game/modding
behavior; archive-load background from UESP "Skyrim Mod:Archive File Format"
(<https://en.uesp.net/wiki/Skyrim_Mod:Archive_File_Format>).

## Path keys

* Case-insensitive, separator-insensitive (`/` == `\`). Canonical key:
  lowercase + backslash separators + redundant separators stripped.
* Empty paths and `.` / `..` components rejected (`VFSError.invalidPath`) —
  game data never uses them; they could escape the data root.

## Resolution order (per lookup)

1. Loose file under `Data/` — modding convention: loose overrides archives.
2. Archives, last-opened wins — plugin archives override base archives.
3. Nothing -> `VFSError.fileNotFound`.

Loose lookup resolves each path component case-insensitively via lazily built
per-directory listings, so it also works on case-sensitive volumes. Listings
are cached and never invalidated: files added to `Data/` while the engine runs
are not seen.

## Archive open order (`ArchiveLoadOrder.resolve`)

First opened = lowest priority. Steps:

1. Ini resource lists: `sResourceArchiveList` then `sResourceArchiveList2`
   (comma-separated, `[Archive]` section; keys matched case-insensitively
   anywhere in the file). Ini source: `Skyrim.ini` in the install root if
   present, else the shipped `Skyrim_Default.ini`, else a built-in copy of the
   vanilla SSE 1.6 lists. (The real user ini lives in the Windows-side
   `My Games` folder — under Proton prefixes on this setup; not probed yet.)
2. Plugin-named archives: for every `.esm`/`.esp`/`.esl` in `Data/`, open
   `<plugin>.bsa` then `<plugin> - Textures.bsa` when present (SSE auto-load
   convention, UESP archive notes). Plugin order: official masters first
   (Skyrim, Update, Dawnguard, HearthFires, Dragonborn), remaining plugins
   alphabetically. Provisional until plugins.txt support lands
   ([roadmap](/todo.md) open question).

Names resolve case-insensitively against the on-disk `Data/` listing;
duplicates collapse to the first mention. Listed-but-absent archives log +
skip — vanilla ini lists `Skyrim - Patch.bsa`, which current installs no
longer ship (observed 2026-07-09 on SSE 1.6 install). `MarketplaceTextures.bsa`
matches no plugin and no ini entry -> never opened; the game only uses it for
Creation Club menu previews.

## Laziness + failure behavior

* Archives open (tables parsed) on first lookup, not at VFS construction;
  payload extraction was already lazy in the BSA parser ([BSA](/formats/bsa.md)).
* Malformed/unreadable archive -> `os_log` error once, slot skipped forever,
  lookup falls through to lower-priority sources. Never fatal (mod-quirk rule).
* Corrupt payload inside a healthy archive -> extraction error propagates to
  the caller; no fallthrough to shadowed copies (matches game behavior).

## Concurrency

`VirtualFileSystem` is `Sendable`; archive slots + directory listings sit
behind a `Mutex` (Synchronization). Archive table parse happens under the
lock — one-time cost per archive, first toucher pays.
