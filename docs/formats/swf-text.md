---
type: File Format
title: SWF fonts and text
description: DefineFont2/3, the font companion tags, DefineText and DefineEditText, glyph
  paths, and the Scaleform fontconfig.txt mapping.
tags: [format, swf, ui, font, text, scaleform]
---

# SWF fonts and text

This page covers the font and text tags in a SWF movie, and the Scaleform file that maps
font names. The container is on [SWF](swf.md). The glyph atlas is on
[screen-space UI layer](../rendering/ui.md).

Reference: Adobe SWF File Format Specification v19, chapter 10 "Fonts and Text"
(pp. 173-182).

## DefineFont2 (48) and DefineFont3 (75)

The body is `FontID` UI16, a flag byte (MSB first: `HasLayout`, `ShiftJIS`, `SmallText`,
`ANSI`, `WideOffsets`, `WideCodes`, `Italic`, `Bold`), `LanguageCode` UI8, a
length-prefixed `FontName`, `NumGlyphs` UI16, then:

- OffsetTable: `NumGlyphs` offsets plus one `CodeTableOffset`. Each is UI32 with
  `WideOffsets`, else UI16. Offsets count from the start of the OffsetTable. OpenSky cuts
  each glyph out by offset, so padding between glyphs does not matter.
- GlyphShapeTable: one bare SHAPE per glyph (`NumFillBits`, `NumLineBits`, shape records,
  no style arrays). Fill index 0 is off and 1 is on. See
  [SWF shapes](swf-shapes.md).
- CodeTable: `NumGlyphs` character codes, UI16 with `WideCodes`, else UI8.
- Layout, only with `HasLayout`: `FontAscent`, `FontDescent`, `FontLeading` SI16, an SI16
  advance per glyph, a bit-packed RECT per glyph, then `KerningCount` UI16 and the kerning
  records (a code pair sized by `WideCodes`, then an SI16 adjustment).

DefineFont3 has the same bytes, but its glyph and layout values use an EM square 20 times
finer (spec p. 179). The EM square is 1024 units for DefineFont2 and 20480 for DefineFont3.
To get pixels, multiply by `fontSize / unitsPerEM`.

A device-font placeholder has `NumGlyphs == 0` and no OffsetTable, CodeTable, or layout.
`hudmenu.swf` has one.

## Companion tags

OpenSky draws glyphs with its own CoreGraphics path, so it reads these tags but does not use
the FlashType hinting they carry:

- DefineFontAlignZones (73): `FontID` UI16 and `CSMTableHint` UB[2]. The per-glyph zone
  table needs the font's glyph count and is kept raw.
- CSMTextSettings (74): `TextID`, `UseFlashType`, `GridFit`, and `Thickness` and
  `Sharpness` as FLOAT32.
- DefineFontName (88): the full font name and the copyright string.

## Glyph paths

A glyph's straight and quadratic edges become a CoreGraphics path. The path is scaled by
`fontSize / unitsPerEM` and flipped, because SWF glyph space points down and CoreGraphics
points up. The baseline is at the origin. Glyphs fill even-odd. A glyph with no edges (a
space) draws nothing.

## DefineText (11) and DefineText2 (33)

The body is `CharacterID` UI16, `TextBounds` RECT, `TextMatrix` MATRIX, `GlyphBits` UI8,
`AdvanceBits` UI8, then TEXTRECORDs up to a zero byte.

Each TEXTRECORD starts with a byte-aligned flag byte. It selects optional changes in this
order: font ID and text height, color, x offset, y offset. Then comes `GlyphCount` UI8 and
that many GLYPHENTRYs: `GlyphIndex` UB[GlyphBits] and `GlyphAdvance` SB[AdvanceBits]. The
next record aligns to a byte again. A record without a field keeps the value from earlier
records. DefineText2 colors are RGBA; DefineText colors are RGB. Glyph indices point into
the current font's glyph table, so no text shaping is needed.

## DefineEditText (37)

The body is `CharacterID` UI16, `Bounds` RECT, then a 16-bit flag word, MSB first:
`HasText`, `WordWrap`, `Multiline`, `Password`, `ReadOnly`, `HasTextColor`, `HasMaxLength`,
`HasFont`, `HasFontClass`, `AutoSize`, `HasLayout`, `NoSelect`, `Border`, `WasStatic`,
`HTML`, `UseOutlines`.

The flags turn on these fields, in order:

| field | present when |
| --- | --- |
| `FontID` UI16 | `HasFont` |
| `FontClass` STRING | `HasFontClass` |
| `FontHeight` UI16 | `HasFont` or `HasFontClass` |
| `TextColor` RGBA | `HasTextColor` |
| `MaxLength` UI16 | `HasMaxLength` |
| `Align` UI8, `LeftMargin` UI16, `RightMargin` UI16, `Indent` SI16, `Leading` SI16 | `HasLayout` |
| `VariableName` STRING | always |
| `InitialText` STRING | `HasText` |

STRINGs end with a zero byte. SWF 6 and later say strings are UTF-8, but older movies use
code-page bytes, so OpenSky decodes them leniently
([string decoding](../decisions/string-decoding.md)). An HTML field keeps its markup; see
[HTML text](#html-text).

The spec gives `Indent` as UI16, but `craftingmenu.swf` stores 65534 there for the bottom bar's
skill label. Read unsigned, the name lands about 3,000 pixels to the right; the game draws it in
place, so OpenSky reads `Indent` as SI16 (-2 twips).

Byte alignment: the spec says only RECT and MATRIX align. OpenSky aligns before the flag
word and reads it as two whole bytes, so the UI16 fields after it are aligned. All vanilla
text tags decode under this rule.

## fontconfig.txt

The game has `Interface/fontconfig.txt`. It maps font names used by movies (aliases) to fonts
defined in font library movies. No public specification exists. This grammar is what the
vanilla file shows:

- `fontlib "<Interface\movie.swf>"` declares a movie whose fonts back the aliases. The path
  is relative to the install and already has the `Interface\` prefix.
- `map "$Alias" = "FontName" [Style ...]` maps an alias such as `$EverywhereFont` to a font.
  Style words (`Normal`, `Bold`, `Italic`) may follow; OpenSky keeps them but does not match
  on them.
- `#` starts a comment to the end of the line, outside quotes. Blank lines are ignored.

- `validNameChars <characters>` lists the characters a typed name may use: everything after the
  keyword to the end of the line, read as written, quotes and spaces included.

Other lines, such as `mapdefault`, are kept and reported as not understood.

To resolve an alias, OpenSky finds its `map` line, then looks for a font with that name in
the font libraries: exact match first, then without regard to case. It is not known whether
GFx matches a `map` name against a font's export name (see ExportAssets on
[SWF display list](swf-display-list.md)) or its internal name, so both are tried.

### Finding a font in the game

The game reads the file one command per line, without regard to case. A line that starts with `[`
is skipped. A style word after a `map` line forces that style on the text; with no style word, or
an unknown one, the text keeps its own style. `validNameChars` sets the characters a name may use.

The game looks for a font in this order:

1. The `map` lines turn the asked name into the font's real name.
2. The movie's own fonts and its imports. An import can lead on to a font library.
3. The font libraries.
4. The font libraries again, now also taking fonts that are not marked as device fonts.

The operating system's fonts are never used. A text field with no font named asks for
`Times New Roman`, size 12, black, by the same order, so it shows only through a `map` line or a
font library. When nothing matches, the game logs the missing font once per field. The text is
laid out but draws no glyphs. The game's own debug text uses `$ConsoleFont`.

## HTML text

An HTML field's `InitialText`, and a string a script assigns to `htmlText`, is a small set of
Flash HTML. The tags vanilla uses are `<p align>`, `<font face size color letterSpacing
kerning>`, `<b>`, and `<img>`.

- `<font>` starts a style that holds until its `</font>`. `color` is `#RRGGBB`. `size` is in
  pixels, so `size='20'` is 400 twips. `face` names a font, usually a fontconfig alias such as
  `$EverywhereBoldFont`. `letterSpacing` adds pixels after each character. A tag inside
  another keeps the outer values it does not set.
- `<p align>` sets the paragraph's alignment: `left`, `right`, `center`, or `justify`.
  `</p>` and `<br>` end a line. The plain text gets a carriage return there, as Flash's `text`
  shows it, but not for the last `</p>`.
- `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&nbsp;`, and numeric entities such as `&#65;`
  decode to their characters. An unknown one stays as written.
- Each style draws as its own run, in its own font, size, and colour. Kerning applies only
  inside one style.
- `<img>` draws a bitmap in the line ([AS2 display runtime](../engine/as2-display-runtime.md#text)).
- `<b>` and `kerning` change nothing: vanilla picks a bold font through `face`.

## Vanilla fonts and text

- 97 fonts. 96 have a layout block. 54,988 glyphs: 54,987 have a code, and 34,379 have
  edges (the rest are blank, such as spaces). 17,336 kerning pairs.
- 676 DefineEditText (655 with initial text, 582 HTML) and no DefineText or DefineText2.
  All vanilla UI text is dynamic. The HTML tags in the initial texts: 642 `<p>` (60 with
  `align`), 589 `<font>` (all with `face`, 586 also with `size`, `color`, `letterSpacing`, and
  `kerning`), and 84 `<b>`.
- `fontconfig.txt` declares 3 font libraries (`fonts_console.swf`, `fonts_en.swf`,
  `fonts_cclub.swf`) and 20 `map` aliases. All 20 resolve.
- All 595 edit texts with content find a font and lay out 14,643 glyphs, none missing.
  Without ImportAssets, 523 of them find no font. One font name has no match anywhere:
  `Times New Roman` in `hudmenu.swf`.
