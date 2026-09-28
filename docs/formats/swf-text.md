---
type: File Format
title: SWF fonts and text
description: DefineFont2 and DefineFont3, glyph drawing, DefineText and DefineEditText, and the
  Scaleform fontconfig.txt font mapping.
tags: [format, swf, ui, font, text, scaleform]
---

# SWF fonts and text

The container is on the [SWF](/formats/swf.md) page. Source: Adobe SWF specification, version 19,
chapter 10 "Fonts and Text" (pp. 173-182). The glyph atlas is on the
[screen-space UI](/rendering/ui.md) page.

## Font tags

DefineFont2 (48) and DefineFont3 (75).

Body: `FontID` uint16, a flag byte, `LanguageCode` uint8, a `FontName` with a length prefix,
`NumGlyphs` uint16, then:

- Offset table: one entry per glyph, then `CodeTableOffset`. Each entry is uint32 with
  `WideOffsets`, else uint16. Offsets count from the start of the offset table. OpenSky cuts each
  glyph out by its offsets, so any padding between glyphs does not matter.
- Glyph shapes: one bare SHAPE per glyph (see [SWF shapes](/formats/swf-shapes.md)). Fill 0 is
  off and fill 1 is on.
- Code table: one character code per glyph. uint16 with `WideCodes`, else uint8.
- Layout, only with `HasLayout`: ascent, descent, and leading (int16), one int16 advance per
  glyph, one RECT per glyph, then a kerning count and kerning records. A kerning record is a code
  pair (size set by `WideCodes`) and an int16 adjustment.

The flag byte, from the high bit: `HasLayout`, `ShiftJIS`, `SmallText`, `ANSI`, `WideOffsets`,
`WideCodes`, `Italic`, `Bold`.

DefineFont3 is the same as DefineFont2, but its coordinates use an EM square 20 times finer
(p. 179). So units per EM is 1024 for DefineFont2 and 20480 for DefineFont3. To get pixels,
scale by `emPixelSize / unitsPerEM`.

A font with 0 glyphs has no offset table, code table, or layout. It is a placeholder for a font
from another movie. `hudmenu.swf` has one. It decodes to an empty font.

## Font companion tags

OpenSky draws glyphs itself with CoreGraphics, so it reads these tags but does not use them:

- DefineFontAlignZones (73): `FontID` and a 2-bit `CSMTableHint`. The zone records are kept raw,
  because their size depends on the font's glyph count.
- CSMTextSettings (74): `TextID`, `UseFlashType`, `GridFit`, and the float `Thickness` and
  `Sharpness`.
- DefineFontName (88): the full font name and the copyright text.

## Drawing a glyph

A glyph's straight and curved edges become a CoreGraphics path. It is scaled by
`emPixelSize / unitsPerEM`, and flipped from the SWF y-down space to y-up, with the baseline at
the origin. It fills even-odd, as SWF glyphs do. An empty glyph, such as a space, draws nothing.

## DefineText and DefineText2

DefineText (11) and DefineText2 (33): `CharacterID` uint16, `TextBounds` RECT, `TextMatrix`
MATRIX, `GlyphBits` uint8, `AdvanceBits` uint8, then text records up to a zero byte.

Each text record starts with a flag byte. The flags say which state changes follow, in this
order: font ID and text height, color, x offset, y offset. Then comes `GlyphCount` (uint8), and
that many glyph entries. A glyph entry is a glyph index of `GlyphBits` bits and an advance of
`AdvanceBits` bits. The next record starts on a whole byte. A record keeps the state it does not
change from earlier records. DefineText2 colors are RGBA, DefineText colors are RGB.

The glyph index points into the current font, so static text needs no text shaping.

Vanilla has no DefineText or DefineText2 at all. All vanilla menu text is DefineEditText.

## DefineEditText

DefineEditText (37): `CharacterID` uint16, `Bounds` RECT, then a 16-bit flag word. From the high
bit: `HasText`, `WordWrap`, `Multiline`, `Password`, `ReadOnly`, `HasTextColor`, `HasMaxLength`,
`HasFont`, `HasFontClass`, `AutoSize`, `HasLayout`, `NoSelect`, `Border`, `WasStatic`, `HTML`,
`UseOutlines`.

Then, each only when its flag is set:

| Field | Flag |
| --- | --- |
| `FontID` | `HasFont` |
| `FontClass` string | `HasFontClass` |
| `FontHeight` | `HasFont` or `HasFontClass` |
| `TextColor` RGBA | `HasTextColor` |
| `MaxLength` | `HasMaxLength` |
| Align, margins, indent, leading | `HasLayout` |
| `VariableName` string | always |
| `InitialText` string | `HasText` |

Strings end in a zero byte and use the [string decoding](/decisions/string-decoding.md) rules.
SWF 6 and later say strings are UTF-8, but older movies use code pages. An HTML field keeps its
markup, and also gives a plain-text version without tags.

OpenSky moves to a whole byte before the flag word and reads it as two bytes. This keeps the
uint16 fields after it aligned. Every vanilla text tag decodes with this rule.

In vanilla, most edit text fields import their font from a font library movie. So `FontID`
usually names a character the movie does not define itself (see
[imports](/formats/swf-display-list.md#imports)).

## fontconfig.txt

The game has `Interface/fontconfig.txt`. It maps font aliases to fonts inside font library
movies. There is no public specification. This grammar is what the file shows:

- `fontlib "<Interface\movie.swf>"` names a movie whose fonts back the aliases. The path already
  starts with `Interface\` in vanilla.
- `map "$Alias" = "FontName" [Style ...]` maps an alias, such as `$EverywhereFont`, to a font
  name. The style words (`Normal`, `Bold`, `Italic`) are kept but not used for matching.
- `#` starts a comment to the end of the line, outside quotes. Blank lines are ignored.

Any other line, such as vanilla's `mapdefault` and `validNameChars`, is kept and reported, not
dropped.

To resolve an alias: find its `map` line, then find a font with that name in the font library
movies. It is not known whether the name matches a font's export name or its internal name. So
OpenSky tries both, exact first, then without regard to case.

Vanilla `fontconfig.txt` names three font libraries: `fonts_console.swf`, `fonts_en.swf`, and
`fonts_cclub.swf`. Every `map` alias resolves. One font name in the whole install does not
resolve: `Times New Roman`, used in `hudmenu.swf`.
