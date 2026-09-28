---
type: File Format
title: SWF shapes and bitmaps
description: DefineShape 1 to 4, fill and line styles, shape records, how OpenSky turns a shape
  into triangles, and the lossless and JPEG bitmap tags.
tags: [format, swf, ui, shape, bitmap]
---

# SWF shapes and bitmaps

Shapes are the vector art of a menu. Bitmaps are its images. The container is on the
[SWF](/formats/swf.md) page. Source: Adobe SWF specification, version 19, chapter 6 "Shapes"
(pp. 119-133), chapter 7 "Gradients" (pp. 134-136), and chapter 8 "Bitmaps" (pp. 137-143).

## Shape tags

DefineShape (2), DefineShape2 (22), DefineShape3 (32), and DefineShape4 (83).

Body: `ShapeId` uint16, `ShapeBounds` RECT, then SHAPEWITHSTYLE. DefineShape4 puts an
`EdgeBounds` RECT and a flag byte between the bounds and the styles. The flag byte is 5 reserved
bits, then `UsesFillWindingRule` (SWF 10 and later), `UsesNonScalingStrokes`, and
`UsesScalingStrokes`.

SHAPEWITHSTYLE is: fill style array, line style array, `NumFillBits` (4 bits), `NumLineBits`
(4 bits), then shape records. Style numbers start at 1. Style 0 means no fill or no line.

Rules that change with the version:

- Colors are RGB in DefineShape and DefineShape2, and RGBA in DefineShape3 and 4.
- A style count of `0xFF` means "a uint16 count follows" from DefineShape2 on (p. 122). In
  DefineShape it is a real count of 255.
- DefineShape4 uses LINESTYLE2: cap, join, and scaling flags, an optional 8.8 miter limit, and
  either an RGBA color or a fill style. Earlier versions use width and color.
- Focal radial gradients (fill type `0x13`, with an 8.8 focal point) belong to DefineShape4.
  OpenSky accepts them in any version.

Fill types: `0x00` solid, `0x10` linear gradient, `0x12` radial gradient, `0x13` focal radial
gradient, `0x40` to `0x43` bitmap (repeating or clipped, smoothed or not). A bitmap fill has a
bitmap character ID and a MATRIX.

## Shape records

Shape records are bit fields with no byte alignment. The first bit picks the kind:

- Edge records: a straight edge (general, vertical, or horizontal deltas) or a curved edge
  (quadratic Bezier control and anchor deltas). Both use signed fields of `NumBits + 2` bits.
- Non-edge records: six zero bits end the shape. Otherwise it is a style change: an optional
  move to an absolute point, new FillStyle0, FillStyle1, and LineStyle numbers, and optional new
  style arrays.

OpenSky joins all new style arrays into one list for the whole shape, and renumbers the records.
So a style number means the same thing everywhere in the shape. A font glyph is a bare SHAPE
with no style arrays, and keeps its numbers as they are.

The specification says RECT and MATRIX must be byte-aligned, but says nothing about other
fields. OpenSky also aligns two more places: the GRADIENT after a fill's MATRIX, and the
`NumFillBits` field after the style arrays. Every vanilla shape parses with this rule.

## Tessellation

Tessellation turns a shape into triangles. The result is a list of triangles in twips, grouped
by fill style. It is cached by shape ID.

- A curve is cut into straight pieces. The number of pieces comes from how far the control
  point is from the middle of the chord: 1 twip tolerance, at most 64 pieces. The result is the
  same every time.
- FillStyle0 is the fill on the left of an edge's direction, FillStyle1 on the right (p. 128).
  For each fill, FillStyle1 edges go in forward and FillStyle0 edges go in reversed. This gives
  one consistent outline. An edge with the same fill on both sides cancels out, so inner edges
  never split a fill.
- Triangles come from a sweep over horizontal bands. A band boundary is at every edge end
  point. The fill rule picks the spans, and each span gives a trapezoid of two triangles. Holes
  and separate outlines need no extra work. The rule is even-odd, or nonzero winding when
  DefineShape4 sets `UsesFillWindingRule`.
- Lines are not turned into triangles yet. Vanilla menu art is almost all fills.

## Lossless bitmaps

DefineBitsLossless (20) and DefineBitsLossless2 (36): `CharacterID` uint16, `BitmapFormat` uint8,
width and height uint16, then one zlib stream.

| Format | Meaning |
| --- | --- |
| 3 | 8-bit palette. A uint8 gives the palette size minus 1. RGB palette in tag 20, RGBA in tag 36. Rows are padded to 4 bytes |
| 4 | 15-bit color, tag 20 only. 1 reserved bit and 5/5/5 bits. Rows padded |
| 5 | Tag 20: a reserved byte and RGB. Tag 36: 32-bit ARGB |

The expected unpacked size comes from the format, size, and padding, and is checked.

Tag 36 ARGB pixels are already multiplied by alpha (p. 143), so they are passed on as
premultiplied. The specification states this only for ARGB pixels, not for palette entries. So
OpenSky marks palette output as not premultiplied until real data shows otherwise.

## JPEG bitmaps

- JPEGTables (8) holds the movie's shared JPEG tables for DefineBits (6), whose body is only the
  image scan. Both parts have start and end markers. The decodable image is the tables without
  their end marker, then the scan without its start marker.
- DefineBitsJPEG2 (21) is a complete image.
- DefineBitsJPEG3 (35) adds `AlphaDataOffset` (uint32) and a zlib-packed alpha plane with one
  byte per pixel after the image.
- DefineBitsJPEG4 (90) also adds `DeblockParam` (uint16, 8.8 fixed point). It is read but not
  used.

Files before SWF 8 can start with a wrong `FF D9 FF D8` prefix. OpenSky removes it. From SWF 8 the
data can be PNG or GIF89a, found by its signature. The alpha plane applies to JPEG only (p. 139).
Images are decoded with Apple's ImageIO. No third-party decoder is used.

In vanilla, every bitmap is DefineBitsLossless2 32-bit ARGB, except two DefineBits JPEG scans in
`sharedcomponents.swf`. Its JPEGTables tag is empty, and the scans decode without it.
