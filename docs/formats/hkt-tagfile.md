---
type: File Format
title: HKT binary tagfile
description: The Havok binary tagfile behind Skyrim SE .hkt files - magic, the varint item stream,
  class definitions, objects, and what the install's files hold.
tags: [format, havok, hkt, animation]
---

# HKT binary tagfile

A `.hkt` file is a Havok binary tagfile. It is a different container from the
[HKX packfile](/formats/hkx-container.md): it has no sections and no fixups. It writes its own class
definitions, member names, and member types before the objects, so a reader needs no knowledge of
any Havok class layout.

## References

No open specification of this container was found. The layout below was read from the install's
own files and checked by decoding every one of them to its last byte. The files describe their own
types, so every member name and type here comes from the files, not from a Havok SDK. No Havok SDK
or Bethesda code was used.

Every field is inferred. The ones still unexplained are marked.

## Magic

| Offset | Size | Value |
| --- | --- | --- |
| 0x00 | 4 | `0xCAB00D1E` |
| 0x04 | 4 | `0xD011FACE` |

All words are little-endian.

## Numbers and strings

Every number after the magic is a varint: seven bits per byte, low bits first, and the high bit set
on every byte but the last. Bit 0 of the decoded value is the sign and the rest is the magnitude.
So `0x03` is -1 and `0x04` is 2. This sign rule was settled by `hkaSkeleton parentIndices`, whose
root bone is -1.

A string is a length. A positive length is followed by that many bytes, and the string joins a
table. Zero is the empty string. A negative length names an earlier string: the table starts with
the empty string at 0 and null at 1, so the first new string is index 2.

## Items

The file is a list of items, each starting with a tag number.

| Tag | Item | Body |
| --- | --- | --- |
| 1 | File info | Version: 0 or 3 on the install |
| 2 | Class definition | Name, version, parent class index, member count, members |
| 3 | Object | Class index, then the fields |
| 4 | Remembered object | As tag 3, and the object is added to the remembered list |
| 5 | Back reference | Remembered index |
| 6 | Null | Nothing |
| 7 | End | Nothing |

Classes are numbered from 1 in the order they are defined, and 0 means no parent. A member is a
name and a type word. Bits 0 to 3 of the type word are the base kind, `0x10` marks an array, and
`0x20` marks a tuple, followed by its length. An object or struct member is followed by its class
name.

| Kind | Value | Written as |
| --- | --- | --- |
| 0 | void | Never written; such members are not saved |
| 1 | byte | One byte |
| 2 | int | Varint |
| 3 | real | 32-bit float |
| 4, 5, 6, 7 | vector of 4, 8, 12, or 16 floats | Floats |
| 8 | object | A reference, below |
| 9 | struct | Fields, inline |
| 10 | string | String |

The install uses every kind but the 8-float vector, and no tuple.

## Objects and fields

Fields start with a presence mask: one bit per member, inherited members first, eight to a byte.
Only the members whose bit is set follow, in member order.

An array is a count, then the elements. A struct array has one presence mask for all elements, then
each present member as a column over every element. A struct member nested in such a column is a
column too. In a version 3 file an int array, or an int column, has one more varint after the count
when the count is not zero. It is always 4 on the install, and its meaning is unknown.

An object reference differs by version:

- Version 3 writes the remembered index of the object. The object itself is written later, as its
  own remembered item. The root container is remembered index 1.
- Version 0 writes the object in place, as a tag 3 or tag 4 item, or a tag 5 or tag 6 item.

The four version 0 files on the install end after their last object, with no end item.

## What the install holds

The archives hold 30 `.hkt` files: 26 at version 3 and 4 at version 0. They come from
`_ResourcePack.bsa`, `Skyrim - Animations.bsa`, and `ccBGSSSE001-Fish.bsa`. They are behavior
projects for activators, the Creation Club fishing and giant crab content, one wolf idle behavior,
and the Dwarven Ballista behavior. They define 121 class versions and hold 777 objects.

Each set has the same roles as a packfile behavior set: a project (`hkbProjectData`), a character
(`hkbCharacterData`), a behavior (`hkbBehaviorGraph`), and a skeleton or animation container
(`hkaAnimationContainer`). Some class versions differ from the packfile files: `hkaSkeleton` is
version 2 in the four version 0 files and version 3 in the others.

No file defines a cloth class (an `hcl` prefix or a `Cloth` name). So the install ships no Havok
cloth setup data, and no cloth binds to a skeleton bone. A future cloth simulation needs another
data source. The skeletons in these files name 34 bones in all, listed by `openskycli hkt sweep`.

OpenSky decodes these files into generic objects. It does not yet run their behavior graphs, which
are decoded only from packfiles ([HKX behavior](/formats/hkx-behavior.md)).
