---
type: File Format
title: ESM/ESP Plugin Container (Skyrim SE)
description: Record, group, and field layout of SSE plugin files and how OpenSky walks them.
tags: [format, plugin, esm, esp, records, io, zlib]
---

# ESM/ESP plugin container

Plugin files (`.esm`, `.esp`, `.esl`) hold all game data. Data is stored in records, and
records are grouped in `GRUP` containers. This page covers only the container. Each record
type has its own page (see [records](/formats/records.md)).

Source: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format). All
integers are little-endian. A type code is 4 ASCII bytes.

## File shape

A file is one `TES4` record (plugin info), then top-level groups until the end of the file.
`Skyrim.esm` has 118 top groups, in the order UESP lists. Each top group holds records of
the type in its label. Only `CELL`, `WRLD`, and `DIAL` records have child groups.

## Record header (24 bytes)

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | char4 | type | For example `WRLD`. `GRUP` means a group |
| 0x04 | uint32 | dataSize | The data only, not the header |
| 0x08 | uint32 | flags | Bits below |
| 0x0C | uint32 | formID | See [FormID](/formats/formid.md) |
| 0x10 | uint16 | timestamp | SSE packs `0bYYYYYYYMMMMDDDDD` |
| 0x12 | uint16 | vcInfo | Creation Kit version-control user IDs |
| 0x14 | uint16 | version | Form version: 43 is Skyrim LE, 44 is SSE |
| 0x16 | uint16 | unknown | 0 to 15 seen |

Oblivion used 20-byte headers. OpenSky does not read them.

Flags that OpenSky uses (many bits mean different things per type, see UESP):

| Bit | Meaning |
| --- | --- |
| `0x1` | On `TES4`: ESM |
| `0x20` | Deleted |
| `0x80` | On `TES4`: localized, text in [string tables](/formats/strings.md) |
| `0x200` | On `TES4`: ESL |
| `0x1000` | Ignored |
| `0x40000` | Data is compressed |

Compressed data is a uint32 decompressed size, then a zlib stream (RFC 1950) for the rest of
`dataSize`. Apple's `COMPRESSION_ZLIB` reads raw deflate only. So OpenSky checks the 2-byte
zlib header and removes it. The final adler32 checksum is not checked. The output length is
checked against the decompressed size instead. A size over 256 MB is rejected.

## Group header (24 bytes)

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | char4 | `GRUP` | |
| 0x04 | uint32 | groupSize | Includes this 24-byte header |
| 0x08 | 4 bytes | label | Meaning depends on the group type |
| 0x0C | int32 | groupType | 0 to 9, below |
| 0x10 | uint16 | timestamp | As in records |
| 0x12 | uint16 | vcInfo | As in records |
| 0x14 | uint32 | unknown | Depends on the group type |

Note the difference: a record's size does not count its header, but a group's size does.

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

For exterior blocks, Y comes before X. UESP warns that the Creation Kit "ignore" flag can
break label bytes. So OpenSky walks by sizes only. Labels are hints.

## Field header (6 bytes)

A field (also called a subrecord) is a char4 type, a uint16 size, and the data. The fields
fill the record data exactly.

A field of type `XXXX` with size 4 holds a uint32. That value is the real size of the next
field, whose own size is stored as 0. Fields larger than 64 KB use this, for example the
navmesh geometry in `NAVM NVNM`. OpenSky applies the size to the next field and drops the
`XXXX` marker.

## Walking the file safely

OpenSky memory-maps the file and first indexes only the `TES4` record and the top groups.
It reads one level of headers at a time. It reads or decompresses record data only when a
caller asks.

Every child must fit inside its parent. A size out of range, a short header, or a bad `XXXX`
marker is an error, never a crash. Both header kinds are 24 bytes, and each step moves at
least that far, so the walk always ends.

## Not implemented

- ESL FormIDs. The master index is the plain top byte. The `0xFE` plus 12-bit slot scheme of
  light plugins is not decoded.
