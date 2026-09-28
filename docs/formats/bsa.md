---
type: File Format
title: BSA Archive (v105, Skyrim SE)
description: On-disk layout of Skyrim SE .bsa archives and how OpenSky reads them.
tags: [format, archive, io, lz4]
---

# BSA archive, version 105

A BSA archive holds meshes, textures, sounds, and scripts. Skyrim SE uses version 105. The
original Skyrim used version 104, with 16-byte folder records and zlib. OpenSky does not read
version 104 or Fallout 4 BA2 files.

Source: UESP [Archive File Format](https://en.uesp.net/wiki/Skyrim_Mod:Archive_File_Format).
All integers are little-endian.

Folder and file names use the [string decoding](/decisions/string-decoding.md) rules.
Vanilla names are ASCII. Mods can use UTF-8 or windows-1252. A name in the wrong encoding
decodes to odd characters, but the archive still opens. Lookups ignore case and separator
style on both sides, so such a name still finds itself.

## Header (36 bytes at offset 0)

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | char4 | fileId | `BSA\0` |
| 0x04 | uint32 | version | 105 |
| 0x08 | uint32 | folderRecordOffset | 36 |
| 0x0C | uint32 | archiveFlags | Bits below |
| 0x10 | uint32 | folderCount | |
| 0x14 | uint32 | fileCount | |
| 0x18 | uint32 | totalFolderNameLength | Includes nulls, not the length bytes |
| 0x1C | uint32 | totalFileNameLength | Includes nulls |
| 0x20 | uint32 | fileFlags | Content hints. Not used |

`archiveFlags` bits that OpenSky uses: `0x1` folder names present, `0x2` file names present,
`0x4` compressed by default, `0x100` file names embedded in the data.

Vanilla values: Interface `0x3`, Misc `0x13`, Meshes0 `0x87`, Textures0 `0x107`.

## Folder records (24 bytes each)

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | uint64 | nameHash | Not used. OpenSky looks up by name |
| 0x08 | uint32 | count | Files in the folder |
| 0x0C | uint32 | padding | |
| 0x10 | uint64 | offset | See the note below |

The stored offset includes `totalFileNameLength`. Subtract it before you seek.

## File record blocks

One block per folder, in folder-record order. If flag `0x1` is set, the block starts with the
folder name as a `bzstring`: a uint8 length (null included), the characters, and a null.
Then come `count` file records of 16 bytes:

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | uint64 | nameHash | Not used |
| 0x08 | uint32 | size | Bit 30 flips the default compression. Size is `size & 0x3FFFFFFF` |
| 0x0C | uint32 | offset | Absolute offset of the file data |

## File name block

`fileCount` zstrings, in the same order as the file records.

## File data

At each record's offset there are `size` bytes:

1. If flag `0x100` is set: the full path as a `bstring` (uint8 length, characters, no null).
   It counts toward `size`.
2. An uncompressed file: the raw bytes.
3. A compressed file: a uint32 decompressed size, then an LZ4 frame (magic `0x184D2204`).

OpenSky parses the LZ4 frame itself, from the public LZ4 block and frame specifications.
Independent blocks (`FLG` bit 5 set) go to Apple's `COMPRESSION_LZ4_RAW`. Linked blocks,
where a match can reach back into earlier blocks, use OpenSky's own Swift decoder. xxHash
checksums are skipped. The output size is checked against the decompressed size instead.

In the vanilla mesh and texture archives, every compressed file is an LZ4 frame. About 98%
use independent blocks (`FLG 0x60`). The rest use linked blocks (`FLG 0x40`).

## Not implemented

- Computing the TES4 name hash. It is only needed for archives without name tables. Vanilla
  SSE has none.
