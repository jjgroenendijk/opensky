---
type: File Format
title: Localized string tables
description: Layout of .strings, .dlstrings, and .ilstrings tables and how OpenSky decodes them.
tags: [format, strings, localization, plugin]
---

# Localized string tables

A plugin with the TES4 "localized" flag (`0x80`, see [FormID](/formats/formid.md)) stores
no display text in its records. Where a record would hold a zstring, it holds a uint32
string ID. The ID points into a table at `Strings/<plugin>_<language>.<ext>`. The table is a
loose file or sits in a BSA (for vanilla: `Skyrim - Interface.bsa`). All five vanilla master
files are localized.

Source: UESP
[String Table File Format](https://en.uesp.net/wiki/Skyrim_Mod:String_Table_File_Format).

## File layout

All integers are little-endian.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0x00 | uint32 | Entry count |
| 0x04 | uint32 | Size of the data block in bytes |
| 0x08 | 8 x count | Directory: uint32 ID, uint32 offset |
| 0x08 + 8 x count | bytes | Data block |

A directory offset counts from the start of the data block. Each extension frames an entry
differently:

- `.strings`: a zstring (ends with a null byte). Names and UI text.
- `.dlstrings`: a uint32 length (null included), then the zstring. Books and descriptions.
- `.ilstrings`: the same as `.dlstrings`. Dialogue lines.

## Decode rules

- When two directory entries share an ID, the first wins. xEdit does the same.
- A directory offset outside the data block is an error. So is an entry that runs past the
  end of the block. Extra bytes after the block are allowed.
- A length-prefixed entry without its final null byte is accepted.
- The file does not say its encoding. Some languages use UTF-8 and some use old code pages.
  OpenSky uses the [string decoding](/decisions/string-decoding.md) rule: UTF-8 if valid,
  else windows-1252, else ISO 8859-1.

The language comes from `[General] sLanguage` (see [INI settings](/formats/ini.md)). A
missing table gives empty lookups and one logged error.

Confirmed on the real install: every table in the vanilla archives, in all 10 languages,
decodes. Chinese, Japanese, and Russian are UTF-8. French and German are windows-1252.
