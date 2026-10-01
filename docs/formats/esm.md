---
type: File Format
title: ESM/ESP Plugin Container (Skyrim SE)
description: Record, group, and field layout of Skyrim SE plugin files and how OpenSky walks
  them.
tags: [format, plugin, esm, esp, records, io, zlib]
---

# ESM/ESP plugin container

A plugin file (`.esm`, `.esp`, or `.esl`) holds game data as records. Records sit inside
groups (`GRUP`). This page covers only the container: records, groups, fields, and
compression. [Record decoders](/formats/records.md) covers what the records mean.

Reference: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format). All
integers are little-endian. A type code is 4 ASCII bytes.

## File shape

The file starts with one `TES4` record (see [FormID](/formats/formid.md)). Top-level groups
follow until the end of the file. `Skyrim.esm` has 118 top groups, in the order UESP lists.
It is not known whether the game depends on this order. A top group holds records of the
type in its label. Only `CELL`, `WRLD`, and `DIAL` records have child groups after them.

## Record: 24-byte header, then data

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | char4 | type | For example `WRLD`. `GRUP` means a group |
| 0x04 | uint32 | dataSize | Data only, without the header |
| 0x08 | uint32 | flags | Below |
| 0x0C | uint32 | formID | See [FormID](/formats/formid.md) |
| 0x10 | uint16 | timestamp | Skyrim SE packs `0bYYYYYYYMMMMDDDDD` |
| 0x12 | uint16 | vcInfo | Creation Kit version-control user IDs |
| 0x14 | uint16 | version | Form version: 43 original Skyrim, 44 Skyrim SE |
| 0x16 | uint16 | unknown | Values 0 to 15 seen |

Oblivion used 20-byte headers. OpenSky does not read them.

Flags OpenSky uses: `0x1` master (on `TES4`), `0x20` deleted, `0x80` localized (on `TES4`),
`0x200` light (on `TES4`), `0x1000` ignored, `0x40000` data compressed. Many bits mean
different things for different record types. See the UESP table.

Compressed data is a uint32 decompressed size, then a zlib stream (RFC 1950) that fills the
rest of `dataSize`. Apple's `COMPRESSION_ZLIB` reads raw deflate only. So OpenSky checks
and removes the 2-byte zlib header first. It does not check the Adler-32 checksum at the
end. It checks the output size instead. A decompressed size above 256 MB is rejected.

## Group: 24-byte header

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | char4 | `GRUP` | |
| 0x04 | uint32 | groupSize | Includes this 24-byte header |
| 0x08 | 4 bytes | label | Depends on the group type |
| 0x0C | int32 | groupType | 0 to 9, below |
| 0x10 | uint16 | timestamp | Same as records |
| 0x12 | uint16 | vcInfo | Same as records |
| 0x14 | uint32 | unknown | Depends on the group type |

Note that `groupSize` includes the header, but a record's `dataSize` does not.

| Type | Meaning | Label |
| --- | --- | --- |
| 0 | Top group | char4 record type |
| 1 | World children | Parent `WRLD` FormID |
| 2 | Interior cell block | int32 block number |
| 3 | Interior cell sub-block | int32 sub-block number |
| 4 | Exterior cell block | int16 grid Y, then int16 grid X |
| 5 | Exterior cell sub-block | int16 grid Y, then int16 grid X |
| 6 | Cell children | Parent `CELL` FormID |
| 7 | Topic children | Parent `DIAL` FormID |
| 8 | Cell persistent children | Parent `CELL` FormID |
| 9 | Cell temporary children | Parent `CELL` FormID |

For types 4 and 5, Y comes before X. UESP warns that the Creation Kit "ignore" flag can
damage label bytes. So OpenSky walks groups by size only and never trusts a label to steer
the walk.

### Worldspace persistent cell

A world children group (type 1) holds one `CELL` directly, before the exterior blocks. This
is the persistent cell of the worldspace. Its children group holds the persistent `REFR` and
`ACHR` records of the whole worldspace. Each one belongs to the grid cell its position falls
in, so OpenSky places it there.

The persistent cell also has an `XCLC` grid of (0, 0). So a grid lookup must skip it, or it
finds the persistent cell instead of the real (0, 0) cell in the blocks. OpenSky tells the two
apart by where the `CELL` sits: directly in the type 1 group. xEdit uses the same rule: it names
a `CELL` whose container is a type 1 group `<Persistent Worldspace Cell>`
(`Core/wbImplementation.pas`, branch `dev-4.1.6`). UESP lists record header flag `0x400` on
`CELL` as "Persistent Cell?", with a question mark, so OpenSky does not rely on the flag.

Confirmed on `Skyrim.esm`: all 36 worldspaces have exactly one such `CELL`. Each has `XCLC`
(0, 0) and header flag `0x400`. Tamriel also has a separate block cell at (0, 0).

## Field: 6-byte header, then data

A field is a char4 type, a uint16 `dataSize`, and the data. The fields fill the record's
(decompressed) data exactly.

`XXXX` fields: a uint16 size cannot hold more than 64 KB. So a field of type `XXXX` with
size 4 holds a uint32 that is the real size of the next field. That next field stores size
0. Navmesh geometry (`NAVM NVNM`) uses this. OpenSky joins the two and never shows the
`XXXX` field to callers.

## Safety

OpenSky memory-maps the file and reads only the headers it needs. Record data is read and
decompressed only when asked for. Every child must lie inside its parent. A size out of
range, a cut header, or a bad `XXXX` field is an error, never a crash. Every header is 24
bytes and the walk moves at least that far each step, so the walk always ends.

## Not supported

- The `0xFE` FormID space of light masters. See [FormID](/formats/formid.md).

## Vanilla Skyrim.esm

Form version 44, `TES4` flags `0x81`. 50,494 groups and 869,687 records, with no unknown
group types. About 44,000 records are compressed, and all decompress. 18 records use
`XXXX` fields. It has 37 worldspaces, and `Tamriel` is the first.
