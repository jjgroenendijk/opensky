---
type: File Format
title: OpenSky native save container (.osav)
description: Byte layout of OpenSky's own .osav save file — header, load-order fingerprint,
  chunk stream, reference deltas — and its determinism, version, and error rules.
tags: [format, save, io, world-state, determinism]
---

# OpenSky native save container

`.osav` is the file OpenSky writes when it saves a session. It holds the
[world-state snapshot](/engine/runtime-state.md) (every runtime change to what the plugins
say), the load order of the session, and a small header.

This format is OpenSky's own, not Bethesda's `.ess`. Nothing in it is reverse engineered, so
this page is the specification. OpenSky never writes a `.ess` file.

All integers are little-endian. Floats are IEEE 754 bit patterns, little-endian. A string is
a `UInt16` byte length followed by that many UTF-8 bytes. The chunk payloads are on
[save chunks: world and scripts](/formats/opensky-save-world-chunks.md) and
[save chunks: actors](/formats/opensky-save-actor-chunks.md).

## Design goals

- Same state, same bytes. Everything after the header is a pure function of the snapshot
  and the fingerprint. Two sessions that reach the same state in a different order write the
  same bytes. So a round-trip test is a byte comparison.
- Old and new builds can read each other's files, with one exception. The body is a list of
  tagged chunks with lengths. A build skips a chunk it does not know. But inside `RDLT`, an
  unknown component kind is an error, because a delta that silently lost a component gives a
  world that looks right and is wrong.

## Header

| offset | type | field | notes |
| --- | --- | --- | --- |
| 0x00 | char[4] | magic | ASCII `OSAV` |
| 0x04 | uint32 | formatVersion | 1; the only version this build reads |
| 0x08 | uint32 | metadataLength | size of the metadata block |
| 0x0C | bytes | metadata | `metadataLength` bytes |

The metadata block holds a uint64 creation time (seconds since the Unix epoch) and a string
with the app version. The caller passes the time in, so a test can write the same bytes
twice. The decoder stops after the app version and skips any bytes left in the block, so a
newer build can add metadata without a version change.

## The deterministic region

Everything after the metadata is deterministic:

- Entries are written sorted in `ReferenceKey` order, never in the order they changed.
- Inside an entry, components are written in ascending tag order. The decoder rejects any
  other order, so a delta has exactly one valid spelling.
- The encoder never reads the clock, a hash seed, or dictionary order.

Two saves of the same state at different times differ only in the header.

## Load-order fingerprint

A uint32 plugin count, then for each plugin in load order:

| type | field | notes |
| --- | --- | --- |
| string | name | file name as on disk |
| uint32 | hedrVersion | bit pattern of the HEDR version float (0.94, 1.7, 1.71) |
| uint32 | recordCount | HEDR record and group count |
| uint32 | nextObjectID | HEDR next object ID |

The three numbers come from the TES4 `HEDR` field ([FormID](/formats/formid.md)). The
Creation Kit updates them whenever the file changes, so they are a cheap "same plugin?"
check. The list is the resolved [load order](/formats/plugins-txt.md).

A load compares the lists position by position and names the first difference. Case in file
names is ignored. Order matters: a plugin `ReferenceKey` uses the name and survives
reordering, but FormIDs and masters do not. Decoding does not check the fingerprint, so a
tool can read a save on a machine without the game.

## Chunks

The rest of the file is chunks, until the end of the file:

| type | field | notes |
| --- | --- | --- |
| char[4] | tag | four ASCII bytes |
| uint32 | payloadLength | size of the payload |
| bytes | payload | `payloadLength` bytes |

A chunk that runs past the end of the file is an error. A chunk with an unknown tag is
skipped by its length. Each payload is read with its own cursor, so a bad count inside one
chunk cannot read into the next.

| tag | contents | page |
| --- | --- | --- |
| `GALC` | next generated-reference number | below |
| `RDLT` | reference deltas: enable, transform, activation, deletion | below |
| `GVAR` | global variable values | world |
| `CLOK` | game clock | world |
| `PSCR` | Papyrus script instance state | world |
| `PTMR` | pending Papyrus update timers | world |
| `INVN` | inventories | world |
| `SPWN` | spawned references | world |
| `QSTS` | quest running, stages, objectives | world |
| `QALS` | filled reference aliases | world |
| `QLOC` | filled location aliases | world |
| `AVAL` | current health, magicka, stamina | actors |
| `AVOV` | actor-value offsets and modifiers | actors |
| `DETH` | deaths and corpse positions | actors |
| `CBTS` | hostility | actors |
| `DLGS` | dialogue said counts | actors |
| `AEFF` | active magic effects | actors |
| `ECHG` | enchantment charge and worn effects | actors |
| `FCTN` | faction memberships | actors |
| `RELS` | scripted relationship ranks | actors |
| `CRIM` | crime gold and crime counts | actors |
| `STOL` | stolen item counts | actors |
| `CRVG` | violent part of crime gold | actors |
| `HRVS` | harvested flora and trees | world |
| `LOCK` | changed locks | world |

`HRVS` is a uint32 entry count, then one key and one cell per harvested reference. An entry
means harvested, so it has no other field.

`LOCK` is a uint32 entry count, then per changed lock: the key, the cell, a locked byte (0 or
1), the `XLOC` level byte, and the key `KEYM` as a uint32 FormID (0 for none). A lock that
still matches its `XLOC` writes no entry. See [locks](/engine/locks.md).

The code also defines `SPLB`, `PRKS`, and `PLVL` (layouts in `Sources/OpenSkySave/`).
`AVGN` is an old tag that `AVOV` replaced; it is now skipped.

`GALC` is exactly 8 bytes: a uint64, the next number the generated-reference allocator gives
out. Without `GALC`, the allocator starts at 1.

`RDLT` is a uint32 entry count, then entries:

| type | field | notes |
| --- | --- | --- |
| key | key | the reference |
| cell | cell | where the reference was when it changed |
| uint8 | componentCount | components that follow |
| bytes | components | in strictly ascending tag order |

A key is a tag byte: 0 plugin (string plugin name, uint32 object ID) or 1 generated (uint64
sequence). A cell is a tag byte: 0 absent, 1 exterior (int32 x, int32 y), 2 interior (uint32
raw cell FormID). Every chunk uses these two encodings.

| tag | component | payload |
| --- | --- | --- |
| 0 | enable state | one byte, 0 or 1 |
| 1 | transform | position x/y/z, rotation x/y/z, scale: seven float32 |
| 2 | activation | uint32 count, open byte, has-last-activator byte, then a key if that byte is 1 |
| 3 | deletion | one byte, 0 or 1 |

The tag numbers are written out in the code, not taken from the declaration order of the
Swift enum, because that order can change and these bytes cannot. Inventory and spawns are
component kinds in the store, but they have no tag here. They travel in their own chunks,
so an older build can skip them. An entry whose only component is one of those is not in
`RDLT` at all.

## Version policy

A new chunk tag needs no `formatVersion` change. An older build loses that chunk's feature
and nothing else.

A version change is needed for a new payload layout in an existing chunk, a new component
kind inside `RDLT`, or a changed component payload. So new state gets its own chunk. When
old entries are flat and have no per-entry length, a new field cannot be appended without
breaking older readers, so it goes into a new sibling chunk (`QALS` beside `QSTS`, `STOL`
beside `INVN`, `CRVG` beside `CRIM`).

`formatVersion` must match exactly. Any other value fails with `unsupportedVersion(found:)`.

## Errors and normalization

A boolean byte must be exactly 0 or 1. Every count is checked against the remaining bytes
divided by the smallest element size, before memory is reserved.

| case | meaning |
| --- | --- |
| `badMagic` | the first four bytes are not `OSAV` |
| `unsupportedVersion(found:)` | a layout version this build does not read |
| `truncated(context:)` | the file ends inside a structure; `context` names it |
| `invalidCount(chunk:count:remaining:)` | a count cannot fit in the bytes left |
| `invalidValue(context:)` | a value the format does not define: a bad boolean, an unknown tag, or components out of order |
| `chunkBoundsViolation(tag:)` | a chunk runs past the end of the file |
| `fingerprintMismatch(reason:)` | the save was made with a different load order |

Some bad values are corrected instead of rejected, when one bad value should not cost the
whole save. The chunk pages say which. The rule: a value this build wrote from a closed list
(a tag, a slot, a kind) is an error when unknown. A number that is out of range is fixed.

Encoding never fails. A string longer than 64 KiB is cut at the last whole UTF-8 character
that fits.

## Where saves live

Saves go in `~/Library/Application Support/OpenSky/Saves/`, as `<slot>.osav`. Never in the
repository and never in the game install. A slot name may contain only a small set of
characters, because it comes from a text field.

A save is written in three steps:

1. Write a temporary file in the same folder. A rename is atomic only inside one file
   system, and `/tmp` may be on another.
2. Flush the file to disk before closing it. Without this, after a power loss the rename can
   land before the data, and the file is full of zeros.
3. Rename it over the old save. A crash or a full disk leaves the old save whole.

On any failure the temporary file is removed. There is no compression: saves hold changes,
not whole worlds, so they are small and easy to read in a hex editor.
