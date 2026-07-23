---
type: File Format
title: UI translation strings
description: UTF-16 Interface/Translations/*.txt files and how OpenSky resolves $KEY UI tokens.
tags: [format, strings, localization, ui, scaleform]
timestamp: 2026-07-23T00:00:00Z
---

# UI translation strings, Skyrim SE

Scaleform UI menus and the HUD reference localized text with `$KEY` tokens
instead of literal strings. A token resolves against per-language text files at
`Interface/Translations/<name>_<language>.txt` — loose under `Data/` or inside a
BSA (vanilla ships `Skyrim - Interface.bsa`). This is a different mechanism from
the plugin [string tables](/formats/strings.md): string tables hold record
display text keyed by numeric lstring ID, while translation files hold UI menu
text keyed by a `$`-prefixed name.

References (the Creation Kit wiki "Translation files" page was offline at
authoring; confirmed against the community mirrors below):

* SkyUI `skyui-lib` wiki "How to"
  (<https://github.com/schlangster/skyui-lib/wiki/How-to>): "The text files have
  to use the UTF16 Little Endian (aka UCS-2 Little Endian) with BOM encoding";
  "tab-separated string values"; keys prefixed with `$`.
* ScaleformTranslationPP (<https://github.com/VersuchDrei/ScaleformTranslationPP>):
  "Scaleform parses keys case-sensitively".

Impl: `opensky/Formats/Strings/TranslationFile.swift` (parser),
`opensky/GameData/LocalizedLabels.swift` (provider + discovery).

## File layout

* Text encoding: UTF-16 little-endian with a leading byte-order mark
  (`FF FE`). Effectively UCS-2 in practice; surrogate pairs decode normally.
* One `$key<TAB>value` pair per line. The key runs from line start to the first
  tab; the value is the rest of the line (so a value may itself contain tabs).
* Lines end with CRLF in vanilla files.
* Keys keep their leading `$` and exact case.
* File naming: `<name>_<language>.txt`, for example `skyui_se_english.txt`,
  under `Interface/Translations/`.
* Values may embed `{}` / `{$OtherKey}` placeholders for Scaleform nesting and
  runtime substitution; OpenSky stores the raw value and does not yet expand
  placeholders (future work, tracked with the SWF menu runtime, issue #99).

## OpenSky parse policy

* Byte-order mark selects endianness: `FF FE` little-endian, `FE FF`
  big-endian; without a mark, little-endian is assumed per the spec. Decoded
  eagerly (files are small).
* Line splitting tolerates CRLF, lone LF, and a trailing newline. Note CRLF is a
  single Swift grapheme, so splitting on any newline scalar (`Character.isNewline`)
  is required — a plain `"\n"` split silently misses every CRLF line.
* A line with no tab (blank lines, stray text) is skipped rather than rejecting
  the whole file (mod-quirk rule, AGENTS.md). An empty key is skipped; an empty
  value is kept.
* Duplicate key within a file: the later line wins (override semantics).
* Keys are case-sensitive, matching Scaleform. `$Key` and `$key` are distinct.
* Encoding failures (odd input is tolerated by the decoder; a genuinely invalid
  UTF-16 sequence such as an unpaired surrogate) throw `notUTF16`; the provider
  logs and skips that file rather than failing the load.

## Provider

`LocalizedLabels` merges every discovered `<name>_<language>.txt` into one
`$key -> value` map. `LocalizedLabels.load(vfs:language:)` discovers files under
`Interface/Translations/` through the VFS (loose files and archives, via the new
`VirtualFileSystem.fileNames(inDirectory:)`), parses each, and skips malformed
files with one os_log error. Language defaults to "english" until a language
setting exists (same open question as the string tables).

API for consumers (HUD M8.2, SWF menus issue #99, UI Lab preview M8.1.4):

* `label(for token: String) -> String` — a token beginning with `$` is looked
  up; an unknown key, or any token without a `$`, returns unchanged. Returning
  the token verbatim is the vanilla-observable behavior for an unresolved `$KEY`
  (it stays visible on screen). Decision recorded here; revisit if SWF runtime
  work shows a different fallback.
* `value(forKey key: String) -> String?` — raw lookup, nil when absent.
* `keyCount`, `fileCount`, `language` — inspection.

Merge order across files is the VFS discovery order (sorted paths), last file
wins on a key collision — provisional, pending real plugin/mod load-order
(same open question noted for archive ordering in [VFS](/formats/vfs.md)).

## Verification

Unit tests: `openskyTests/TranslationFileTests.swift` and
`openskyTests/LocalizedLabelsTests.swift` (synthetic fixtures built in code,
`TranslationFileFixture` — never extracted files). Cover BOM/no-BOM, CRLF/LF,
missing tab, empty value, duplicate keys, case sensitivity, non-ASCII and
surrogate-pair values, big-endian tolerance, truncated bytes, provider merge and
`$KEY` fallback, and VFS loose+archive discovery.

Runtime probe 2026-07-23 against the real install (env-gated scratch test, not
committed): 172 750 archive entries enumerated across the vanilla BSAs, zero
files under `Interface/Translations/`. Vanilla Skyrim SE ships its own UI text in
the `.strings` tables, not this mechanism; translation `.txt` files come from
SkyUI, other mods, Creation Club content, and non-English localized builds. The
discovery and load path ran end to end without error and returned an empty
provider, exercising the wiring against real data.
