---
type: File Format
title: UI translation strings
description: UTF-16 Interface/Translations/*.txt files and how OpenSky resolves $KEY tokens
  in the UI.
tags: [format, strings, localization, ui, scaleform]
---

# UI translation strings

Scaleform menus and the HUD use `$KEY` tokens instead of literal text, for example
`$Inventory`. A token is looked up in text files at
`Interface/Translations/<name>_<language>.txt`, for example `skyui_se_english.txt`. The file
can be loose or inside a BSA.

This is not the same as the plugin [string tables](/formats/strings.md). A string table
holds record text and is keyed by a number. A translation file holds menu text and is keyed
by a name that starts with `$`.

References. The Creation Kit wiki page "Translation files" was offline, so these community
sources were used:

- SkyUI `skyui-lib` wiki [How to](https://github.com/schlangster/skyui-lib/wiki/How-to):
  "The text files have to use the UTF16 Little Endian (aka UCS-2 Little Endian) with BOM
  encoding", "tab-separated string values", and keys start with `$`.
- [ScaleformTranslationPP](https://github.com/VersuchDrei/ScaleformTranslationPP):
  "Scaleform parses keys case-sensitively".

## File layout

- UTF-16 little-endian, starting with the byte-order mark `FF FE`.
- One `$key<TAB>value` pair per line. The key ends at the first tab. The value is the rest
  of the line and may contain more tabs.
- Vanilla-style files end lines with CRLF.
- A key keeps its `$` and its exact case. `$Key` and `$key` are different keys.
- A value may hold `{}` slots. The parser keeps the raw value; the lookup fills the slots.

## Parse rules

- The byte-order mark sets the byte order: `FF FE` little-endian, `FE FF` big-endian. With
  no mark, OpenSky assumes little-endian, as the source says.
- Lines may end with CRLF or LF. In Swift, CRLF is one `Character`, so splitting on `"\n"`
  misses CRLF lines. The parser splits on `Character.isNewline`.
- A line without a tab is skipped. An empty key is skipped. An empty value is kept.
- When a key appears twice in one file, the later line wins.
- Invalid UTF-16, such as a lone surrogate, fails that file only. OpenSky logs it and skips
  the file.

## Lookup

OpenSky merges all files for the chosen language into one map. Files load in sorted path
order, and the last file wins when two share a key.

A token can carry arguments in braces. SkyUI's `skyui-lib` wiki gives this example: the menu
script builds `"$Enemy hits you for {" + myDamage + "} damage."`, and the file holds
`$Enemy hits you for {} damage.<TAB>Enemy hits you for {} damage.` When `myDamage` is 10,
the game shows "Enemy hits you for 10 damage."

OpenSky resolves such a token in these steps:

1. A token that is a key as written resolves to its value. No argument is read.
2. Otherwise each `{...}` group is one argument. The key is the token with each group
   emptied to `{}`. For example, `$Pair{a}{b}` looks up `$Pair{}{}`.
3. Each `{}` in the value takes the next argument, in order. A `{}` past the last argument
   stays `{}`.
4. An argument that starts with `$` is resolved first, by the same steps. So `$Pair{$Gold}{3}`
   shows the value of `$Gold`. The wiki calls the feature "nested translations"; that the
   argument itself is looked up is OpenSky's reading of that name, not a tested game fact.
5. Braces that do not pair up, or a key that is not found, leave the whole token as written.

The vanilla `translate_english.txt` has no braces at all (checked on the install), so only
mod files use arguments.

A token that is not found is shown as it is, for example `$Unknown`. A string without `$`
is also shown as it is. The game also leaves an unknown `$KEY` visible on screen.

## The vanilla file

Vanilla Skyrim SE ships one file per language at the archive root of the interface folder,
for example `interface\translate_english.txt` in `Skyrim - Interface.bsa` (seen on the
install). The vanilla archives hold no files under `Interface/Translations/`; those come
from SkyUI, other mods, and Creation Club content.

OpenSky loads the vanilla file first, then each `Interface/Translations/` file over it. The
running game passes every `$KEY` text in a menu movie through this map, so a menu shows real
words such as "Settings" in place of `$SETTINGS`.
