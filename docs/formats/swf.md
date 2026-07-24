---
type: File Format
title: SWF container (FWS/CWS)
description: On-disk layout of SWF UI files - container framing, shape tags with
  tessellation, and bitmap tags.
tags: [format, swf, ui, scaleform]
timestamp: 2026-07-24T00:00:00Z
---

# SWF container (FWS/CWS)

Skyrim's interface is authored in Adobe SWF and played back by Scaleform GFx.
Milestone 8.2.1 decodes the container: signature and compression, the fixed
header fields, and the flat tag stream. Milestone 8.2.2 adds the shape
definition tags (with CPU tessellation) and the bitmap definition tags. Fonts,
text, and the display list follow in 8.2.3-8.2.4.

Reference: Adobe SWF File Format Specification, version 19 (public Adobe
document). Impl: `opensky/Formats/SWF/`. All byte-aligned integers are
little-endian; the FrameSize RECT is bit-packed most-significant-bit first.

## Header — first 8 bytes, uncompressed

| offset | type  | field      | notes                                  |
| ------ | ----- | ---------- | -------------------------------------- |
| 0x00   | char3 | Signature  | `FWS`, `CWS`, or `ZWS` (below)         |
| 0x03   | uint8 | Version    | SWF version                            |
| 0x04   | uint32| FileLength | uncompressed total, includes this header |

The three signatures select body compression:

* `FWS` — uncompressed. The body follows the header verbatim.
* `CWS` — the body (everything after byte 8) is one zlib stream (RFC 1950, with
  the CMF/FLG header). Introduced with SWF 6. Its decompressed size is
  `FileLength - 8`. OpenSky decodes it through `opensky/Formats/Zlib.swift`,
  which validates CMF/FLG and the output length.
* `ZWS` — LZMA-compressed body (SWF 13+). Recognized but not decoded at this
  stage; it raises `SWFError.unsupportedCompression`.

An unknown signature raises `SWFError.notASWF`; a `FileLength` below 8 raises
`SWFError.invalidFileLength`. The header's first eight bytes are always read
uncompressed — only the body past byte 8 is compressed.

## Header body — after decompression

Parsed from the (decompressed) body, in order:

1. FrameSize — a RECT giving the stage bounds in twips (1/20 px). Bit-packed
   MSB-first: `Nbits = UB[5]`, then `Xmin`, `Xmax`, `Ymin`, `Ymax`, each a
   signed `SB[Nbits]`. The stream byte-aligns after the RECT.
2. FrameRate — `UI16` little-endian read as 8.8 fixed point: the frame rate is
   the stored value divided by 256.
3. FrameCount — `UI16` little-endian, number of frames in the main timeline.

The bit-packed reads go through `SWFBitReader` (`readUB` / `readSB`), the only
MSB-first bit reader in the repo; byte-aligned reads use the shared
`BinaryReader`.

## Tag stream

The body after the header fields is a flat sequence of tags. Each begins with a
RECORDHEADER:

* `UI16` little-endian. Tag code = `value >> 6`; length = `value & 0x3F`.
* A length of `0x3F` is the "long" form: the real length follows as a `UI32`
  little-endian.
* The body is exactly that many bytes and is left undecoded at this stage.

The stream terminates at the End tag (code 0, length 0), which OpenSky keeps as
the final entry in the tag list. Bytes after the End tag are ignored. A record
header or body that runs past the end of the data raises a typed error
(`BinaryReaderError` / `SWFBitReaderError`) rather than crashing or over-reading.

## Known-tag table

`SWFTagName.name(forCode:)` maps standard Adobe tag codes to their names (End=0,
ShowFrame=1, DefineShape=2, ... EnableTelemetry=93), and `isKnown` reports
whether a code is in the Adobe specification. This drives a known/unknown tally
when sweeping the game's `.swf` files.

Scaleform GFx adds its own extension tags in roughly the 1000+ code range. Those
are deliberately not part of the Adobe specification and stay "unknown" here;
decoding them is out of scope for the container milestone.

## Shape tags — DefineShape (2), DefineShape2 (22), DefineShape3 (32), DefineShape4 (83)

Reference: spec chapter 6 "Shapes" (pp. 119-133) and chapter 7 "Gradients"
(pp. 134-136). Impl: `opensky/Formats/SWF/SWFShape.swift` (tag layout,
`SWFShapeDefinition.parse(tag:)`), `SWFShapeParser.swift` (bit-level
structures), `SWFShapeTypes.swift` (style value types).

Tag body: `ShapeId` UI16, `ShapeBounds` RECT, then SHAPEWITHSTYLE.
DefineShape4 inserts `EdgeBounds` RECT plus a flag byte (Reserved UB[5],
`UsesFillWindingRule` UB[1] — SWF 10+, `UsesNonScalingStrokes`,
`UsesScalingStrokes`) between the bounds and the styles.

SHAPEWITHSTYLE = FILLSTYLEARRAY, LINESTYLEARRAY, `NumFillBits` UB[4],
`NumLineBits` UB[4], then shape records. Style arrays index from 1; index 0
means no fill / no stroke.

Per-version rules:

* Colors are RGB in DefineShape/DefineShape2 and RGBA in DefineShape3/4
  (FILLSTYLE, LINESTYLE, and GRADRECORD color fields alike).
* The 0xFF style-count escape to a UI16 extended count applies to DefineShape2
  and later (spec FILLSTYLEARRAY, p. 122); DefineShape reads 0xFF as a literal
  count of 255.
* DefineShape4 line styles are LINESTYLE2 (cap/join/scaling flags, optional
  8.8 miter limit, and either an RGBA color or a stroke FILLSTYLE); earlier
  versions use the width + color LINESTYLE.
* Focal radial gradients (fill type 0x13, FOCALGRADIENT with a FIXED8 focal
  point) belong to DefineShape4 per the spec; the parser accepts the type
  leniently in any version.

FILLSTYLE types: 0x00 solid, 0x10 linear gradient, 0x12 radial gradient, 0x13
focal radial gradient, 0x40/0x41/0x42/0x43 bitmap (repeating/clipped and
smoothed/non-smoothed variants; the fill carries a bitmap character id plus a
MATRIX).

Shape records are bit-packed and not byte-aligned: a TypeFlag bit selects
edge records (StraightEdgeRecord general/vertical/horizontal deltas,
CurvedEdgeRecord quadratic Bezier control + anchor deltas, both SB[NumBits+2])
or non-edge records (EndShapeRecord = six zero bits; StyleChangeRecord with
MoveTo — absolute, relative to the shape origin — FillStyle0/FillStyle1/
LineStyle selections read with the current index bit widths, and optional
replacement style arrays). `SWFShapeParser` flattens replacement arrays into
single global style lists and rebases the record indices, so a
`SWFShapeSegment` index is stable for the whole shape. A bare SHAPE (glyphs,
for 8.2.3) parses through `SWFShapeDefinition.parseGlyphSegments(_:)` with
pass-through indices.

Alignment notes (the spec marks RECT/MATRIX "must be byte aligned" but is
silent elsewhere): GRADIENT after the fill's MATRIX and the `NumFillBits`
field after the style arrays are both treated as byte-aligned. Observed
encoders agree — all 53 vanilla movies (2,677 shapes) parse cleanly under this
rule with zero failures.

## Shape tessellation

Impl: `opensky/Formats/SWF/SWFShapeTessellator.swift`. Output is
`SWFShapeMesh`: a twip-space triangle list (`[SIMD2<Float>]`, three vertices
per triangle) with `FillRun` ranges grouping triangles per fill style index.
`SWFShapeCache` memoizes the mesh per shape character id; 8.2.4's renderer
consumes this cache. GPU upload is out of scope for 8.2.2.

* Quadratic edges flatten deterministically: uniform subdivision with the step
  count derived from the control point's deviation from the chord midpoint
  (tolerance 1 twip, 64-step cap).
* FillStyle0 is the fill left of an edge's travel direction, FillStyle1 the
  right (spec p. 128). For each fill, fill1 edges enter the sweep forward and
  fill0 edges reversed, giving a consistently oriented boundary; an edge with
  the same fill on both sides cancels itself, so interior edges never split a
  fill.
* Triangulation is a horizontal-band trapezoid sweep (bands split at every
  segment endpoint y; spans selected by fill rule; two triangles per
  trapezoid, slivers dropped). Holes and disjoint contours need no contour
  chaining. The fill rule is even-odd by default and nonzero winding when
  DefineShape4 sets `UsesFillWindingRule`.
* Deferred: stroke tessellation. Line styles (including LINESTYLE2 caps,
  joins, and stroke fills) are fully decoded and carried on segments, but no
  stroke geometry is emitted yet — vanilla UI art is overwhelmingly
  fill-based, and stroke meshes need the 8.2.4 draw path to pick a pixel
  scale.

## Bitmap tags

Reference: spec chapter 8 "Bitmaps" (pp. 137-143). Impl:
`opensky/Formats/SWF/SWFBitmap.swift` (lossless) and `SWFBitmapJPEG.swift`
(JPEG family via ImageIO/CoreGraphics — Apple frameworks, no third-party
codec). All decoders produce `SWFBitmap`: RGBA8 row-major pixels, dimensions,
a `premultipliedAlpha` flag, and the detected source format.
`SWFBitmapDecoder.decode(tag:jpegTables:)` dispatches on the tag code.

DefineBitsLossless (20) / DefineBitsLossless2 (36): `CharacterID` UI16,
`BitmapFormat` UI8, width/height UI16, then one zlib stream. Formats: 3 =
8-bit colormapped (UI8 `BitmapColorTableSize` stores count minus one; RGB
table for tag 20, RGBA for tag 36; index rows padded to 32-bit boundaries),
4 = PIX15 (tag 20 only; 1 reserved + 5/5/5 bits MSB-first, rows padded), 5 =
PIX24 (tag 20: reserved byte + RGB) or 32-bit ARGB (tag 36). The expected
decompressed size is computed from format, dimensions, and row padding and
validated by `Zlib.decompress`. Per the spec (p. 143) the tag-36 ARGB pixel
data is already premultiplied by alpha and is passed through with
`premultipliedAlpha == true`. Open question: the spec states the premultiply
rule only for ARGB data, not for RGBA colormap entries — colormapped
Lossless2 output is flagged non-premultiplied here until observed otherwise.

JPEG family: JPEGTables (8) holds the movie-wide encoding tables for
DefineBits (6), whose body is only the scan — both streams carry SOI/EOI, so
the decodable image is tables-without-EOI + scan-without-SOI.
DefineBitsJPEG2 (21) is a self-contained image. DefineBitsJPEG3 (35) adds
`AlphaDataOffset` UI32 and a zlib-compressed one-byte-per-pixel alpha plane
after the image; DefineBitsJPEG4 (90) additionally inserts a `DeblockParam`
UI16 (8.8 fixed point; decoded, not applied). Pre-SWF8 payloads may carry an
erroneous `FF D9 FF D8` prefix, which is stripped. From SWF 8 the payload may
be PNG or GIF89a, detected by signature; the alpha plane applies to JPEG
payloads only (spec p. 139). JPEG color with a substituted alpha plane is
straight (non-premultiplied); PNG/GIF decode through a premultiplied
CoreGraphics context and are flagged accordingly.

## Not implemented (yet)

* `ZWS` (LZMA) body decompression.
* Stroke tessellation for line styles (decoded, not meshed — see above).
* Fonts, text, the display list, and ActionScript / GFx extension tags
  (milestones 8.2.3-8.2.4, 8.3.x).

## Verification

Unit tests: synthetic in-code fixtures (`openskyTests/SWFFileTests.swift`,
`openskyTests/SWFFixture.swift`) cover FWS field parsing, CWS round-trip, short
and long tags, End-tag termination with trailing bytes, unknown-tag passthrough,
the tag-name table, and rejection of bad signatures, `ZWS`, truncated headers,
truncated tag bodies, and a RECT running past the end.

Milestone 8.2.2 tests: `openskyTests/SWFShapeTests.swift` (styles, gradients,
bitmap fills, LINESTYLE2, extended counts, new-style flattening, glyph SHAPE,
malformed bodies) over the bit-exact `SWFShapeBodyBuilder` fixture
(`openskyTests/SWFShapeFixture.swift`), `SWFShapeTessellatorTests.swift`
(area-verified squares, holes, fill0/fill1 sides, shared interior edges,
winding vs. even-odd, deterministic curve flattening, cache), and
`SWFBitmapTests.swift` (all lossless formats with row padding, ARGB
premultiply, JPEG2/3/4, JPEGTables merge, PNG signature detection, erroneous
header stripping, typed failures) with ImageIO-generated synthetic payloads.

`openskycli swf sweep` ([CLI dev tool](/tools/cli.md)) is the milestone 8.2.1 +
8.2.2 gate: every archive/loose path under `interface\` ending `.swf` parsed
through `SWFFile` with a known/unknown tag-code tally, every shape tag decoded
and tessellated, and every bitmap tag decoded to RGBA; any shape/bitmap decode
failure fails the sweep.

## Vanilla sweep results

`openskycli swf sweep` against the vanilla install (`Skyrim - Interface.bsa`):
53 `.swf` movies, all 53 parsed (0 `ZWS`/unsupported, 0 failed). 14,477 tags
total, all 14,477 known to the Adobe tag table — no unknown or GFx-extension
(~1000+) tag codes appeared in vanilla `Interface/*.swf`. Versions observed:
mostly SWF 15, with `racesex_menu.swf` at version 8 and `fonts_pl.swf` /
`fonts_ru.swf` / `gfxfontlib.swf` / `sharedcomponents.swf` at version 10.

Shapes and bitmaps (milestone 8.2.2): 2,677 shapes decoded and tessellated
with 0 failures — DefineShape 944, DefineShape2 1,097, DefineShape3 574,
DefineShape4 62 — producing 2,195,435 triangles. 453 bitmaps decoded with 0
failures: 451 DefineBitsLossless2 32-bit ARGB (`lossless32`) and 2 DefineBits
JPEG scans (`jpeg`) in `sharedcomponents.swf`, whose JPEGTables tag is empty
(0 bytes) — the scans are self-contained and decode without merged tables. No
colormapped/15-bit/24-bit lossless, DefineBitsJPEG2/3/4, PNG, or GIF payloads
appear in vanilla. Full per-file output: `logs/swf-shape-sweep.log`
(gitignored, not committed — AGENTS.md Legal & IP; reproduce with
`openskycli swf sweep`).
