---
type: Subsystem
title: Asset cache
description: How OpenSky stores optimised copies of the base game's assets outside the
  archives, how an entry is keyed and goes stale, the texture quality search, and the
  legal limits on the folder.
tags: [engine, assets, cache, loading]
---

# Asset cache

The app calls this feature "Asset Optimisation", and the code calls it the asset cache. It
is a folder of converted copies of the game's assets. A converted copy loads
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
can choose another folder on the launcher's Asset Optimisation page. The page warns before a
conversion when:

- the folder is on an external disk, because reads from it may be slower than from the
  internal SSD, and that takes away part of the cache's gain;
- the folder is on a network disk;
- the disk has less free space than the conversion needs. The estimate is the source bytes
  of the files that wait, times the output ratio of their kind ("Texture quality").

## Entries

Each entry is one file: `<kind>/<xx>/<hash>.osac`. `<kind>` is `textures`, `meshes`, or
`collision`. The `animation` and `audio` kinds are retired: their folder names and kind
numbers stay reserved, and `asset-cache measure` still writes them. `<hash>` is the 64-bit
FNV-1a hash of the source's origin and VFS path, and `<xx>` is its first two hex digits, so no
folder gets too many files.

The origin is the file that provides the asset: an archive name, or `loose` for a file
under `Data/`. A mod that overrides a file has another origin, so it gets its own entry.

### Entry layout

All integers are little-endian.

| Field | Size | Meaning |
| --- | --- | --- |
| magic | 4 | `OSAC` |
| header version | 2 | 1 |
| kind | 1 | 1 texture, 2 mesh, 3 collision, 4 animation, 5 audio |
| output | 1 | Textures only: how the texture was stored (below). 0 for other kinds |
| converter version | 4 | The version of the converter that built the payload |
| source size | 8 | Size of the source asset in bytes |
| source time | 8 | Modification time of the providing file, seconds since 1970 |
| source hash | 8 | FNV-1a of the source bytes, or 0 when not known |
| origin | 2 + n | Length, then UTF-8 |
| path | 2 + n | Length, then UTF-8 |
| payload length | 8 | Bytes of payload |
| padding | 0 to 15 | Zeros, so the payload starts on a 16-byte boundary |
| payload | n | The converted asset |

The output byte of a texture: 0 keeps the shipped blocks, 1 to 3 is the quality target of
High, Medium, or Low, and `0x10` plus a format number is a forced format. The top three
bits hold the size limit as `log2(side) - 7`, or 0 for no limit.

### When an entry is stale

A stale entry is never used. The engine loads the original file instead. An entry is stale
when:

- the source's size, modification time, or hash changed (a hash of 0 counts as unknown);
- the converter that would build it now has a newer version;
- it is a texture built for another texture output. A quality change leaves meshes and
  collision current.

A file that is shorter or longer than its header says is unreadable, and is treated like a
stale entry.

### Writes

A write goes to a temporary file in `tmp/` and is then renamed onto the entry path. A rename
on one disk is atomic, so a crash leaves the old entry or the new one, never half of one.
Opening the cache deletes `tmp/`, which removes the leftovers of an interrupted write.

## Size

The folder has no size limit: it holds at most one entry per archive file, so its size
follows from the install and the texture quality. A conversion checks the free space first.
The store can still drop the least recently used entries past a limit, for tools that set
one. A hit sets the entry file's modification date to now, but not again within an hour,
because each write is a disk update and it made up a quarter of a warm lookup.

## Texture quality

The texture quality sets how each texture is stored. Meshes and collision are always stored
ready to use and identical to the game. A texture's group comes from its file name: `_n` and
`_msn` are normal maps; `_s`, `_g`, `_e`, `_em`, `_m`, `_p`, `_b`, and `_sk` are data maps;
the rest are colour.

| Quality | Colour PSNR | Normal angle | Cut-out alpha PSNR |
| --- | --- | --- | --- |
| Original | shipped blocks | shipped blocks | shipped blocks |
| High | 42 dB | 2 degrees | 46 dB |
| Medium | 38 dB | 3.5 degrees | 42 dB |
| Low | 34 dB | 6 degrees | 38 dB |

Each quality other than Original is a target, not a format. For one texture the conversion
tries ASTC 8x8, 6x6, 5x5, and 4x4, smallest first, and keeps the first that meets the target.
When none does, the texture keeps its shipped blocks. The search never tries a format with
more bits per pixel than the shipped one, so a BC1 texture (4 bits per pixel) never becomes
ASTC 4x4 (8 bits per pixel). A texture of 256 pixels or less on its long side keeps its
shipped blocks: the saving is too small to pay for the search.

ASTC (Adaptive Scalable Texture Compression) is a block format that Apple GPUs read
directly. A larger block keeps less detail and uses less memory.

The measure compares the top mip level. The GPU decodes every shipped level once; that image
is the reference, because it is the image the renderer shows. The CPU DDS decoder cannot read
BC5 and BC7, so it cannot be the reference. A candidate is encoded with astcenc
([astcenc decision](/decisions/astcenc.md)) at its fastest effort and decoded again by
astcenc on the CPU, which matches the GPU decode to within one step. Colour uses the RGB
PSNR. A normal map uses the mean angle between the decoded normals. A colour texture with
transparent texels has cut-out alpha, where a wrong edge shows as holes, so its alpha uses
the stricter target. The winning format then encodes every level.

"Show details" on the page has a format menu for each group: Automatic follows the quality,
Shipped keeps the BC blocks, and an ASTC size forces that format. It also shows a size limit,
which drops the top mip levels of larger textures.

The output ratios that the space check uses, in optimised bytes per source byte, are
estimates until a whole base-game conversion per quality measures them: textures 1.0
(Original), 0.8 (High), 0.6 (Medium), 0.45 (Low); meshes 1.6; collision 0.9.

A graphics preset on the Graphics page also sets the texture quality: Ultra is Original,
High is High, Medium is Medium, and Low is Low.

## Audio

The cache does not store audio or animation. A lossless ALAC copy decodes at the same CPU
cost as the shipped xWMA, so it loads no faster ("Where the cache helps"). The game reads every
sound and animation from the archives, and a cache opened after an earlier build deletes the
`audio` and `animation` folders. [Asset cache audio](/engine/asset-cache-audio.md) has the
measurement that rules out lossy AAC copies.

## Per-kind settings

Each kind the cache stores has its own setting in the shared settings store, all on by
default. A kind that is off:

- is not converted by a build, and a check does not count it, so the cache reads as current
  when every kind that is on is built;
- is read from the archives, without a cache lookup;
- keeps its entries on disk, so turning it on again needs no rebuild.

In a running game, World > Asset Optimisation turns the reads of one kind off and on for a
comparison, without a reload; that change is not saved. `openskycli asset-optimisation` and
the benchmarks read the same settings, and `--kinds textures,meshes,collision` overrides
them.

Audio and animation have no switch, because the cache does not store them.

## Read path

The engine opens the cache when the game loads, if the cache is turned on in Settings and
the folder passes the location check. Each loader asks the cache first:

1. Look up the entry for the providing file and path.
2. On a hit, decode the payload. Textures upload their ready blocks, meshes and collision
   rebuild their models.
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
it lets a check count the file as current. A conversion can be cancelled between items; the
entries written so far stay valid. The game starts while files wait: a waiting file loads
from the archives.

A check reads only the entry headers. It reports the cache as current, partly built, not
built, or stale. Stale wins, because a changed install or texture output needs a new
conversion. The launcher shows the result as Ready, Needs conversion, or Not converted.

`openskycli asset-optimisation build` runs a conversion without the app
([CLI](/tools/cli.md)). The app starts the same conversion from the launcher's Asset
Optimisation page. In a running game, World > Asset Optimisation turns reads off and on,
shows the hits and misses per kind, and shows the entries of one path.

## Direct GPU loading

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
path. The page calls this "Direct GPU loading", with one switch for textures, one for
meshes, and one for "All disks". In a running game, World > Asset Optimisation has the same
switches and shows the textures, bytes, and time of the last cell load.
`openskycli benchmark --asset-optimisation --direct-load` measures it.

A texture read needs scratch memory, in requests from 16 KiB to 8 MiB. The queue's own
allocator keeps that memory for the life of the queue, which added about 80 MB to the peak
footprint of the fly route. The fast loader passes its own allocator, which frees each
scratch buffer when its read ends. Median of three cold `bench --fly-path --fast-load` runs
(2026-10-07, run directory `.logs/fast-load-footprint/20261007T024924Z`): peak 1269 MB with
the queue's allocator, 1189 MB with ours, and 1186 MB for the CPU upload. The frames until
the stream settles did not change (391 and 393).

On a slow external disk this does not hold. More reads wait at once, so the queue asks for
more scratch buffers. The device keeps the memory of every scratch buffer the queue used, even
after our allocator released it: `currentAllocatedSize` grows by the total scratch size, and
the benchmark block ended 377 MiB above the CPU upload. Neither a cap on reads in flight, a new
queue per batch, private textures, nor scratch memory that OpenSky owns changed this. On that
disk the fast loader also saved no time: 4.62 s cold against 4.60 s for the CPU upload
(2026-10-08, USB SSD, run directories under `.logs/fast-load-*`). So the fast loader reads
only from a cache folder on an internal volume. From an external volume each texture takes
the CPU path, and World > Asset Optimisation counts it under "External disk". "All disks"
turns this rule off for a measurement.

Each entry is read without compression. An LZ4 copy is 30% smaller, but the measurement
below shows that it saves almost no time cold, needs twice the CPU time, and is twice as
slow warm.

## Where the cache helps

The cache stores a kind only when it makes that kind faster to load, or when it serves a
Metal 4 loading path. A kind that does neither costs build time and disk space and gives
nothing back, so the game reads it from the archives and offers no setting for it.

`openskycli asset-cache measure` checks this per kind. It takes up to 300 archive files of
each kind, spread evenly over the sorted paths, builds their entries, and loads them twice
each way: cold (the files dropped from the page cache) and warm. The archive path is the
engine's own read and parse: archive read and decompression, then DDS parse, NIF parse and
model or collision build, the shipped animation bytes, or the full audio decode. The cache
path is entry lookup, read, and decode. A GPU upload is the same for both, so neither times
it.

Both sides must read from the same disk, or the result measures the disks and not the
cache. So the cache folder sits on the same external USB SSD as the game data.

Result on an Apple M1 with 16 GB, shipped texture blocks, two runs (2026-10-07, run directory
`.logs/asset-cache-measure/20261007T045926Z`). Times are for the whole sample, in ms:

| Kind | Files | Archive cold | Cache cold | Archive warm | Cache warm | Advice |
| --- | --- | --- | --- | --- | --- | --- |
| Textures | 299 | 702-705 | 398-402 | 181-182 | 34 | cache |
| Meshes | 243 | 346-348 | 185-187 | 175 | 19 | cache |
| Collision | 297 | 337-338 | 89-92 | 126 | 12 | cache |
| Animation | 300 | 104-111 | 99-102 | 4 | 12 | archives |
| Audio | 291 | 1130-1210 | 863-872 | 679-772 | 687-688 | archives |

Warm CPU time equals warm wall time within 1 ms, so the warm columns are also the CPU cost.

- Textures, meshes, and collision load 5 to 11 times faster warm and about 2 to 4 times
  faster cold. The cache removes the parse and the decompression.
- Animation was the shipped file, copied out of the archive. Reading it from the archive
  costs 0.01 ms per file warm, less than the cache's lookup of an entry file (0.04 ms). Cold, the two
  are even.
- Audio was stored as ALAC, and decoding ALAC costs as much CPU time as decoding the shipped
  xWMA. Warm, the two are even. Cold, it saves about 0.8 ms per sound, only because the
  ALAC files of the shipped WAV sounds are smaller.

The rule: a kind is worth caching when the cache at least halves its warm load time and is
not slower cold, or when it feeds a Metal 4 path. Textures, meshes, and collision pass.
Animation and audio fail both tests: no gain, and the GPU never reads them. So the cache no
longer stores them, and the settings offer no switch for them.

A warm load reads from memory, so the warm result does not depend on the disk. A faster or
slower disk changes only the cold numbers. The two kinds that fail, fail on the warm test,
so the answer holds on any Mac and there is no per-Mac advice.

### Metal 4 paths

- Textures: each entry holds the mip levels in the layout a texture needs, so Metal fast
  resource loading reads them straight into GPU memory ("Direct GPU loading" above).
  Sparse texture streaming (#881) can map single mip levels from the same layout.
- Meshes: an entry holds ready vertex and index blocks, so fast resource loading can read
  them straight into GPU buffers ([fast mesh loading](/engine/fast-mesh-loading.md)).
- Collision, animation, and audio are CPU data.
- Compiled render pipelines (#875) are the Metal compiler's output, not a game asset. They
  may share the cache folder, but the asset kinds and their settings do not cover them.

## Measurements

Measured on 2026-10-07 on an Apple M1 with 16 GB and macOS 27, with the Release `openskycli`.
The game data and every cache are on the same external USB SSD, so each table compares the
archives with the cache and not two disks. Each cold run first drops the files from the page
cache.

The benchmark block, `openskycli benchmark`, reads 293 textures and makes 378 mesh loads. One
run each,
from `make asset-cache-bench CACHE=<folder on the game data disk>` (run directory
`.logs/asset-cache-bench/20261007T042624Z`):

"Fixed ASTC" forces colour and normal maps to ASTC 6x6 and data maps to ASTC 8x8, with the
format menus under "Show details".

| Run | Cold load | GPU memory | Peak RSS | Image against archives |
| --- | --- | --- | --- | --- |
| Archives | 5383 ms | 563 MiB | 1194 MiB | - |
| Loose copies | 4658 ms | 563 MiB | 878 MiB | - |
| Original | 4566 ms | 563 MiB | 925 MiB | identical |
| Original, direct GPU loading | 4644 ms | 940 MiB | 1080 MiB | identical |
| Fixed ASTC | 4224 ms | 442 MiB | 772 MiB | PSNR 38.9 dB |

GPU memory counts all allocations at 2560x1600, render targets included. The loose copies cover
every file, while the cache keeps skinned and particle meshes (125 of the 378 loads) in
the archives, so the two cold loads are not a fair pair. On this disk, direct GPU loading does
not make the block's cold load faster, and it holds 377 MiB more GPU memory at its peak.

Loading the block's 293 textures (365 MiB) as one batch, `asset-cache io-bench`, wall time
and CPU time, same run:

| Method | Cold | Warm |
| --- | --- | --- |
| Archive | 1619 ms, 638 ms CPU | 487 ms |
| Cache, CPU upload | 698 ms, 220 ms CPU | 105 ms |
| Cache, fast loading | 721 ms, 342 ms CPU | 92 ms |
| Cache, fast loading of LZ4 copies | 697 ms, 464 ms CPU | 153 ms |

Cold, the disk limits every cache method, so fast loading gains nothing over the CPU
upload. Warm, it is 12% faster.

Streaming, `bench --fly-path --footprint-cap-mb 4096`, median of three cold runs, with a
cache of the route's assets (run directory `.logs/stream-worst-frame/20261007T042841Z`):

| Run | Frames until the stream settles | Worst frame | Peak footprint |
| --- | --- | --- | --- |
| Archives | 538 | 19.4 ms | 1270 MB |
| Original | 484 | 16.5 ms | 1229 MB |
| Original, direct GPU loading | 481 | 16.0 ms | 1362 MB |

The worst frame is the distant LOD swap in every run. A waypoint settles only when its distant
ring is in. Without that rule, a slow archive run ended its legs before the ring arrived, so it
never measured the swap and its worst frame looked 5 ms better than the cache's.

With the cache on the internal SSD, the fast loader's peak footprint matched the CPU upload
(see Direct GPU loading). On the slower external disk it is 133 MB higher.

A full base game build, 92392 files, to the external disk, with 8 build tasks on 8 cores. These
builds still held audio and animation (0.87 GiB, 66 s of CPU time):

| Texture output | Build time | Size |
| --- | --- | --- |
| Original | 233 s | 21.3 GiB |
| Fixed ASTC | 1186 s | 11.3 GiB |
