---
type: File Format
title: HKX Packfile Container
description: Havok packfile layout in Skyrim SE - header, sections, fixups, and class names -
  and how OpenSky lists the objects in a file.
tags: [format, havok, hkx, animation]
---

# HKX packfile container

An HKX file is a Havok binary packfile. Skyrim SE uses it for skeletons (`skeleton.hkx`),
animation clips, behaviors, and ragdolls. This page covers only the container: the header,
the section table, the fixup tables, and the class names. The objects inside have their own
pages: [hkaSkeleton](/formats/hka-skeleton.md) and
[hkaSplineCompressedAnimation](/formats/hka-animation.md).

`openskycli hkx <key>` prints the container of a file (see [CLI](/tools/cli.md)).

A `.hkt` file is not a packfile. It is a Havok binary tagfile, on its own page:
[HKT binary tagfile](/formats/hkt-tagfile.md).

## References

There is no public Havok specification. The layout comes from open parsers and community
notes. Every field was then checked against vanilla files (`skeleton.hkx`, `mt_idle.hkx`,
`1hm_idle.hkx`, `2hm_idle.hkx`, all in `Skyrim - Animations.bsa`):

- exyorha/hkxparse (MIT): packfile structs, fixup regions, and end markers.
- ret2end/HKX2Library (MIT): Skyrim SE header values, the 48-byte section header, and the
  class-name encoding. This is the best source for Skyrim SE.
- ZeldaMods wiki "Havok": byte tables for the Havok 2014 (version 11) variant. The shape is
  the same, the values differ.
- Lukas Cone, "Havok middleware": the table of platform layout rules.

No Havok SDK or Bethesda code was used.

## Skyrim SE profile

Every vanilla file checked has: 64-bit little-endian, file version 8, version string
`hk_2010.2.0-r1`, layout rules `8-1-0-1`, and 3 sections (`__classnames__`, `__types__`,
`__data__`). `__types__` is empty. There are no export or import tables. The section sizes
add up exactly to the file size.

## Header: 64 bytes at offset 0

All integers are little-endian.

| Offset | Size | Field | Skyrim SE value |
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
| 0x1C | 4 | contentsSectionOffset | 0 (the top object is at data offset 0) |
| 0x20 | 4 | contentsClassNameSectionIndex | 0 (`__classnames__`) |
| 0x24 | 4 | contentsClassNameSectionOffset | `0x4B`, which is `hkRootLevelContainer` |
| 0x28 | 16 | contentsVersion | `hk_2010.2.0-r1`, a null, then `0xFF` bytes |
| 0x38 | 4 | flags | 0 |
| 0x3C | 4 | padding (two int16) | `0xFFFFFFFF` |

OpenSky rejects a wrong magic, a pointer size other than 8, and big-endian files. Other file
versions are read, and the caller can see the version.

## Section headers: 48 bytes each, from 0x40

Each header is a 19-byte name padded with nulls, one `0xFF` byte, and seven uint32 values:
`absoluteDataStart`, then six offsets from that start: `localFixupsOffset`,
`globalFixupsOffset`, `virtualFixupsOffset`, `exportsOffset`, `importsOffset`, and
`endOffset`. The parts of a section come in this order:

```text
[object data | local fixups | global fixups | virtual fixups | exports | imports] end
```

The data size is `localFixupsOffset`. In Skyrim SE, `exports == imports == end` always.
`__classnames__` has no fixups (all six offsets are equal). `__types__` is all zeros, with
the same `absoluteDataStart` as `__data__`.

Havok 2014 (version 11) adds 16 `0xFF` bytes to each section header, making it 64 bytes. It
may also use an 80-byte file header. Skyrim SE never does.

## `__classnames__`

Each entry is a uint32 signature (a hash of the class type), a `0x09` byte, and the class
name as a null-terminated ASCII string. Fixups point at the name, so at entry start + 5. The
table ends with `0xFFFFFFFF`, then `0xFF` padding. OpenSky also stops at a separator byte
that is not `0x09`, as HKX2Library does. This handles files with no end marker.

`skeleton.hkx` has 20 classes, for example `hkaSkeleton`, `hkaSkeletonMapper`, and the
ragdoll physics classes. An idle clip has 9, for example `hkaSplineCompressedAnimation` and
`hkaAnimationBinding`. Signatures are the same in every file, for example `hkClass`
`0x75585EF6` and `hkRootLevelContainer` `0x2772C11E`.

## Fixup tables

A fixup tells the loader to patch a pointer. A first uint32 of `0xFFFFFFFF` is an unused
slot and ends the table. Regions are aligned to 16 bytes, so the end is often padding. For
example, an idle clip's virtual table has 5 entries in a 64-byte region.

| Kind | Size | Fields | Meaning |
| --- | --- | --- | --- |
| Local | 8 | `fromOffset`, `toOffset` | Pointer inside the same section |
| Global | 12 | `fromOffset`, `toSectionIndex`, `toOffset` | Pointer to another section |
| Virtual | 12 | `objectOffset`, `classNameSectionIndex`, `classNameOffset` | Gives an object its class |

## Listing the objects

The virtual fixups of `__data__` give every object's start and class name. The root object
comes from the header (offset 0, `hkRootLevelContainer`). `skeleton.hkx` has 324 objects:
2 `hkaSkeleton`, 2 `hkaSkeletonMapper`, ragdoll physics, and resource containers. An idle
clip has 5. The container gives only where each object starts. The size of an object needs
knowledge of its class.

If a class name offset points nowhere, the object keeps no class name. The file is still
readable.

Note: `mt_idle.hkx` exists only in `animations/male/` and `animations/female/`. There is no
`animations/mt_idle.hkx`.
