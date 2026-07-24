---
type: File Format
title: SWF container (FWS/CWS)
description: On-disk layout of SWF UI files - container framing, shape tags with
  tessellation, bitmap/font/text tags, and the display-list control tags.
tags: [format, swf, ui, scaleform]
timestamp: 2026-07-24T00:00:00Z
---

# SWF container (FWS/CWS)

Skyrim's interface is authored in Adobe SWF and played back by Scaleform GFx.
Milestone 8.2.1 decodes the container: signature and compression, the fixed
header fields, and the flat tag stream. Milestone 8.2.2 adds the shape
definition tags (with CPU tessellation) and the bitmap definition tags.
Milestone 8.2.3 adds the font tags (glyph extraction) and the static-text tags,
plus the Scaleform `fontconfig.txt` alias mapping. Milestone 8.2.4 adds the
display-list control tags, sprite timelines, and asset imports — everything the
renderer needs to draw a movie's first frame
([screen-space UI layer](/rendering/ui.md)).

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

## Font tags — DefineFont2 (48), DefineFont3 (75)

Reference: spec chapter 10 "Fonts and Text" (pp. 176-182). Impl:
`opensky/Formats/SWF/SWFFont.swift` (value types),
`SWFFontParser.swift` (DefineFont2/3), `SWFFontCompanionParser.swift`
(companion tags).

Tag body: `FontID` UI16, a flag byte (`HasLayout`, `ShiftJIS`, `SmallText`,
`ANSI`, `WideOffsets`, `WideCodes`, `Italic`, `Bold`, MSB first), `LanguageCode`
UI8, a length-prefixed `FontName`, `NumGlyphs` UI16, then:

* OffsetTable — `NumGlyphs` entries plus a trailing `CodeTableOffset`, each
  UI32 when `WideOffsets` else UI16. All offsets are measured from the start of
  the OffsetTable (immediately after `NumGlyphs`). OpenSky slices each glyph's
  SHAPE from the body using these offsets rather than parsing sequentially, so
  any per-glyph padding is irrelevant.
* GlyphShapeTable — one bare SHAPE per glyph (NumFillBits/NumLineBits + shape
  records, no style arrays), decoded through
  `SWFShapeDefinition.parseGlyphSegments(_:)`; fill indices follow the glyph
  convention (0 = off, 1 = on).
* CodeTable — `NumGlyphs` character codes, UI16 when `WideCodes` else UI8.
* Layout (only when `FontFlagsHasLayout`): `FontAscent`/`FontDescent`/
  `FontLeading` SI16, a `FontAdvanceTable` of SI16 advances, a `FontBoundsTable`
  of bit-packed RECTs (one per glyph), then `KerningCount` UI16 and the
  KERNINGRECORDs (code pair sized by `WideCodes`, SI16 adjustment).

DefineFont3 is byte-identical to DefineFont2 except its glyph and layout
coordinates use a 20x-finer EM square (spec p. 179). The decoded font exposes
`unitsPerEM` (1024 for DefineFont2, 20480 for DefineFont3), so a consumer scales
any glyph coordinate by `emPixelSize / unitsPerEM` to reach pixels regardless of
tag version — the EM square equals one font-size unit.

Defensive cases: a device-font placeholder with `NumGlyphs == 0` omits the
OffsetTable, CodeTable, and layout entirely (observed in `hudmenu.swf`); it
decodes to an empty font rather than over-reading. Malformed offsets throw
`SWFFontError.glyphOffsetOutOfRange`; a truncated body throws the underlying
`BinaryReaderError` / `SWFBitReaderError`.

Companion tags decode minimally (`SWFFontCompanionParser`) and are retained but
not applied — OpenSky rasterizes glyphs through its own CoreGraphics coverage
path, so the FlashType hinting is parsed-and-ignored:

* DefineFontAlignZones (73): `FontID` UI16 and the `CSMTableHint` (UB[2]); the
  per-glyph ZONERECORD table (which needs the referenced font's glyph count to
  size) is kept raw.
* CSMTextSettings (74): `TextID`, `UseFlashType`, `GridFit`, and the
  `Thickness`/`Sharpness` FLOAT32 hints.
* DefineFontName (88): the full font name and copyright strings.

## Glyph rasterization

Impl: `opensky/Formats/SWF/SWFGlyphPath.swift`, plus
`UIGlyphAtlas.swfEntry(...)` — see [Screen-space UI layer](/rendering/ui.md) for
the atlas side. `SWFGlyphPath.makePath(segments:unitsPerEM:emPixelSize:)` builds
a CoreGraphics `CGPath` from a glyph's straight + quadratic edges, scaled by
`emPixelSize / unitsPerEM` and flipped from SWF's y-down glyph space to
CoreGraphics y-up with the baseline at the origin. The glyph fills even-odd per
SWF glyph semantics. An empty glyph (no segments) yields nil, drawing no quad.

## Static text tags — DefineText (11), DefineText2 (33), DefineEditText (37)

Reference: spec chapter 10 (pp. 173-177). Impl:
`opensky/Formats/SWF/SWFText.swift` (DefineText/2),
`SWFEditText.swift` (DefineEditText).

DefineText/DefineText2 body: `CharacterID` UI16, `TextBounds` RECT, `TextMatrix`
MATRIX, `GlyphBits` UI8, `AdvanceBits` UI8, then a run of TEXTRECORDs terminated
by a zero byte. Each TEXTRECORD's flag byte (byte-aligned) selects optional
state changes — font id + text height, color, x offset, y offset — applied in
that spec order, then `GlyphCount` UI8 and that many GLYPHENTRYs of
`GlyphIndex` UB[GlyphBits] + `GlyphAdvance` SB[AdvanceBits] (bit-packed; the next
record re-aligns). State fields absent from a record inherit the value carried
by earlier records. DefineText2 stores RGBA colors where DefineText stores RGB.
The glyph indices point into the record's active font's glyph table, so static
text lays out directly from the record data (no CoreText shaping).

DefineEditText body: `CharacterID` UI16, `Bounds` RECT, then a 16-bit flag word
(`HasText`, `WordWrap`, `Multiline`, `Password`, `ReadOnly`, `HasTextColor`,
`HasMaxLength`, `HasFont`, `HasFontClass`, `AutoSize`, `HasLayout`, `NoSelect`,
`Border`, `WasStatic`, `HTML`, `UseOutlines`, MSB first). Then, gated by the
flags: `FontID` (HasFont), `FontClass` STRING (HasFontClass), `FontHeight`
(HasFont or HasFontClass), `TextColor` RGBA (HasTextColor), `MaxLength`
(HasMaxLength), a layout block (align, margins, indent, leading — HasLayout), a
`VariableName` STRING, and `InitialText` STRING (HasText). STRINGs are
null-terminated UTF-8 (SWF 6+) with a CP1252 fallback. For static rendering the
plain-text content is the target: HTML fields keep the raw markup verbatim and
expose a tag-stripped `plainText`; full HTML text layout is deferred to 8.3.x.

Alignment note (as with shapes, the spec marks only RECT/MATRIX byte-aligned):
OpenSky byte-aligns before the DefineEditText flag word and treats it as two
whole bytes, which keeps the following UI16 fields aligned. All vanilla text
tags decode cleanly under this rule.

## fontconfig.txt (Scaleform GFx font mapping)

Impl: `opensky/Formats/SWF/SWFFontConfig.swift` (parser),
`SWFFontLibrary.swift` (resolver). The game ships `Interface/fontconfig.txt`,
read via the VFS (`vfs.contents(forPath: "interface\\fontconfig.txt")`). It maps
logical font aliases to font names defined inside fontlib movies.

This grammar is OBSERVED behavior, not a published specification (open GFx
documentation is thin) — the subset OpenSky implements:

* `fontlib "<Interface\movie.swf>"` — declare a movie whose fonts back the
  aliases. The name is an install-relative path (already carries the
  `Interface\` prefix in vanilla).
* `map "$Alias" = "FontName" [Style ...]` — map a logical alias (e.g.
  `$EverywhereFont`) to a font name, with optional trailing style keywords
  (`Normal`, `Bold`, `Italic`, ...) retained but not used for matching.
* `#` begins a comment to the end of the line (outside quotes); blank lines are
  ignored.

Any other non-empty line (e.g. vanilla's `mapdefault`, `validNameChars`) is
retained verbatim in `unrecognizedLines` and reported, never silently dropped —
the uncertainty is surfaced rather than guessed away.

Resolution: `SWFFontLibrary.register(movie:file:)` decodes a movie's
DefineFont2/3 tags and its ExportAssets (56) name table, indexing each font by
its export name and its internal font name. `resolve(alias:config:)` looks the
alias up in the config's `map` directives, then finds a registered font with
that name (exact, then case-insensitive). GFx font naming — whether a `map`
name matches an export name or an internal name — is itself observed, so both
are tried.

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

## Display-list tags

Reference: spec chapter 3 "The display list" (pp. 31-39) plus DefineSprite in
chapter 13 (p. 233). Impl: `opensky/Formats/SWF/SWFDisplayList.swift` (tag
decode), `SWFMovie.swift` (dictionary + frame-1 list), `SWFScene.swift`
(flattening to draw commands), `SWFTransform.swift` / `SWFColorTransform.swift`
(the affine and color algebra).

A movie's visible content is a depth-keyed list of placed characters. Control
tags mutate that list; `ShowFrame` (1) publishes it. OpenSky builds the list up
to the **first** `ShowFrame` — frame 1 — and freezes it there; later frames are
timeline work (8.3.x). Later define tags still enter the dictionary.

| tag | name              | body                                                     |
| --- | ----------------- | -------------------------------------------------------- |
| 4   | PlaceObject       | `CharacterId` UI16, `Depth` UI16, MATRIX, optional CXFORM |
| 26  | PlaceObject2      | flag byte, `Depth` UI16, then the gated field run         |
| 70  | PlaceObject3      | two flag bytes, `Depth` UI16, class name, field run, extras |
| 5   | RemoveObject      | `CharacterId` UI16, `Depth` UI16                          |
| 28  | RemoveObject2     | `Depth` UI16                                              |
| 1   | ShowFrame         | empty                                                     |
| 9   | SetBackgroundColor| RGB record                                                |
| 39  | DefineSprite      | `SpriteID` UI16, `FrameCount` UI16, nested tag stream     |

PlaceObject2's flag byte, MSB to LSB: `HasClipActions`, `HasClipDepth`,
`HasName`, `HasRatio`, `HasColorTransform`, `HasMatrix`, `HasCharacter`,
`Move`. The gated fields follow in that (reverse) order: `CharacterId` UI16,
MATRIX, CXFORMWITHALPHA, `Ratio` UI16, `Name` STRING, `ClipDepth` UI16.
PlaceObject3 keeps that byte and adds a second one (MSB to LSB: reserved,
`OpaqueBackground`, `HasVisible`, `HasImage`, `HasClassName`,
`HasCacheAsBitmap`, `HasBlendMode`, `HasFilterList`); its class name precedes
the character id, and `SurfaceFilterList`, `BlendMode` UI8, `BitmapCache` UI8,
`Visible` UI8, and an RGBA `BackgroundColor` follow the clip depth.

Place semantics (spec p. 34), applied by `SWFDisplayListBuilder`:

* `Move` clear + character id -> place a new character at the depth.
* `Move` set, no character id -> modify the object already at the depth; the
  fields present overwrite, the rest persist. An empty depth here is a dangling
  placement: skipped and counted, never fatal.
* `Move` set + character id -> replace the character at the depth. The spec
  leaves the unspecified fields undefined; observed Flash/GFx behavior keeps the
  previous state, which is what OpenSky does.
* `RemoveObject`/`RemoveObject2` clear the depth (the character id in tag 5 is
  informational — removal is by depth).

MATRIX (spec p. 23) is bit-packed and byte-aligned: `HasScale` UB[1] (then
`NScaleBits` UB[5] and two SB 16.16 fixed-point terms), `HasRotate` UB[1] (same
shape), then `NTranslateBits` UB[5] and two SB translations in twips. Semantics:
`x' = x*ScaleX + y*RotateSkew1 + TranslateX`, `y' = x*RotateSkew0 + y*ScaleY +
TranslateY`. `SWFTransform` mirrors those field names so the concatenation
algebra stays checkable against the spec.

CXFORM / CXFORMWITHALPHA (spec pp. 24-25), also byte-aligned: `HasAddTerms`
UB[1], `HasMultTerms` UB[1], `Nbits` UB[4], then the multiply terms
(R, G, B[, A] as SB[Nbits], 8.8 fixed point — divide by 256) followed by the add
terms (same width, the -255..255 integer domain — divide by 255). Application is
`clamp(color * multiply + add, 0, 1)` in the straight-alpha domain; nesting
concatenates as `multiply = outer.multiply * inner.multiply`,
`add = outer.multiply * inner.add + outer.add`.

Clip layers: a placement carrying `ClipDepth` draws no color of its own and
masks every placement at depths `(depth, clipDepth]`. Ranges may interleave, so
`SWFScene` emits `beginClip`/`endClip` commands around the affected draws and
records how many masks are active per draw; the renderer turns that into a
counting stencil ([screen-space UI layer](/rendering/ui.md)).

DefineSprite (39) carries its own End-terminated tag stream in its body — the
same `RECORDHEADER` framing as the top level (`SWFFile.parseTags` is shared).
Each sprite keeps its own frame-1 display list, and the scene flattener expands
a placed sprite recursively, concatenating the parent transform and color
transform into every child (recursion bounded at 16 levels defensively; vanilla
nesting is shallow).

Parsed and deliberately not rendered, each counted so the deferral stays
measured: PlaceObject3 `SurfaceFilterList` (framed per spec chapter 8, pp.
143-151 — each `FilterID` selects a fixed body size, except GradientGlow/
GradientBevel whose size depends on `NumColors` and Convolution whose size
depends on the matrix dimensions), `BlendMode`, and `ClipActions` (OpenSky runs
no ActionScript yet). `Ratio` is decoded and retained; morph shapes are not
implemented.

## ImportAssets / ImportAssets2

Reference: spec chapter 14 "Sharing fonts and other assets" — ImportAssets (57,
p. 285) and ImportAssets2 (71, p. 286). Impl:
`opensky/Formats/SWF/SWFImportAssets.swift`.

Body: `URL` STRING, then (ImportAssets2 only) two reserved bytes (1 and 0),
`Count` UI16, and `Count` pairs of `CharacterId` UI16 + `Name` STRING. The
importing movie uses those character ids as if it had defined them; the actual
character lives in the named source movie.

This matters for text: vanilla Interface movies import their fonts from the
fontlib movies, so an edit text's `FontID` usually names a character the movie
never defines (523 of the 595 vanilla fields with content, before imports were
honored). `SWFMovie.importedNames` keeps the id -> export-name mapping and
`SWFMovieScene.resolvedFont(for:)` resolves that name through fontconfig, the
same path a zero-glyph placeholder font takes.

## Not implemented (yet)

* `ZWS` (LZMA) body decompression.
* Stroke tessellation for line styles (decoded, not meshed — see above).
* HTML/rich text layout in DefineEditText (raw markup retained, plain-text
  stripped) and dynamic text bound to a variable name (8.3.x).
* Frames past the first: the display list freezes at the first `ShowFrame`, so
  timeline playback, `Ratio` morph shapes, and button states wait for 8.3.x.
* PlaceObject3 filters and blend modes (framed, counted, not applied) and
  `ClipActions` (recorded, never executed — no ActionScript yet).
* ActionScript and GFx extension tags (8.3.x).

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

Milestone 8.2.3 tests: `openskyTests/SWFFontTests.swift` (DefineFont2/3 glyphs +
code tables, wide offsets/codes, layout with advances/bounds/kerning, the
companion tags, truncation) over `SWFFontBodyBuilder`;
`SWFTextTests.swift` (DefineText mixed style records, DefineText2 RGBA,
DefineEditText flag combinations, HTML strip, truncation) over
`SWFTextBodyBuilder` / `SWFEditTextBodyBuilder`; `SWFFontConfigTests.swift`
(directive/comment/unrecognized parsing, alias resolution by internal + export
name) with synthetic fontlib movies; and `SWFGlyphPathTests.swift` (y-flip,
DefineFont2 vs DefineFont3 scaling, conversion determinism, atlas caching).

Milestone 8.2.4 tests: `openskyTests/SWFDisplayListTests.swift` (CXFORM/
CXFORMWITHALPHA decode + algebra, all three PlaceObject versions with every
gated field, filters and blend modes, removals, background color, truncation,
and the `SWFTransform`/viewport math) over `openskyTests/SWFDisplayFixture.swift`
(bit-exact place/remove/sprite tag builders); `SWFMovieTests.swift` (dictionary
building, place/move/replace/remove, ShowFrame freeze, sprite frame 1, clip-depth
command ranges with interleaving, tallies); `SWFTextLayoutTests.swift` (record
state inheritance, kerning, wrap, alignment, missing glyphs); and
`SWFImportAssetsTests.swift` (both import tags, imported-font resolution).

`openskycli swf sweep` ([CLI dev tool](/tools/cli.md)) is the milestone 8.2.1 +
8.2.2 + 8.2.3 + 8.2.4 gate: every archive/loose path under `interface\` ending
`.swf` parsed through `SWFFile` with a known/unknown tag-code tally, every shape
tag decoded and tessellated, every bitmap tag decoded to RGBA, every
DefineFont2/3 and DefineText/2/EditText tag decoded (glyphs also converted to
`CGPath`), every frame-1 display list assembled and flattened into draw commands
with its edit texts laid out, and a fontconfig alias-resolution report; any
shape/bitmap/font/text/display-list decode failure fails the sweep.
`openskycli swf render-sweep` is the GPU half: every movie is assigned to the
production renderer and its frame 1 rendered offscreen.

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

Fonts and text (milestone 8.2.3): 97 fonts decoded with 0 failures — 96 carry a
layout block; 54,988 glyphs total (54,987 code-mapped, 34,379 with a drawable
CGPath — the remainder are blank glyphs such as spaces), 17,336 kerning pairs.
One DefineFont3 in `hudmenu.swf` is a 0-glyph device-font placeholder. Text:
665 DefineEditText (644 with initial text, 571 HTML) and 0 DefineText/DefineText2
— vanilla Skyrim UI text is entirely dynamic (DefineEditText bound to variables),
so no static DefineText blocks appear. fontconfig: `Interface/fontconfig.txt`
declares 3 fontlibs (`fonts_console.swf`, `fonts_en.swf`, `fonts_cclub.swf`) and
20 `map` aliases, all 20 resolving against the fontlib movies; the `mapdefault`
and `validNameChars` directives are outside the implemented subset and reported
as unrecognized.

Display lists (milestone 8.2.4): 53 movies decoded with 0 failures, 130 frame-1
placements on the main timelines (5 movies place nothing at frame 1), 53
`SetBackgroundColor` tags. Place tags across the main timelines and every
sprite's frame 1: 0 PlaceObject, 5,926 PlaceObject2, 281 PlaceObject3, 3,202
`ShowFrame`, 3,971 sprites, 30 clip layers — and **0 moves and 0 removals**.
Vanilla frame 1 only places; the modify/replace/remove paths exist for
correctness and are exercised by unit tests, not by vanilla's first frame.
Flattening those lists yields 1,207 shape draws, 695 edit-text draws, 0
static-text draws (vanilla has no DefineText), and 22 clip ranges, with 20
placements referencing something undrawable. Recorded-but-deferred features:
233 filters, 25 blend modes, 122 `ClipActions` blocks; 0 dangling placements.

Text through the display list: all 595 edit texts that carry content resolve a
font and lay out 15,238 glyphs with 0 missing glyphs (100 further fields are
empty). That depends on ImportAssets2 — without it 523 of those fields resolve
nothing. One font name remains unresolved across the whole install.

An important consequence for acceptance: 1,032 of the 1,902 frame-1 draws
resolve to alpha 0 through their CXFORM. Vanilla menus hide most of their
content at frame 1 and reveal it from ActionScript, so a correct frame-1 render
of many movies is legitimately blank — 20 of the 53 movies change no pixels at
all, and 10 of them (the fontlib and asset-only movies) produce no draws
at all.

GPU frame-1 render (`openskycli swf render-sweep --size 960x600`): 53 movies,
53 rendered, 0 failed, 2,277 draws, 692,328 triangles, 44 stencil mask draws.
Per-movie highlights: `modmanager.swf` 275 draws / 372,128 changed pixels,
`creationclubmenu.swf` 97 draws with 164 glyphs / 344,207, `quest_journal.swf`
(rendered on its own) 612 draws with 1,535 glyphs / 237,525, `console.swf`
4 draws with 12 glyphs / 239,216, `hudmenu.swf` 185 draws with 24 mask draws /
7,637. Glyph
counts in a full 53-movie sweep under-report late movies because the shared
glyph atlas fills up (issue #127); `--movie <name>` renders one movie with a
fresh renderer for honest numbers. Full output: `logs/swf-render-sweep.log`,
optional frame captures under `logs/swf-frames/` — both gitignored, never
committed (AGENTS.md Legal & IP: a rendered vanilla movie embeds game art).
