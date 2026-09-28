---
type: File Format
title: HKX Packfile Container
description: Havok packfile container layout in Skyrim SE (header, sections, fixups, class
  names) and how OpenSky lists the objects in it.
tags: [format, havok, hkx, animation]
---

# HKX packfile container

An `.hkx` file is a Havok binary packfile. Skyrim SE uses it for skeletons
(`skeleton.hkx`), animation clips, behaviors, and ragdolls. This page covers only the
container: the header, the sections, the fixup tables, and the class names. The objects
inside have their own pages: [hkaSkeleton](/formats/hka-skeleton.md) and
[hkaSplineCompressedAnimation](/formats/hka-animation.md).

`openskycli hkx <key>` prints a file's container ([CLI](/tools/cli.md)).

## Sources

There is no public Havok specification. The layout comes from open parsers and community
notes. Every field was then checked against real SSE files (`skeleton.hkx`, `mt_idle.hkx`,
`1hm_idle.hkx`, `2hm_idle.hkx` in `Skyrim - Animations.bsa`).

- exyorha/hkxparse (MIT): packfile structs, fixup ranges, end markers.
- ret2end/HKX2Library (MIT): SSE header values, the 48-byte section header, class-name
  encoding. The most reliable source for SSE.
- ZeldaMods wiki "Havok": byte tables for the Havok 2014 (version 11) variant. The shape is
  the same, but values differ.
- Lukas Cone, "Havok middleware": the table of layout rules per platform.

No Havok SDK or Bethesda code was used.

## What SSE files look like

Every vanilla SSE file checked is a 64-bit little-endian packfile with file version 8, the
version string `hk_2010.2.0-r1`, and layout rules `8-1-0-1`. It has three sections:
`__classnames__`, `__types__` (empty), and `__data__`. There are no export or import tables.
The section sizes add up exactly to the file size.

## Header (64 bytes at offset 0)

All integers are little-endian.

| Offset | Size | Field | SSE value |
| --- | --- | --- | --- |
| 0x00 | 4 | magic0 | `0x57E0E057` |
| 0x04 | 4 | magic1 | `0x10C0C010` |
| 0x08 | 4 | userTag | 0 |
| 0x0C | 4 | fileVersion | 8 (Havok 2010; 2014 files use 11) |
| 0x10 | 1 | pointerSize | 8 |
| 0x11 | 1 | littleEndian | 1 |
| 0x12 | 1 | reusePaddingOptimization | 0 |
| 0x13 | 1 | emptyBaseClassOptimization | 1 |
| 0x14 | 4 | numSections | 3 |
| 0x18 | 4 | contentsSectionIndex | 2 (`__data__`) |
| 0x1C | 4 | contentsSectionOffset | 0 (the root object is at offset 0) |
| 0x20 | 4 | contentsClassNameSectionIndex | 0 (`__classnames__`) |
| 0x24 | 4 | contentsClassNameSectionOffset | `0x4B`, the name `hkRootLevelContainer` |
| 0x28 | 16 | contentsVersion | `hk_2010.2.0-r1`, null, then `0xFF` fill |
| 0x38 | 4 | flags | 0 |
| 0x3C | 4 | padding (two int16) | `0xFFFFFFFF` |

A wrong magic, a pointer size other than 8, or big-endian data is an error. Other file
versions parse, and the caller sees the version.

## Section headers (48 bytes each, from 0x40)

Each header is a 19-byte null-padded name, one `0xFF` byte, and seven uint32 values:
`absoluteDataStart`, then six offsets relative to it: `localFixupsOffset`,
`globalFixupsOffset`, `virtualFixupsOffset`, `exportsOffset`, `importsOffset`, `endOffset`.

The parts of a section, in order:

```text
[object data | local fixups | global fixups | virtual fixups | exports | imports] end
```

The object data ends where the local fixups start. In SSE, exports, imports, and end are
equal (no tables). `__classnames__` has no fixups. `__types__` is all zero, and its
`absoluteDataStart` equals the one of `__data__`.

Havok 2014 files add 16 bytes of `0xFF` to each section header (64 bytes) and can use an
80-byte file header. SSE files never do.

## Class names

`__classnames__` is a packed list. Each entry is a uint32 signature (a hash of the class),
the byte `0x09`, and a null-terminated ASCII name. A fixup points at the name, which is the
entry start plus 5. The list ends at `0xFFFFFFFF`, followed by `0xFF` padding. OpenSky also
stops at a separator that is not `0x09`, as HKX2Library does, for files with no end marker.

Signatures are the same in every file. Examples: `hkClass` is `0x75585EF6`, and
`hkRootLevelContainer` is `0x2772C11E`.

## Fixup tables

A first uint32 of `0xFFFFFFFF` marks an unused slot and ends the table. Tables are 16-byte
aligned, so they often end with padding.

- Local fixup (8 bytes): `fromOffset`, `toOffset`. A pointer inside one section.
- Global fixup (12 bytes): `fromOffset`, `toSectionIndex`, `toOffset`. A pointer to another
  section.
- Virtual fixup (12 bytes): `objectOffset`, `classNameSectionIndex`, `classNameOffset`.
  It gives an object its class.

## Listing objects

Walk the virtual fixups of `__data__`. Look up each `classNameOffset` in the class-name
table. The result is a list of (object offset, class name). The container gives only where
each object starts. The size of an object needs the class layout.

A class-name offset that does not resolve gives an object with no class name. The file stays
readable.

A clip name to know: `mt_idle.hkx` exists only per sex, under `animations/male/` and
`animations/female/`. There is no `animations/mt_idle.hkx`.
