---
type: File Format
title: Localized string tables
description: Layout of .strings, .dlstrings, and .ilstrings tables and how OpenSky reads
  them.
tags: [format, strings, localization, plugin]
---

# Localized string tables

A plugin with the "localized" flag (`0x80` in the `TES4` header, see
[FormID](/formats/formid.md)) keeps no display text in its records. Where a record would
hold a zstring, it holds a uint32 string ID instead. This is called an "lstring". The text
is in a table per language: `Strings/<plugin>_<language>.<ext>`. The table can be a loose
file or inside a BSA. In vanilla it is in `Skyrim - Interface.bsa`. All five vanilla masters
are localized.

Reference: UESP
[String Table File Format](https://en.uesp.net/wiki/Skyrim_Mod:String_Table_File_Format).

## File layout

All integers are little-endian.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | uint32 | Entry count |
| 0x04 | uint32 | Size of the data block in bytes |
| 0x08 | 8 x count | Directory: uint32 ID, uint32 offset |
| 0x08 + 8 x count | bytes | Data block |

Each directory offset counts from the start of the data block. The extension sets how an
entry is stored:

| Extension | Entry | Used for |
| --- | --- | --- |
| `.strings` | zstring (ends with a null byte) | Names and UI text |
| `.dlstrings` | uint32 length (with the null) + zstring | Books and descriptions |
| `.ilstrings` | Same as `.dlstrings` | Dialogue lines |

## Decode rules

- If an ID appears twice in the directory, the first one wins. xEdit does the same.
- A directory offset outside the data block is an error when the file is opened. An entry
  that runs past the end of the block is an error when it is looked up.
- Extra bytes after the data block are allowed. A file shorter than the header says is not.
- A length-prefixed entry without its final null byte is allowed.
- The file does not say its text encoding. Some languages use UTF-8, others use old code
  pages. OpenSky uses the [string decoding](/decisions/string-decoding.md) policy: UTF-8
  when the bytes are valid UTF-8, else windows-1252, else ISO 8859-1.

The language comes from `[General] sLanguage`, see [INI settings](/formats/ini.md). When a
table is missing, lookups return nothing and OpenSky logs one error.

A string ID is local to the plugin that wrote the record. Two plugins can use the same ID
for different text. So a record's text is looked up in the tables of the
plugin whose record won in the load order, for example `dawnguard_english.strings`.

Real data check: all 273 table files in the vanilla archives (10 languages) decode with no
errors. Chinese, Japanese, and Russian use UTF-8. French and German use windows-1252.
