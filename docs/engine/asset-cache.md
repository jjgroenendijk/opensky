---
type: Subsystem
title: Asset cache
description: How OpenSky stores converted copies of the base game's assets outside the
  archives, how an entry is keyed and goes stale, and the legal limits on the cache folder.
tags: [engine, assets, cache, loading]
---

# Asset cache

The asset cache is a folder of converted copies of the game's assets. A converted copy loads
with almost no work: it is not inside an archive, and it is already in the layout the
engine uses. The engine reads the cache when an entry is current, and the original file
otherwise. So the cache can always be deleted.

## Legal limits

The cache holds content derived from the user's install, so it is game content.

- It lives on the user's disk, never in the repository, the app bundle, or the build output.
- OpenSky refuses a cache folder inside the game install, around the game install, or inside
  any git checkout. A git checkout is refused because a file there can be committed by
  mistake.
- The game install stays read-only. The cache is written only into its own folder.

## Location

The default folder is `~/Library/Caches/OpenSky/AssetCache`, on the internal disk. The user
can choose another folder in Settings. OpenSky warns before a build when:

- the folder is on an external disk, because reads from it may be slower than from the
  internal SSD, and that takes away part of the cache's gain;
- the folder is on a network disk;
- the disk has less free space than the preset's estimated cache size.

## Entries

Each entry is one file: `<kind>/<xx>/<hash>.osac`. `<kind>` is `textures`, `meshes`,
`collision`, `animation`, or `audio`. `<hash>` is the 64-bit FNV-1a hash of the source's
origin and VFS path, and `<xx>` is its first two hex digits, so no folder gets too many
files.

The origin is the file that provides the asset: an archive name, or `loose` for a file
under `Data/`. A mod that overrides a file has another origin, so it gets its own entry.

### Entry layout

All integers are little-endian.

| Field | Size | Meaning |
| --- | --- | --- |
| magic | 4 | `OSAC` |
| header version | 2 | 1 |
| kind | 1 | 1 texture, 2 mesh, 3 collision, 4 animation, 5 audio |
| preset | 1 | 0 Best performance, 1 Balanced, 2 Highest quality |
| converter version | 4 | The version of the converter that built the payload |
| source size | 8 | Size of the source asset in bytes |
| source time | 8 | Modification time of the providing file, seconds since 1970 |
| source hash | 8 | FNV-1a of the source bytes, or 0 when not known |
| origin | 2 + n | Length, then UTF-8 |
| path | 2 + n | Length, then UTF-8 |
| payload length | 8 | Bytes of payload |
| padding | 0 to 15 | Zeros, so the payload starts on a 16-byte boundary |
| payload | n | The converted asset |

### When an entry is stale

A stale entry is never used. The engine loads the original file instead. An entry is stale
when:

- the source's size, modification time, or hash changed (a hash of 0 counts as unknown);
- the converter that would build it now has a newer version;
- it was built for another quality preset.

A file that is shorter or longer than its header says is unreadable, and is treated like a
stale entry.

### Writes

A write goes to a temporary file in `tmp/` and is then renamed onto the entry path. A rename
on one disk is atomic, so a crash leaves the old entry or the new one, never half of one.
Opening the cache deletes `tmp/`, which removes the leftovers of an interrupted write.

## Size limit

The cache keeps the least recently used entries out when it grows past its limit. A hit sets
the entry file's modification date to now, so the oldest modification date is the least
recently used entry.

The default limit fits the whole base-game cache for the chosen preset with a tenth to spare.
The estimates come from the format comparison census of the base game. The census counted
audio in AAC for Best performance; every preset stores ALAC for now, so a Best
performance cache is larger than its estimate:

| Preset | Estimated cache | Default limit |
| --- | --- | --- |
| Best performance | 13 GiB | 15 GiB |
| Balanced | 22 GiB | 25 GiB |
| Highest quality | 26 GiB | 29 GiB |
