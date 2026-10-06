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
audio in AAC for Best performance; every preset stores ALAC for now (see Audio), so a Best
performance cache is larger than its estimate:

| Preset | Estimated cache | Default limit |
| --- | --- | --- |
| Best performance | 13 GiB | 15 GiB |
| Balanced | 22 GiB | 25 GiB |
| Highest quality | 26 GiB | 29 GiB |

## Presets

The preset sets how each texture group is stored. Meshes, collision, and animation are the
same in every preset. A texture's group comes from its file name: `_n` and `_msn` are normal
maps; `_s`, `_g`, `_e`, `_em`, `_m`, `_p`, `_b`, and `_sk` are data maps; the rest are color.

| Preset | Color | Normal | Data | Quality limit |
| --- | --- | --- | --- | --- |
| Highest quality | shipped | shipped | shipped | lossless |
| Balanced | shipped | ASTC 4x4 | shipped | PSNR 40 dB, normal angle 2 degrees |
| Best performance | ASTC 6x6 | ASTC 6x6 | ASTC 8x8 | PSNR 30 dB |

ASTC (Adaptive Scalable Texture Compression) is a block format that Apple GPUs read
directly. A 4x4 block keeps more detail than a 6x6 or 8x8 block, and uses more memory.
"Shipped" keeps the BC blocks and mip levels from the archive.

A texture that is converted is first decoded by the GPU, one mip level at a time, and then
encoded with astcenc ([astcenc decision](/decisions/astcenc.md)) at its fastest effort. The
GPU decode is the reference because it is the image the renderer shows. The CPU DDS decoder
cannot read BC5 and BC7, so it cannot be the reference.

The preset lives in the shared settings store. The graphics presets set it later; until then
it is its own setting.

## Audio

A short sound effect is stored as ALAC (Apple Lossless) in a CAF file. ALAC is lossless, so a
cached sound plays the same samples as the original. Sounds longer than 30 seconds, such as
music, are not cached: they keep the streaming decode.

AAC is smaller but lossy. It is used only after a listening check finds no audible
difference. That check has not been done, so every preset stores ALAC.

## Read path

The engine opens the cache when the game loads, if the cache is turned on in Settings and
the folder passes the location check. Each loader asks the cache first:

1. Look up the entry for the providing file and path.
2. On a hit, decode the payload. Textures upload their ready blocks, meshes and collision
   rebuild their models, animation returns the shipped file, and audio decodes the CAF.
3. On a miss, load the original file.
4. On a stale, unreadable, or undecodable entry, log a `[WARNING]`, delete the entry, load
   the original file, and mark the asset for a rebuild.

A cached mesh or collision model must equal the direct decode exactly. So some files are not
cached: skinned character meshes with skin data, meshes with particle systems, and collision
with constraints. They always load from the archive.

## Build

A build plans one item per archive file that a converter accepts, then converts the items in
parallel on a utility-priority task. It skips an item whose entry is already current. Each
converted payload is written as one entry. When a converter does not store a file, the build
writes an entry with an empty payload. That entry tells the engine to load the original, and
it lets a check count the file as current. A build can be cancelled between items; the
entries written so far stay valid.

A check reads only the entry headers. It reports the cache as current, partly built, not
built, or stale. Stale wins, because a changed install or preset needs a rebuild.

`openskycli asset-cache build` runs a build without the app ([CLI](/tools/cli.md)).
