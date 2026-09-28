---
type: File Format
title: OpenSky save file (.osav)
description: OpenSky's own save container - design goals, header, load-order fingerprint, chunk
  stream, version rules, defensive decoding, and atomic writes.
tags: [format, save, io, world-state, determinism]
---

# OpenSky save file (.osav)

`.osav` is the file OpenSky writes when it saves a session. It holds the
[world state snapshot](/engine/runtime-state.md): every runtime change from what the plugins say.
It also holds the load order and a small header.

This format is OpenSky's own. It is not Bethesda's `.ess` and does not come from it. Nothing in
it is reverse engineered, so this page is the specification. OpenSky never writes an `.ess`
file. Reading one is a separate idea for the future and shares nothing with this layout.

Integers are little-endian. Floats are IEEE 754 bit patterns, little-endian. A string is a
uint16 byte length, then that many UTF-8 bytes. The chunks are on the
[save chunks](/formats/save-chunks.md) page.

## Design goals

Deterministic bytes. Everything after the header is a pure function of the world state and the
load order. Two sessions that reach the same state in a different order write the same bytes. So
a round-trip test is a byte comparison, and a bug report can be reproduced.

Tolerance, in two directions and on purpose unequal. The body is a stream of tagged chunks with
a length. A build that does not know a chunk skips it and loads the rest. But inside a chunk, an
unknown component kind is an error. A world that silently lost some components looks right and
is not.

Defensive decoding. Every count is checked against the bytes left before any memory is
reserved. A corrupt length is an error, not a huge allocation.

## Header

| Offset | Type | Field | Meaning |
| --- | --- | --- | --- |
| 0x00 | 4 chars | magic | `OSAV` |
| 0x04 | uint32 | formatVersion | 1, the only version this build reads |
| 0x08 | uint32 | metadataLength | Size of the metadata block |
| 0x0C | bytes | metadata | uint64 creation time (Unix seconds), then the app version string |

The caller passes in the creation time. The encoder never reads the clock. So tests can make the
same bytes twice, and a copied or migrated save keeps its original time.

The decoder stops after the app version, however long the block is. So a newer build can add
metadata without a version change, and an older build skips the extra bytes.

Only the header depends on the time. Two saves of the same state differ only in their first few
dozen bytes.

## Deterministic region

Everything after the metadata is deterministic. Three rules make it so:

- Entries are written in `ReferenceKey` order. The store sorts its changed keys. It does not keep
  the order of changes.
- Components inside an entry are written in rising tag order, and the decoder rejects any other
  order. So one state has exactly one byte form.
- The encoder never reads a clock, a hash seed, or the order of a dictionary.

## Load-order fingerprint

A uint32 plugin count, then for each plugin in load order:

| Type | Field | Meaning |
| --- | --- | --- |
| string | name | Plugin file name, as on disk |
| uint32 | hedrVersion | Bits of the `HEDR` version float (0.94, 1.7, 1.71) |
| uint32 | recordCount | `HEDR` record and group count |
| uint32 | nextObjectID | `HEDR` next object ID |

The three numbers come from the plugin's TES4 `HEDR` field (see [FormID](/formats/formid.md)).
The Creation Kit rewrites them whenever a plugin changes. So together they are a cheap "same
plugin as before?" check, much cheaper than hashing archives.

The check compares the lists position by position and names the first difference. Name case is
ignored, as everywhere else in the engine. Order matters. Plugin `ReferenceKey`s use names and
survive a new order, but records, masters, and object IDs do not.

Checking is separate from decoding. Decoding needs only the file. So a tool or a test can read a
save with no game installed, and the app can show what a save holds before it explains why the
save cannot load.

The list is the resolved [load order](/formats/plugins-txt.md). A save made with a mod on does
not match an install with that mod off.

## Chunks

The rest of the file is chunks, up to the end of the file:

| Type | Field | Meaning |
| --- | --- | --- |
| 4 chars | tag | Chunk name |
| uint32 | payloadLength | Size of the payload |
| bytes | payload | The data |

A length past the end of the file is an error. An unknown tag is skipped by its length. This is
what lets an older build load a newer save.

## Version rules

A new chunk tag needs no version change. An older build skips it and loses only that feature.

A version change is needed for:

- a changed payload layout in an existing chunk,
- a new component kind inside `RDLT`,
- a changed component payload.

An unknown component kind is rejected, not skipped. The decoder would have to guess how many
bytes to skip, and a wrong guess breaks the rest of the entry. So new kinds of state go into
their own chunk instead. Inventory was the first. Every later kind of state followed.

A new meaning for existing bytes needs a new tag, not the same tag. Example: `AVOV` replaced
`AVGN`. The two have the same shape but different meanings. Reading one as the other would turn a
resistance of 30 into 30 points above the record value.

Widening a flat chunk also needs a new sibling chunk. Most chunks are lists of entries with no
length per entry. Adding a field to each entry would make an older build misread the whole
chunk. A sibling chunk is skipped whole. Examples: `QALS` beside `QSTS`, `AVOV` beside `AVAL`,
`STOL` beside `INVN`, and `CRVG` beside `CRIM`.

`formatVersion` must match exactly. Any other value fails with "unsupported version".

## Defensive decoding

All reads go through one bounds-checked reader. Every read failure becomes one "truncated" error
that names the structure being read.

- Every count is checked against the bytes left, divided by the smallest size of one element,
  before memory is reserved.
- Each chunk is decoded through its own reader over only its payload. A bad count cannot reach
  into the next chunk.
- A string length past the end is a truncation. Bytes are read before they are used.
- A Boolean byte must be exactly 0 or 1. Reading `0x7F` as true would hide a bug.

Errors:

| Error | Meaning |
| --- | --- |
| `badMagic` | The first 4 bytes are not `OSAV` |
| `unsupportedVersion(found:)` | A version this build does not read |
| `truncated(context:)` | The file ends inside a structure. `context` names it |
| `invalidCount(chunk:count:remaining:)` | A count cannot fit in the bytes left |
| `invalidValue(context:)` | A value the format does not define: a bad Boolean, an unknown tag, or components out of order |
| `chunkBoundsViolation(tag:)` | A chunk runs past the end of the file |
| `fingerprintMismatch(reason:)` | The save was made with a different load order |

Some values are fixed up instead of rejected. The rule: a value the running game can really
produce is fixed up, and a shape the build cannot read is rejected. Each chunk's rule is on the
[save chunks](/formats/save-chunks.md) page.

Encoding never fails. Every state has a byte form. The one loss: a string longer than 64 KiB is
cut at the last whole UTF-8 character that fits. A plugin name or app version that long is
already nonsense.

## Where saves go

Saves go to `~/Library/Application Support/OpenSky/Saves/`, created when needed. Never to the
repository and never to the game folder. The game folder is read-only input, and a save is the
user's data.

Each save is written in three steps. Each step prevents one failure:

1. Write a temporary file in the same folder as the target. A rename is atomic only inside one
   file system, and `/tmp` may be on another one.
2. Sync the file to disk before closing it. Without this, after a power loss the folder entry
   can reach the disk before the data, which gives a file full of zeros.
3. Rename it over the target. This replaces the file in one step. A crash or a full disk leaves
   the old save whole.

Any failure removes the temporary file.

## Save slots

`OpenSkySaveStore` names saves by slot. A slot name becomes `<slot>.osav` in the saves folder.
Loading can skip the fingerprint check, so a save can be inspected with no game installed.

A slot name comes from a text field the user types in. So it is checked before it becomes a path:
an empty name, a path separator, or a character outside a small allowed set is an error. The UI
is under World > Runtime State (see [runtime state](/engine/runtime-state.md)).

Saves are not compressed. They hold only changes, so they are small, and an uncompressed file can
be read in a hex editor when a determinism test fails.
