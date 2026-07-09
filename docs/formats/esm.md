---
type: File Format
title: ESM/ESP Plugin Container (Skyrim SE)
description: Record/group/field container layout of SSE plugin files and how OpenSky walks it.
tags: [format, plugin, esm, esp, records, io, zlib]
timestamp: 2026-07-09T00:00:00Z
---

# ESM/ESP plugin container, Skyrim SE

Plugin files (`.esm`, `.esp`, `.esl`) hold all game data as records grouped into
GRUP containers. This page covers the container layer only: record/group/field
framing, compression, traversal. Per-record semantics (WRLD, CELL, REFR, ...)
get own pages as decoders land.

Reference: UESP "Skyrim Mod:Mod File Format"
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>).
Impl: `opensky/Formats/ESM/` (`ESMFile`, `ESMGroup`, `ESMRecord`, `ESMField`).
All integers little-endian. Type codes are 4 ASCII bytes (`FourCC.swift`).

## File shape

One TES4 record (plugin info) followed by top-level GRUPs, back to back to EOF.
Skyrim.esm: 118 top groups; order per UESP list (engine dependence unknown).
Top groups hold records matching their label; only CELL, WRLD, DIAL nest child
groups after their records.

## Record — 24-byte header + data

| offset | type   | field     | notes                                  |
| ------ | ------ | --------- | -------------------------------------- |
| 0x00   | char4  | type      | e.g. `WRLD`; `GRUP` means group, below |
| 0x04   | uint32 | dataSize  | data only, header NOT included         |
| 0x08   | uint32 | flags     | bitfield, below                        |
| 0x0C   | uint32 | formID    | see [FormID](/formats/formid.md)       |
| 0x10   | uint16 | timestamp | SSE packs 0bYYYYYYYMMMMDDDDD           |
| 0x12   | uint16 | vcInfo    | CK version-control user ids            |
| 0x14   | uint16 | version   | form version: 43 = LE, 44 = SSE        |
| 0x16   | uint16 | unknown   | 0-15 observed                          |

Oblivion-era headers are 20 bytes — not supported.

Flags OpenSky interprets (`ESMRecord.Flags`; many bits are per-type overloads,
see UESP table): 0x1 TES4=ESM, 0x20 deleted, 0x80 TES4=localized (strings in
`.strings` tables), 0x200 TES4=ESL, 0x1000 ignored, 0x40000 data compressed.

Compressed record data: uint32 decompressedSize, then a zlib (RFC 1950) stream
filling the rest of dataSize. Decoded via Apple Compression
(`Formats/Zlib.swift`): COMPRESSION_ZLIB handles the raw deflate payload, so
the 2-byte zlib header is validated (CMF/FLG) and stripped; trailing adler32
not verified, output length checked against decompressedSize instead.
Sanity cap 256 MB against malformed size fields.

## Group (GRUP) — 24-byte header

| offset | type    | field     | notes                            |
| ------ | ------- | --------- | -------------------------------- |
| 0x00   | char4   | `GRUP`    |                                  |
| 0x04   | uint32  | groupSize | INCLUDES this 24-byte header (!) |
| 0x08   | 4 bytes | label     | meaning depends on groupType     |
| 0x0C   | int32   | groupType | 0-9, below                       |
| 0x10   | uint16  | timestamp | as records                       |
| 0x12   | uint16  | vcInfo    | as records                       |
| 0x14   | uint32  | unknown   | varies by group type             |

Group types + label meaning (`ESMGroup.Kind`):

| type | meaning                  | label                              |
| ---- | ------------------------ | ---------------------------------- |
| 0    | top group                | char4 record type                  |
| 1    | world children           | parent WRLD formID                 |
| 2    | interior cell block      | int32 block number                 |
| 3    | interior cell sub-block  | int32 sub-block number             |
| 4    | exterior cell block      | int16 grid Y, int16 grid X (rev!)  |
| 5    | exterior cell sub-block  | int16 grid Y, int16 grid X (rev!)  |
| 6    | cell children            | parent CELL formID                 |
| 7    | topic children           | parent DIAL formID                 |
| 8    | cell persistent children | parent CELL formID                 |
| 9    | cell temporary children  | parent CELL formID                 |

Caveat (UESP): CK "ignore" flag corrupts label bytes, so labels are hints
only. OpenSky traverses purely by sizes; labels never drive the walk.

## Field (subrecord) — 6-byte header + data

char4 type, uint16 dataSize, payload. Sequence fills the record's
(decompressed) data exactly.

XXXX extension: a field typed `XXXX` (dataSize 4) holds a uint32 that is the
real size of the NEXT field, whose own dataSize is stored as 0. Used for
>64 KB payloads (NAVM/NVNM geometry). `ESMField.parseAll` folds the override
into the extended field and does not emit the XXXX marker.

## Laziness & validation

`ESMFile(url:)` memory-maps the plugin and indexes only the TES4 record +
top-group extents. `children()` parses one nesting level of 24-byte headers;
record payloads are read/decompressed only via `fieldData()`/`fields()`.
Every child must lie fully inside its parent's range; sizes out of bounds,
truncated headers, bad XXXX markers -> thrown `ESMError`, never a crash.
Both header kinds are 24 bytes and every child advances the cursor by at
least that, so traversal always terminates.

## Not implemented (yet)

* Localized string lookup (TES4 flag 0x80 -> lstring tables).
* Per-record-type decoders (WRLD, CELL, REFR, STAT, ...).

## Verification

Unit tests: synthetic in-code fixtures (`openskyTests/ESMFileTests.swift`,
`ESMFixture.swift`, `ZlibTests.swift`). Runtime probe 2026-07-09 against
vanilla Skyrim.esm (form version 44, flags 0x81): 118 top groups in UESP's
documented order, 50 494 groups + 869 687 records walked, no unknown group
types; all 44 153 compressed records decompress and all 4.13 M fields parse
(18 records carry >64 KB XXXX-extended fields); 37 worldspaces listed via
WRLD EDID (Tamriel first). Full deep walk ~3 s on M1.
