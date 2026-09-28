---
type: File Format
title: UI translation strings
description: UTF-16 Interface/Translations/*.txt files and how OpenSky resolves $KEY UI tokens.
tags: [format, strings, localization, ui, scaleform]
---

# UI translation strings

Scaleform menus (the in-game UI) show text through `$KEY` tokens, not literal strings. A
token is looked up in text files at `Interface/Translations/<name>_<language>.txt`. The
files are loose under `Data/` or inside a BSA.

This is not the same as the plugin [string tables](/formats/strings.md). String tables hold
record text under a number. Translation files hold menu text under a `$` name.

Sources (the Creation Kit page "Translation files" was offline, so these were used):

- SkyUI `skyui-lib` wiki [How to](https://github.com/schlangster/skyui-lib/wiki/How-to):
  files are "UTF16 Little Endian (aka UCS-2 Little Endian) with BOM", with
  "tab-separated string values" and keys that start with `$`.
- [ScaleformTranslationPP](https://github.com/VersuchDrei/ScaleformTranslationPP):
  "Scaleform parses keys case-sensitively".

## File layout

- UTF-16 little-endian, starting with the byte-order mark (BOM) `FF FE`.
- One pair per line: `$key<TAB>value`. The key ends at the first tab. The value is the rest
  of the line, so it can contain more tabs.
- Vanilla-style files end lines with CRLF.
- Keys keep their `$` and their exact case.
- A value can hold `{}` or `{$OtherKey}` placeholders. OpenSky stores the value as it is and
  does not expand placeholders yet.

Example line: `$Continue<TAB>Continue`.

## Parse rules

- `FF FE` means little-endian and `FE FF` means big-endian. With no BOM, OpenSky assumes
  little-endian.
- CRLF, a lone LF, and a final newline all work. In Swift, CRLF is one `Character`, so the
  split must test `Character.isNewline`. A split on `"\n"` misses every CRLF line.
- A line with no tab is skipped. An empty key is skipped. An empty value is kept.
- When a key appears twice in a file, the later line wins.
- `$Key` and `$key` are different keys, as in Scaleform.
- Bytes that are not valid UTF-16, such as a lone surrogate, make the file fail. OpenSky logs
  it and skips that file.

## Lookup

All files for the language are merged into one map. Files are read in sorted path order,
and on a clash the later file wins. This order is a placeholder until mod load order applies
here too.

An unknown `$KEY`, or a token without `$`, is shown as it is. This matches what players see
in the game: an unresolved `$KEY` stays visible on screen.

`Developer > UI Lab` has a preview that shows sample strings through this lookup, including
the unknown-key case.

## Vanilla has no translation files

The vanilla archives contain no files under `Interface/Translations/`. Vanilla Skyrim SE
keeps its UI text in the `.strings` tables. Translation files come from SkyUI, other mods,
Creation Club content, and some non-English builds.
