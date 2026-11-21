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
chapter 7 "Gradients" (pp. 134-136), chapter 8 "Bitmaps" (pp. 137-143), and the chapter
"Shape Morphing".

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

## Gradients

A GRADIENT holds a spread mode, an interpolation mode, and up to 15 GRADRECORD stops. Each
stop has a ratio from 0 to 255 and a colour (spec chapter 7, pp. 134-136).

- A gradient fill maps the shape through its MATRIX into a square from -16384 to 16384
  twips. A linear fill reads its colour from x; a radial fill reads it from the distance to
  the centre.
- Between two stops the colour mixes by the ratio. Before the first stop and after the last
  one, the colour is the stop's own (pad).
- Interpolation mode 0 mixes the stored sRGB values. Mode 1, linear RGB, turns the colour
  channels into linear light first, mixes them, and turns them back. Example: red to blue
  half way is 128 in mode 0 and 188 in mode 1. Alpha always mixes straight.
- A focal radial gradient (type 0x13) adds a FIXED8 focal point from -1 to 1 on the x axis
  of the square. Ratio 0 sits at the focal point and ratio 255 on the circle of radius 1, so
  the bright centre moves to one side.

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
- Strokes are cut after the fills and drawn over them (see below).

## Strokes

A LINESTYLE gives a width in twips and a colour. LINESTYLE2 adds cap and join styles, a
miter limit, and an optional fill in place of the colour (spec pp. 123-125). LINESTYLE has
round caps and round joins.

- Edges with the same line style chain into one path when an edge starts where the last one
  ended. A path whose last point is its first is closed.
- Each straight piece of a path becomes a quad as wide as the line. A curve is flattened
  first, as for fills.
- Between two pieces that turn, the join fills the gap on the outer side. A round join is a
  disc. A bevel join is one triangle. A miter join runs to where the two outer edges meet,
  and bevels when that point is further than the limit times half the width.
- An open path gets a cap at each end. A round cap is a disc, a square cap reaches half the
  width past the end, and no cap stops at the end. A closed path has no caps; its first
  corner gets a join unless `NoClose` is set.
- A line thinner than one pixel draws one pixel wide, which is how Flash draws a hairline.

## Morph shapes

DefineMorphShape (46) and DefineMorphShape2 (84) hold one shape in two forms, a start and an
end. A placement's `Ratio` picks a form between them: 0 is the start and 65535 the end.

| Field | Type | Note |
| --- | --- | --- |
| `CharacterId` | UI16 | |
| `StartBounds`, `EndBounds` | RECT | |
| `StartEdgeBounds`, `EndEdgeBounds` | RECT | DefineMorphShape2 only |
| Flags | UI8 | DefineMorphShape2 only: 6 reserved bits, then the two stroke scaling flags |
| `Offset` | UI32 | Bytes from the end of this field to `EndEdges` |
| `MorphFillStyles` | MORPHFILLSTYLEARRAY | UI8 count, 0xFF escapes to a UI16 count |
| `MorphLineStyles` | MORPHLINESTYLEARRAY | The same count rule |
| `StartEdges`, `EndEdges` | SHAPE | Index bit widths, then the records |

Each morph style holds a start and an end value of every field, in that order: two RGBA
colours, two matrices, and gradient records of start ratio, start colour, end ratio, end
colour. A bitmap fill has one bitmap id and two matrices. MORPHLINESTYLE holds two widths and
two colours. MORPHLINESTYLE2 holds two widths, the LINESTYLE2 flag bits, the miter limit when
the join is a miter, and then two colours or a morph fill. Colours are always RGBA.

The two forms must have the same number of edges. The start form carries the styles; the end
form only moves the pen. So edge n of the start pairs with edge n of the end. At a ratio, each
point, colour, width, matrix term, and gradient stop moves in a straight line from its start
value to its end value. A straight edge paired with a curve becomes a curve whose control
point is the middle of the line.

Two layout facts the spec leaves open:

- The spec gives the MORPHGRADIENT count as a full byte. OpenSky reads it as GRADIENT packs it:
  2 bits spread mode, 2 bits interpolation, and a 4-bit count. The two readings agree for a
  file that sets no spread or interpolation bits.
- A focal radial morph fill (type 0x13) reads a start and an end FIXED8 focal point after the
  records.

No vanilla movie holds a morph shape (`openskycli swf sweep`), so neither fact is confirmed
on the install. A form pair with different edge counts fails to parse and loses only its own
character.

Only timeline placements set a ratio, so the ratios a movie uses are known once it is decoded.
OpenSky turns each pair of morph and ratio into a plain shape character with a free id, and
points the placements at it. A move that only changes the ratio then swaps the shape at that
depth, and every later step draws shapes alone. A morph placed by a button record is not
expanded and draws nothing.

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
