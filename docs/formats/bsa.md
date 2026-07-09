---
type: File Format
title: BSA Archive (v105, Skyrim SE)
description: On-disk layout of Skyrim SE .bsa archives and how OpenSky reads them.
tags: [format, archive, io, lz4]
timestamp: 2026-07-09T00:00:00Z
---

# BSA archive, version 105

Bethesda archive holding meshes, textures, sounds, scripts. Skyrim SE uses
version 105; LE used 104 (16-byte folder records, zlib) — not supported.

Reference: UESP "Skyrim Mod:Archive File Format"
(<https://en.uesp.net/wiki/Skyrim_Mod:Archive_File_Format>).
Impl: `opensky/Formats/BSA/BSAArchive.swift`. All integers little-endian.
Strings windows-1252 (vanilla is ASCII; mods carry high bytes).

## Header — 36 bytes at offset 0

| offset | type   | field                 | notes                          |
| ------ | ------ | --------------------- | ------------------------------ |
| 0x00   | char4  | fileId                | `BSA\0`                        |
| 0x04   | uint32 | version               | 105 (SSE)                      |
| 0x08   | uint32 | folderRecordOffset    | 36                             |
| 0x0C   | uint32 | archiveFlags          | bitfield, below                |
| 0x10   | uint32 | folderCount           |                                |
| 0x14   | uint32 | fileCount             |                                |
| 0x18   | uint32 | totalFolderNameLength | incl. nulls, excl. len prefix  |
| 0x1C   | uint32 | totalFileNameLength   | incl. nulls                    |
| 0x20   | uint32 | fileFlags             | content-type hints, unused     |

archiveFlags bits OpenSky cares about: 0x1 folder names present, 0x2 file
names present, 0x4 compressed by default, 0x100 embedded file names.
Observed vanilla: Interface 0x3, Misc 0x13, Meshes0 0x87, Textures0 0x107.

## Folder records — folderCount x 24 bytes

| offset | type   | field    | notes                                     |
| ------ | ------ | -------- | ----------------------------------------- |
| 0x00   | uint64 | nameHash | TES4 hash; unused (we key by names)       |
| 0x08   | uint32 | count    | files in folder                           |
| 0x0C   | uint32 | padding  |                                           |
| 0x10   | uint64 | offset   | file-record block + totalFileNameLength ! |

Quirk: stored offset includes `totalFileNameLength`; subtract before seeking.

## File record blocks — per folder, in folder-record order

`bzstring` folder name (uint8 length incl. trailing null, chars, null) when
flag 0x1, then `count` x 16-byte file records:

| offset | type   | field    | notes                                          |
| ------ | ------ | -------- | ---------------------------------------------- |
| 0x00   | uint64 | nameHash | unused                                         |
| 0x08   | uint32 | size     | bit 30 toggles archive default compression;    |
|        |        |          | real packed size = size & 0x3FFFFFFF           |
| 0x0C   | uint32 | offset   | absolute, to file data                         |

## File name block

fileCount zstrings (null-terminated), same order as records across folders.

## File data

At each record's offset, `packedSize` bytes total:

1. flag 0x100 set -> `bstring` (uint8 length, chars, no null) full path first;
   counts toward packedSize.
2. Uncompressed entry -> raw payload.
3. Compressed entry -> uint32 decompressedSize, then an LZ4 *frame*
   (magic 0x184D2204), typically linked blocks. OpenSky decodes with a
   clean-room LZ4 (`opensky/Formats/LZ4.swift`, specs:
   lz4 Block/Frame format docs on github.com/lz4/lz4). Decoding all blocks
   into one buffer makes linked-block matches resolve naturally. xxHash
   checksums are skipped; output validated against decompressedSize instead.

## Not implemented (yet)

* TES4 name-hash computation — lookups go through a name dictionary; needed
  only for archives without name tables (none in vanilla SSE).
* Version 104 (LE, zlib), Fallout 4 BA2.

## Verification

Unit tests: synthetic in-code fixtures (`openskyTests/BSAArchiveTests.swift`).
Runtime probe 2026-07-09 against vanilla SSE: Misc/Meshes0/Textures0/Interface
parse (14032/19443/5891/386 files); extracted NIFs start with
`Gamebryo File Format`, DDS with `DDS`, interface txt readable.
