---
type: File Format
title: BSA Archive (v105, Skyrim SE)
description: On-disk layout of Skyrim SE .bsa archives and how OpenSky reads them.
tags: [format, archive, io, lz4]
---

# BSA archive, version 105

A BSA archive holds meshes, textures, sounds, and scripts. Skyrim SE uses version 105. The
original Skyrim used version 104, with 16-byte folder records and zlib compression. OpenSky
does not read version 104 or Fallout 4 BA2 archives.

Reference: UESP
[Archive File Format](https://en.uesp.net/wiki/Skyrim_Mod:Archive_File_Format). All
integers are little-endian.

Folder and file names follow the [string decoding](/decisions/string-decoding.md) policy.
Vanilla names are ASCII. Mod names may be UTF-8 or windows-1252. A name in the wrong
encoding gives wrong characters, but the archive still opens. Lookups ignore case and
separators, so such a name still finds itself.

## Header: 36 bytes at offset 0

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | char4 | fileId | `BSA\0` |
| 0x04 | uint32 | version | 105 |
| 0x08 | uint32 | folderRecordOffset | 36 |
| 0x0C | uint32 | archiveFlags | Bits below |
| 0x10 | uint32 | folderCount | |
| 0x14 | uint32 | fileCount | |
| 0x18 | uint32 | totalFolderNameLength | With nulls, without length bytes |
| 0x1C | uint32 | totalFileNameLength | With nulls |
| 0x20 | uint32 | fileFlags | Content hints. Not used |

`archiveFlags` bits OpenSky uses: `0x1` folder names present, `0x2` file names present,
`0x4` compressed by default, `0x100` file names stored before the data. Vanilla values:
Interface `0x3`, Misc `0x13`, Meshes0 `0x87`, Textures0 `0x107`.

## Folder records: folderCount x 24 bytes

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | uint64 | nameHash | Not used. OpenSky looks up by name |
| 0x08 | uint32 | count | Files in the folder |
| 0x0C | uint32 | padding | |
| 0x10 | uint64 | offset | See below |

The stored offset includes `totalFileNameLength`. Subtract it before seeking.

## File record blocks

One block per folder, in folder-record order. If flag `0x1` is set, the block starts with
the folder name as a `bzstring`: a uint8 length (with the null), the characters, and a null.
Then come `count` file records of 16 bytes:

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | uint64 | nameHash | Not used |
| 0x08 | uint32 | size | Bit 30 flips the archive's compression default |
| 0x0C | uint32 | offset | Absolute offset of the file data |

The packed size is `size & 0x3FFFFFFF`.

## File name block

`fileCount` zstrings, in the same order as the file records across all folders.

## File data

At each record's offset there are `packedSize` bytes:

1. If flag `0x100` is set: first the full path as a `bstring` (uint8 length, characters,
   no null). It counts toward `packedSize`.
2. An uncompressed file: the raw bytes.
3. A compressed file: a uint32 decompressed size, then an LZ4 frame (magic `0x184D2204`).

OpenSky reads the LZ4 frame itself, from the public LZ4 Block and Frame format
specifications. Independent blocks (`FLG` bit 5 set) go to Apple's `COMPRESSION_LZ4_RAW`.
Linked blocks use OpenSky's own Swift decoder, because a match may reach back into an
earlier block. The xxHash checksums are skipped. The output size is checked against the
decompressed size instead.

In the vanilla mesh and texture archives, every compressed file is an LZ4 frame. Most use
independent blocks (`FLG 0x60`). About 1,000 use linked blocks (`FLG 0x40`).

## Not supported

- Computing the TES4 name hash. OpenSky looks files up by name. The hash is needed only
  for archives without name tables, and vanilla has none.
