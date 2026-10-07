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

AAC is smaller but lossy, so it may only be used where it makes no audible difference.
`openskycli audio aac-check` measures that per sound category instead of a listening test:

- Categories, from the folder: `music`, `voice` (`sound\fx\voc`; dialogue is `.fuz` and is
  not cached), `ambience` (`sound\fx\amb*`), and `effects` (the rest).
- Each sampled sound is encoded as AAC at 96 kbps per channel, decoded, and compared with
  the original. The measure is the band spectral distortion (SD): per 1024-sample frame, the
  root mean square of the level difference in the 24 Bark critical bands (Zwicker 1961).
  Frames quieter than -50 dBFS are skipped, and a band more than 60 dB below the loudest
  band of its frame is masked.
- A sound is transparent by the Paliwal and Atal (1993) rule: mean SD under 1 dB, under 2 %
  of frames from 2 to 4 dB, and no frame over 4 dB. A category may use AAC only when every
  sampled sound is transparent.
- AAC defines a fixed set of sampling rates. A few vanilla sounds use 22000 Hz, so they stay
  ALAC in any category.

Result, 400 sounds per category at most (2026-10-07, run directory
`.logs/aac-check/20261007T020728Z`):

| Category | Sounds | Transparent | Mean SD | Worst sound |
| --- | --- | --- | --- | --- |
| Effects | 399 | 387 | 0.33 dB | 1.23 dB |
| Voice | 122 | 120 | 0.28 dB | 0.51 dB |
| Ambience | 387 | 269 | 0.47 dB | 2.47 dB |
| Music | 116 | 115 | 0.10 dB | 0.35 dB |

No category passes, so every preset stores ALAC. The failing sounds fail on a few frames at
a sharp attack, where AAC spreads noise before the attack (pre-echo). At 128 kbps per channel
the counts barely change (run `.logs/aac-check/20261007T021023Z`), so a higher rate is not
the fix. The preset table sets the storage per category, so a later pass needs only a table
change.

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

`openskycli asset-cache build` runs a build without the app ([CLI](/tools/cli.md)). The app
starts the same build from the launcher's Asset Cache page. In a running game, World > Asset
Cache turns cache reads off and on, shows the hits and misses per kind, and shows the entries
of one path.

## Fast resource loading

Metal fast resource loading (MTLIO) reads file bytes straight into a texture on the GPU
side. The CPU does not copy the bytes and does not wait for each read. A cached texture
suits it: its mip levels sit in the entry file in the layout the texture needs.

The fast loader runs only during a cell build:

1. The cell build opens a batch.
2. Each cached texture becomes an empty texture, and one IO command buffer queues a read of
   each mip level from the entry file.
3. At the end of the cell build, the batch commits the buffer and waits for it. Only then is
   the cell handed to the renderer, so a frame never shows a texture that is still loading.
4. If the buffer fails, every texture of the batch is filled on the CPU from the same entry.

A texture loaded outside a cell build, or a texture with no current entry, takes the CPU
path. The setting "Fast texture loading" turns the fast loader on and off. In a running
game, World > Asset Cache has the same switch and shows the textures, bytes, and time of
the last cell load. `openskycli benchmark --asset-cache --fast-load` measures it.

Each entry is read without compression. An LZ4 copy is 30% smaller, but the measurement
below shows that it saves almost no time cold, needs twice the CPU time, and is twice as
slow warm.

## Measurements

Measured on 2026-10-06 on an Apple Silicon Mac with macOS 27, with the Release `openskycli`.
`make asset-cache-bench` runs the block measurement. Each cold run first drops the files
from the page cache.

The benchmark block, `openskycli benchmark`, reads 293 textures and 226 meshes. The caches
are on the internal SSD:

| Run | Cold load | GPU memory | Peak RSS | Image against archives |
| --- | --- | --- | --- | --- |
| Archives | 5350 ms | 442 MiB | 1194 MiB | - |
| Loose copies | 3936 ms | 442 MiB | 878 MiB | - |
| Highest quality | 4472 ms | 442 MiB | 897 MiB | identical |
| Highest quality, fast loading | 4010 ms | 602 MiB | 690 MiB | identical |
| Balanced | 4483 ms | 442 MiB | 897 MiB | identical |
| Best performance | 4201 ms | 342 MiB | 768 MiB | PSNR 38.4 dB |

The block holds no normal maps, so Balanced stores the same files as Highest quality. The
loose copies cover every file, while the cache keeps skinned and particle meshes in the
archives, so the two cold loads are not a fair pair.

Loading the block's 293 textures (365 MiB) as one batch, `asset-cache io-bench`, wall time
and CPU time:

| Method | Cold, internal SSD | Warm | Cold, external USB disk |
| --- | --- | --- | --- |
| Archive | 1554 ms, 624 ms CPU | 486 ms | 1599 ms |
| Cache, CPU upload | 610 ms, 153 ms CPU | 88 ms | 684 ms |
| Cache, fast loading | 243 ms, 130 ms CPU | 74 ms | 705 ms |
| Cache, fast loading of LZ4 copies | 228 ms, 242 ms CPU | 148 ms | 687 ms |

Streaming, `bench --fly-path --footprint-cap-mb 4096`, median of three cold runs, with a
cache of the route's assets on the internal SSD (2026-10-07, run directory
`.logs/stream-worst-frame/20261007T023809Z`):

| Run | Frames until the stream settles | Worst frame | Peak footprint |
| --- | --- | --- | --- |
| Archives | 524 | 17.4 ms | 1270 MB |
| Highest quality | 482 | 17.7 ms | 1200 MB |
| Highest quality, fast loading | 432 | 16.0 ms | 1242 MB |

The worst frame is the distant LOD swap in every run. A waypoint settles only when its distant
ring is in. Without that rule, a slow archive run ended its legs before the ring arrived, so it
never measured the swap and its worst frame looked 5 ms better than the cache's.

A full base game build, 92392 files, to the external disk, with 8 build tasks on 8 cores:

| Preset | Build time | Size |
| --- | --- | --- |
| Highest quality | 233 s | 21.3 GiB |
| Balanced | 549 s | 21.2 GiB |
| Best performance | 1186 s | 11.3 GiB |
