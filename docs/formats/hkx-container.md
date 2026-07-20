---
type: File Format
title: HKX Packfile Container
description: Havok packfile container layout (header, sections, fixups, class
  names) as shipped in Skyrim SE, and how OpenSky enumerates objects.
tags: [format, havok, hkx, animation]
timestamp: 2026-07-20T00:00:00Z
---

# HKX packfile container

Havok binary packfile — container for skeletons (`skeleton.hkx`), animations
(`*.hkx` clips), behavior + ragdoll data. This page covers the container only:
header, section table, fixup tables, class-name inventory. Object internals
(hkaSkeleton members, spline-compressed tracks) are separate work (todo 6.2+).

Parser: `opensky/Formats/HKX/` (`HKXHeader`, `HKXSection`, `HKXFile`). CLI dump:
`openskycli hkx <key>` ([CLI](/tools/cli.md)). Tests: `HKXFileTests` over
synthetic `HKXFixture` blobs.

## References

No public Havok spec. Layout reimplemented from independent open parsers +
community docs, then every field probe-verified against the local SSE install
(`skeleton.hkx`, `mt_idle.hkx`, `1hm_idle.hkx`, `2hm_idle.hkx` — all
`Skyrim - Animations.bsa`):

* exyorha/hkxparse (MIT) — packfile structs, fixup extents, sentinel rules.
* ret2end/HKX2Library (MIT) — SSE-specific header values, 48-byte section
  header quirk, class-name encoding. Most SSE-authoritative.
* ZeldaMods wiki "Havok" — byte tables for the Havok-2014 (v11) variant;
  container shape matches, values differ (see variants below).
* Lukas Cone "Havok middleware" write-up — platform layout-rule table.

No Havok SDK or Bethesda code consulted (AGENTS.md Legal & IP).

## Observed SSE profile

Every vanilla SSE file probed: 64-bit little-endian packfile, fileVersion 8,
version string `hk_2010.2.0-r1`, layout rules `8-1-0-1`, 3 sections
(`__classnames__`, `__types__`, `__data__`), `__types__` empty, no
exports/imports tables. Section arithmetic closes exactly on file size.

## Header (64 bytes, offset 0, all integers LE)

| off | size | field | SSE value |
| --- | --- | --- | --- |
| 0x00 | 4 | magic0 | 0x57E0E057 |
| 0x04 | 4 | magic1 | 0x10C0C010 |
| 0x08 | 4 | userTag | 0 |
| 0x0C | 4 | fileVersion | 8 (Havok 2010; BotW/2014 files use 11) |
| 0x10 | 1 | pointerSize | 8 |
| 0x11 | 1 | littleEndian | 1 |
| 0x12 | 1 | reusePaddingOptimization | 0 |
| 0x13 | 1 | emptyBaseClassOptimization | 1 |
| 0x14 | 4 | numSections | 3 |
| 0x18 | 4 | contentsSectionIndex | 2 (`__data__`) |
| 0x1C | 4 | contentsSectionOffset | 0 (top object at data offset 0) |
| 0x20 | 4 | contentsClassNameSectionIndex | 0 (`__classnames__`) |
| 0x24 | 4 | contentsClassNameSectionOffset | 0x4B -> "hkRootLevelContainer" |
| 0x28 | 16 | contentsVersion | "hk_2010.2.0-r1" NUL-terminated, 0xFF fill |
| 0x38 | 4 | flags | 0 |
| 0x3C | 4 | pad (2x i16 maxPredicate/sectionOffset) | 0xFFFFFFFF |

Parser rejects wrong magic, non-8 pointer size, non-LE (typed `HKXError`);
other fileVersions parse but are surfaced to callers.

## Section headers (48 bytes each, at 0x40, back-to-back)

19-byte NUL-padded ASCII name + 1 separator byte (0xFF) + 7 u32:
`absoluteDataStart`, then six offsets relative to it — `localFixupsOffset`,
`globalFixupsOffset`, `virtualFixupsOffset`, `exportsOffset`, `importsOffset`,
`endOffset`. Region order inside a section:

```text
[object data | local fixups | global fixups | virtual fixups | exp | imp] end
```

Data size = `localFixupsOffset` (data ends where fixups begin). SSE:
`exports == imports == end` everywhere (no tables); `__classnames__` carries
no fixups (all six equal); `__types__` all-zero with `absoluteDataStart`
equal to `__data__`'s.

Variant flag: Havok-2014 (v11) appends 16 bytes of 0xFF to each section
header (64-byte headers) + may use an 80-byte file header. SSE never does.

## `__classnames__` encoding

Packed entries: `u32 signature` (stable per-class type hash) + `0x09`
separator + NUL-terminated ASCII name. Fixups reference the offset of the
name string, i.e. entry start + 5. Table ends at a `0xFFFFFFFF` sentinel,
then 0xFF padding to the section end. Parser also stops on a non-0x09
separator (HKX2Library rule) — covers files without sentinel.

Observed: skeleton.hkx 20 classes (hkaSkeleton, hkaSkeletonMapper, ragdoll
physics set); idle clips 9 classes (hkaSplineCompressedAnimation,
hkaAnimationBinding, ...). Signatures stable across files (hkClass
0x75585EF6, hkRootLevelContainer 0x2772C11E).

## Fixup tables

First u32 == 0xFFFFFFFF -> unused slot, ends the table (regions are 16-byte
aligned; tails padded — observed: idle virtual table 5 entries in a 64-byte
region). Entry layouts:

* local (8 B): `fromOffset`, `toOffset` — intra-section pointer patch.
* global (12 B): `fromOffset`, `toSectionIndex`, `toOffset` — cross-section.
* virtual (12 B): `objectOffset`, `classNameSectionIndex`, `classNameOffset`
  — binds an object instance to its class name ("finish" pass).

## Object inventory

Walk `__data__` virtual fixups, resolve each `classNameOffset` against the
class-name table -> `(object offset, class name)` list. Root object:
contents fields in the header (offset 0, "hkRootLevelContainer"). Observed:
skeleton.hkx 324 objects (2 hkaSkeleton + 2 hkaSkeletonMapper + ragdoll
physics + resource containers); idle clips 5 objects each. The container
gives object starts only — sizes need class reflection (later milestone).

## Engine mapping

`HKXFile` keeps the raw `Data` + parsed tables; `sectionData(at:)` slices a
section payload for 6.2+ object decoding. Unresolvable class-name offsets
yield `className == nil` on the `HKXObjectRef` — malformed input stays
inspectable, never traps. Human idle gotcha: `mt_idle.hkx` is gender-split
(`animations/male/`, `animations/female/`); no bare `animations/mt_idle.hkx`.
