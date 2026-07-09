---
type: File Format
title: Localized string tables
description: Layout of .strings/.dlstrings/.ilstrings tables and how OpenSky decodes them.
tags: [format, strings, localization, plugin]
timestamp: 2026-07-09T00:00:00Z
---

# Localized string tables, Skyrim SE

Plugins with the TES4 "localized" flag (0x80, see [FormID](/formats/formid.md))
store no display text inline. Where a record would hold a zstring it holds a
uint32 string ID ("lstring") pointing into per-language tables at
`Strings/<plugin>_<language>.<ext>` — loose or in a BSA (vanilla:
`Skyrim - Interface.bsa`). All five vanilla masters are localized.

Reference: UESP "Skyrim Mod:String Table File Format"
(<https://en.uesp.net/wiki/Skyrim_Mod:String_Table_File_Format>).
Impl: `opensky/Formats/Strings/StringTable.swift`.

## File layout

Little-endian. One header, three entry framings by extension:

| offset         | type      | meaning                                   |
| -------------- | --------- | ----------------------------------------- |
| 0x00           | uint32    | entry count                               |
| 0x04           | uint32    | data block size in bytes                  |
| 0x08           | 8 × count | directory: uint32 id, uint32 offset       |
| 0x08 + 8×count | bytes     | data block, entries at directory offsets  |

Directory offsets are relative to the data block start. Entry framing:

* `.strings` — bare zstring (null-terminated). UI text, names.
* `.dlstrings` — uint32 byte length (terminator included) + zstring. Book
  text, descriptions.
* `.ilstrings` — same framing as `.dlstrings`. Dialogue lines.

## OpenSky decode policy

* Directory parsed eagerly (id -> offset map); string bytes framed + decoded
  per lookup. Duplicate directory IDs: first wins (matches xEdit lookup).
* Bounds: directory offset must lie inside the data block (throw at parse);
  entry framing past the block throws at lookup. Trailing bytes after the
  data block tolerated; truncation is not.
* Length-prefixed entries missing their trailing null are tolerated.
* Encoding: no marker in the file, languages mix UTF-8 and legacy codepages.
  Policy: bytes valid as UTF-8 decode as UTF-8 (accidental valid UTF-8 is
  rare), else windows-1252 — consistent with BSA/ESM string handling. See
  open question in [roadmap](/todo.md).

Lookup wiring (record field -> table by content type, VFS path resolution,
language selection) is not built yet; this page covers the container format.

## Verification

Unit tests: `openskyTests/StringTableTests.swift` (synthetic fixtures,
`StringTableFixture`). Runtime probe 2026-07-09 against the real install:
273 table files across vanilla BSAs (10 languages), 834 865 strings framed
and decoded, 0 failures; UTF-8 languages (Chinese, Japanese, Russian) hit
the UTF-8 path, cp1252 languages (French, German) decode correctly;
`skyrim_english.strings` spot checks match known content.
