---
type: File Format
title: SWF shapes and bitmaps
description: DefineShape 1-4 layout, how OpenSky tessellates fills, and the lossless and
  JPEG bitmap tags.
tags: [format, swf, ui, shape, bitmap]
---

# SWF shapes and bitmaps

This page covers the shape tags and the bitmap tags in a SWF movie. The container is on
[SWF](/formats/swf.md).

References: Adobe SWF File Format Specification v19, chapter 6 "Shapes" (pp. 119-133),
chapter 7 "Gradients" (pp. 134-136), and chapter 8 "Bitmaps" (pp. 137-143).

## Shape tags

DefineShape (2), DefineShape2 (22), DefineShape3 (32), and DefineShape4 (83).

The body is `ShapeId` UI16, `ShapeBounds` RECT, then SHAPEWITHSTYLE. DefineShape4 puts two
more fields between the bounds and the styles: `EdgeBounds` RECT and a flag byte (Reserved
UB[5], `UsesFillWindingRule` UB[1] from SWF 10, `UsesNonScalingStrokes`,
`UsesScalingStrokes`).

SHAPEWITHSTYLE is FILLSTYLEARRAY, LINESTYLEARRAY, `NumFillBits` UB[4], `NumLineBits` UB[4],
then shape records. Style indices start at 1. Index 0 means no fill or no line.

Differences by version:

- Colors are RGB in DefineShape and DefineShape2, and RGBA in DefineShape3 and 4. This
  applies to FILLSTYLE, LINESTYLE, and GRADRECORD.
- A style count of 0xFF means "a UI16 count follows" from DefineShape2 on (spec p. 122). In
  DefineShape, 0xFF is a count of 255.
- DefineShape4 uses LINESTYLE2: cap, join, and scaling flags, an optional 8.8 miter limit,
  and either an RGBA color or a FILLSTYLE. Older versions use width plus color.
- The spec puts focal radial gradients (fill type 0x13, FOCALGRADIENT with a FIXED8 focal
  point) in DefineShape4 only. OpenSky accepts them in any version.

FILLSTYLE types: 0x00 solid, 0x10 linear gradient, 0x12 radial gradient, 0x13 focal radial
gradient, 0x40 to 0x43 bitmap (repeating or clipped, smoothed or not). A bitmap fill has a
bitmap character ID and a MATRIX.

Shape records are bit-packed and not byte-aligned. A TypeFlag bit picks the kind:

- Edge records: StraightEdgeRecord (general, vertical, or horizontal deltas) and
  CurvedEdgeRecord (quadratic Bezier control and anchor deltas). Both use SB[NumBits+2].
- Non-edge records: EndShapeRecord is six zero bits. StyleChangeRecord has an optional MoveTo
  (absolute, from the shape origin), FillStyle0, FillStyle1, and LineStyle selections read
  with the current bit widths, and optional new style arrays.

When a StyleChangeRecord brings new style arrays, OpenSky joins all arrays into one list and
shifts the indices. So an index means the same style for the whole shape. A font glyph is a
bare SHAPE with no style arrays, and its indices are used as they are.

Byte alignment: the spec says only RECT and MATRIX "must be byte aligned". OpenSky also
aligns before the GRADIENT after a fill's MATRIX, and before `NumFillBits` after the style
arrays. All vanilla shapes parse under this rule.

## Tessellation

OpenSky turns each shape into a triangle list in twips, grouped by fill style.

- Quadratic edges are split into equal steps. The step count comes from how far the control
  point is from the middle of the chord. The tolerance is 1 twip and the cap is 64 steps.
- FillStyle0 is the fill on the left of the edge direction. FillStyle1 is on the right
  (spec p. 128). For each fill, FillStyle1 edges go in forward and FillStyle0 edges go in
  reversed, so the outline has one direction. An edge with the same fill on both sides
  cancels out, so inner edges never split a fill.
- Triangles come from a sweep over horizontal bands. Bands split at every segment end `y`.
  The fill rule picks the spans, and each span becomes two triangles. Holes and separate
  outlines need no special handling. The fill rule is even-odd, or nonzero winding when
  DefineShape4 sets `UsesFillWindingRule`.
- Line styles are decoded but no line geometry is made. Vanilla UI art is almost all fills.

## Lossless bitmaps

DefineBitsLossless (20) and DefineBitsLossless2 (36): `CharacterID` UI16, `BitmapFormat`
UI8, width UI16, height UI16, then one zlib stream.

| format | tag 20 | tag 36 |
| --- | --- | --- |
| 3 | 8-bit color map, RGB table | 8-bit color map, RGBA table |
| 4 | PIX15: 1 reserved bit + 5/5/5 bits | not allowed |
| 5 | PIX24: reserved byte + RGB | 32-bit ARGB |

For format 3, `BitmapColorTableSize` (UI8) stores the count minus one. Rows of format 3 and
4 are padded to 32 bits.

The spec (p. 143) says tag-36 ARGB pixels are already multiplied by alpha. It says this only
for ARGB, not for RGBA color-map entries. So OpenSky treats color-mapped Lossless2 as not
premultiplied until data shows otherwise.

## JPEG bitmaps

- JPEGTables (8) holds the tables for DefineBits (6). A DefineBits body is only the scan.
  Both streams have SOI and EOI markers, so the image is the tables without EOI plus the
  scan without SOI.
- DefineBitsJPEG2 (21) is a complete image.
- DefineBitsJPEG3 (35) adds `AlphaDataOffset` UI32, then a zlib-compressed alpha plane with
  one byte per pixel after the image.
- DefineBitsJPEG4 (90) also adds `DeblockParam` UI16 (8.8 fixed point).
- Data from before SWF 8 may start with a wrong `FF D9 FF D8` prefix. OpenSky removes it.
- From SWF 8 the data may be PNG or GIF89a instead, found by signature. The alpha plane
  applies to JPEG only (spec p. 139).

## Vanilla shapes and bitmaps

- 2,677 shapes, all tessellated: DefineShape 944, DefineShape2 1,097, DefineShape3 574,
  DefineShape4 62. They give 2,195,435 triangles.
- 453 bitmaps: 451 DefineBitsLossless2 32-bit ARGB, and 2 DefineBits JPEG scans in
  `sharedcomponents.swf`. Its JPEGTables tag is empty (0 bytes), and the scans decode
  without it.
- Vanilla has no color-mapped, 15-bit, or 24-bit lossless bitmaps, and no DefineBitsJPEG2,
  3, or 4, PNG, or GIF data.
